package App::BloomUtils;

# AUTHORITY
# DATE
# DIST
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::ger;

our %SPEC;

my $desc = <<'_';

You supply lines of text from STDIN and it will output the bloom filter bits on
STDOUT. You can also customize `num_bits` (`m`) and `num_hashes` (`k`), or, more
easily, `num_items` and `fp_rate`. Some rules of thumb to remember:

* One byte per item in the input set gives about a 2% false positive rate. So if
  you expect two have 1024 elements, create a 1KB bloom filter with about 2%
  false positive rate. For other false positive rates:

    10%    -  4.8 bits per item
     1%    -  9.6 bits per item
     0.1%  - 14.4 bits per item
     0.01% - 19.2 bits per item

* Optimal number of hash functions is 0.7 times number of bits per item. Note
  that the number of hashes dominate performance. If you want higher
  performance, pick a smaller number of hashes. But for most cases, use the the
  optimal number of hash functions.

* What is an acceptable false positive rate? This depends on your needs. 1% (1
  in 100) or 0.1% (1 in 1,000) is a good start. If you want to make sure that
  user's chosen password is not in a known wordlist, a higher false positive
  rates will annoy your user more by rejecting her password more often, while
  lower false positive rates will require a higher memory usage.

Ref: https://corte.si/posts/code/bloom-filter-rules-of-thumb/index.html

_

$SPEC{gen_bloom_filter} = {
    v => 1.1,
    summary => 'Generate bloom filter',
    description => $desc1,
    args => {
        num_bits => {
            description => <<'_',

The default is 80000 (generates a ~10KB bloom filter). If you supply 10,000 items
(meaning 1 byte per 1 item) then the false positive rate will be ~2%. If you
supply fewer items the false positive rate is smaller and if you supply more
than 10,000 items the false positive rate will be higher.

_
            schema => 'uint*',
            #default => 8*10000,
            cmdline_aliases => {m=>{}},
        },
        num_hashes => {
            schema => 'num*',
            cmdline_aliases => {k=>{}},
            #default => 5.7,
        },
        num_items => {
            schema => 'uint*',
            cmdline_aliases => {n=>{}},
        },
        false_positive_rate => {
            schema => ['float*', max=>0.5],
            cmdline_aliases => {
                fp_rate => {},
                p => {},
            },
        },
    },
    'cmdline.skip_format' => 1,
    args_rels => {
        'choose_all&' => [
            [qw/num_bits num_hashes/],
            [qw/num_items false_positive_rate/],
        ],
        'choose_one' => [qw/num_bits num_items/],
    },
    examples => [
        {
            summary => 'Create a bloom filter for 100k items and 0.1% false-positive rate',
            argv => [qw/--num-items 100000 --fp-rate 0.1%/],
            'x.doc.show_result' => 0,
            test => 0,
        },
    ],
    links => [
        {url=>'prog:bloom-filter-calculator'},
    ],
};
sub gen_bloom_filter {
    require Algorithm::BloomFilter;

    my %args = @_;

    my ($m, $k);

    if (defined $args{num_items}) {
        my $res = bloom_filter_calculator(
            num_items => $args{num_items},
            false_positive_rate => $args{false_positive_rate},
            num_hashes_to_bits_per_item_ratio => 0.7,
        );
        return $res unless $res->[0] == 200;
        $m = int($res->[2]{m});
        $k = $res->[2]{k};
    } else {
        $m = $args{num_bits} // 80_000;
        $k = $args{num_hashes} // 5.7;
    }
    log_trace "Will be creating bloom filter with m=%d, k=%.1f", $m, $k;

    my $bf = Algorithm::BloomFilter->new($m, $k);
    my $i = 0;
    while (defined(my $line = <STDIN>)) {
        chomp $line;
        $bf->add($line);
        $i++;
        if (defined $args{num_items} && $i == $args{num_items}+1) {
            log_warn "You created bloom filter for num_items=%d, but now have added more than that", $args{num_items};
        }
    }

    print $bf->serialize;

    [200];
}

$SPEC{check_with_bloom_filter} = {
    v => 1.1,
    summary => 'Check with bloom filter',
    description => <<'_',

You supply the bloom filter in STDIN, items to check as arguments, and this
utility will print lines containing 0 or 1 depending on whether items in the
arguments are tested to be, respectively, not in the set (0) or probably in the
set (1).

_
    args => {
        items => {
            summary => 'Items to check',
            schema => ['array*', of=>'str*'],
            req => 1,
            pos => 0,
            greedy => 1,
        },
    },
    'cmdline.skip_format' => 1,
    links => [
    ],
};
sub check_with_bloom_filter {
    require Algorithm::BloomFilter;

    my %args = @_;

    my $bf_str = "";
    while (read(STDIN, my $block, 8192)) {
        $bf_str .= $block;
    }

    my $bf = Algorithm::BloomFilter->deserialize($bf_str);

    for (@{ $args{items} }) {
        say $bf->test($_) ? 1:0;
    }

    [200];
}

$SPEC{bloom_filter_calculator} = {
    v => 1.1,
    summary => 'Help calculate num_bits (m) and num_hashes (k)',
    description => $desc1,
    args => {
        num_items => {
            summary => 'Expected number of items to add to bloom filter',
            schema => 'posint*',
            pos => 0,
            req => 1,
            cmdline_aliases => {n=>{}},
        },
        false_positive_rate => {
            schema => ['float*', max=>0.5],
            default => 0.02,
            cmdline_aliases => {
                fp_rate => {},
                p => {},
            },
        },
        num_hashes => {
            schema => 'num*',
            cmdline_aliases => {k=>{}},
        },
        num_hashes_to_bits_per_item_ratio => {
            summary => '0.7 (the default) is optimal',
            schema => 'num*',
            default => 0.7,
        },
    },
    args_rels => {
        choose_one => [qw/num_hashes num_hashes_to_bits_per_item_ratio/],
    },
};
sub bloom_filter_calculator {
    my %args = @_;

    my $num_items = $args{num_items};
    my $fp_rate   = $args{false_positive_rate};

    my $num_bits = $num_items * log(1/$fp_rate)/ log(2)**2;
    my $num_bits_per_item = $num_bits / $num_items;
    my $num_hashes = $args{num_hashes} //
        (defined $args{num_hashes_to_bits_per_item_ratio} ? $args{num_hashes_to_bits_per_item_ratio}*$num_bits_per_item : undef) //
        ($num_bits / $num_items * log(2));
    my $num_hashes_to_bits_per_item_ratio = $args{num_hashes_to_bits_per_item_ratio} //
        $num_hashes / $num_bits_per_item;

    [200, "OK", {
        num_bits   => $num_bits,
        m          => $num_bits,
        num_items  => $num_items,
        n          => $num_items,
        num_hashes => $num_hashes,
        num_hashes_to_bits_per_item_ratio => $num_hashes_to_bits_per_item_ratio,
        k          => $num_hashes,
        fp_rate    => $fp_rate,
        p          => $fp_rate,
        num_bits_per_item => $num_bits / $num_items,
        'm/n'             => $num_bits / $num_items,
    }];
}

1;
#ABSTRACT: Utilities related to bloom filters

=head1 DESCRIPTION

This distributions provides the following command-line utilities:

# INSERT_EXECS_LIST

=cut
