package App::BloomUtils;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

our %SPEC;

$SPEC{gen_bloom_filter} = {
    v => 1.1,
    summary => 'Generate bloom filter',
    description => <<'_',

You supply lines of text from STDIN and it will output the bloom filter bits on
STDOUT. You can also customize `num_bits` (`m`) and `num_hashes` (`k`). Some
rules of thumb to remember:

* One byte per item in the input set gives about a 2% false positive rate. So if
  you expect two have 1024 elements, create a 1KB bloom filter with about 2%
  false positive rate. For other false positive rates:

    1%    -  9.6 bits per item
    0.1%  - 14.4 bits per item
    0.01% - 19.2 bits per item

* Optimal number of hash functions is 0.7 times number of bits per item.

* What is an acceptable false positive rate? This depends on your needs.

Ref: https://corte.si/posts/code/bloom-filter-rules-of-thumb/index.html

_
    args => {
        num_bits => {
            description => <<'_',

The default is 80000 (generates a ~10KB bloom filter). If you supply 10,000 items
(meaning 1 byte per 1 item) then the false positive rate will be ~2%. If you
supply fewer items the false positive rate is smaller and if you supply more
than 10,000 items the false positive rate will be higher.

_
            schema => 'num*',
            default => 8*10000,
            cmdline_aliases => {m=>{}},
        },
        num_hashes => {
            schema => 'num*',
            cmdline_aliases => {k=>{}},
            default => 5.7,
        },
    },
    'cmdline.skip_format' => 1,
    links => [
        {url=>'prog:bloom-filter-calculator'},
    ],
};
sub gen_bloom_filter {
    require Algorithm::BloomFilter;

    my %args = @_;

    my $m = $args{num_bits};
    my $k = $args{num_hashes};

    my $bf = Algorithm::BloomFilter->new($m, $k);
    while (defined(my $line = <STDIN>)) {
        chomp $line;
        $bf->add($line);
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
    description => <<'_',

Bloom filter is setup using two parameters: `num_bits` (`m`) which is the size
of the bloom filter (in bits) and `num_hashes` (`k`) which is the number of hash
functions to use which will determine the write and lookup speed.

Some rules of thumb:

* One byte per item in the input set gives about a 2% false positive rate. So if
  you expect two have 1024 elements, create a 1KB bloom filter with about 2%
  false positive rate. For other false positive rates:

    1%    -  9.6 bits per item
    0.1%  - 14.4 bits per item
    0.01% - 19.2 bits per item

* Optimal number of hash functions is 0.7 times number of bits per item.

* What is an acceptable false positive rate? This depends on your needs.

Ref: https://corte.si/posts/code/bloom-filter-rules-of-thumb/index.html

_
    args => {
        num_items => {
            summary => 'Expected number of items to add to bloom filter',
            schema => 'posint*',
            pos => 0,
            req => 1,
            cmdline_aliases => {n=>{}},
        },
        false_positive_rate => {
            schema => 'num*',
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

    [200, "OK", {
        num_bits   => $num_bits,
        m          => $num_bits,
        num_items  => $num_items,
        n          => $num_items,
        num_hashes => $num_hashes,
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
