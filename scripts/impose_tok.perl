#!/usr/bin/perl

use strict;
use Algorithm::Diff::XS qw(diff);
use Data::Dumper;

if (not $ARGV[0] or not -e $ARGV[0]) {
    die "Missing tokenized example\n";
}

open(SCHEMA, $ARGV[0]) or die "Cannot open $ARGV[0]\n";

while (defined(my $in = <STDIN>)
       and defined(my $schema = <SCHEMA>)) {

    chomp($in, $schema);

    if ($schema =~ /''\w/) {
        $in =~ s/" /''/;
    }
    if ($schema =~ /, .$/) {
        $in =~ s/ .$/, ./;
    }
    $in =~ s/n 't/ n't/g;

    my @in = split(//, $in);
    my @scheme = split(//, $schema);

    my $diff = diff(\@in, \@scheme);

    #print "$in\n$scheme\n";
    #print Dumper($diff);

    my $count = 0;
    foreach my $ops (@$diff) {
        foreach my $s (@$ops) {
            my ($op, $i, $char) = @$s;
            if ($op eq '-') {
                $count++;
            }

            if (@$ops == 1) {
                if ($char eq ' ') {
                    if ($op eq '-') {
                        $in[$i] = undef;
                    }
                    if ($op eq '+') {
                        my $j = $i + $count;
                        $in[$j] = " $in[$j]";
                        $count--;
                    }
                }
            }
        }
    }

    print STDERR "[$.]\n" if($. % 1000 == 0);

    my $out = join("", grep { defined } @in);
    #$out =~ s/ n't / not /g;
    #$out =~ s/ can? not / cannot /g;
    print $out, "\n";
}
