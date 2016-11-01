#!/usr/bin/perl
use strict;
use Getopt::Long;

my $FACT = 0;

GetOptions(
  "f|fact" => \$FACT,
);

my $largest = 0;
my %CLS;

my $OPEN = $ARGV[0];
if($ARGV[0] =~ /\.gz$/) {
    $OPEN = "gzip -dc $ARGV[0] |";
}

open(CLS, $OPEN) or die;
while(<CLS>) {
    chomp;
    my ($w, $c) = split(/\s/, $_);
    $CLS{$w} = $c;
    if($c > $largest) {
        $largest = $c;
    }
}
close(CLS);
my $unseen = "G";

while(<STDIN>) {
    chomp;
    my @tok = split(/\s/, $_);
    foreach my $t (@tok) {
        my ($fac) = split(/\|/, $t);
        my $prefix = "";
        $prefix = "$t|" if($FACT);
        if(exists($CLS{$fac})) {
            print "$prefix$CLS{$fac} ";
        }
        else {
            print "$prefix$unseen ";
        }
    }
    print "\n";
}