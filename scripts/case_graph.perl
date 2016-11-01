#!/usr/bin/perl

use strict;
use Parallel::ForkManager;
use Getopt::Long;
use File::Temp qw(tempdir);

binmode(STDIN, ":utf8");
binmode(STDOUT, ":utf8");

my $DECODE = "";
my $LM = "";
my $THREADS = 16;

GetOptions(
    "t|threads=i" => \$THREADS,
    "lm=s" => \$LM,
    "d|decode=s" => \$DECODE,
);

die "Specify path to lazy/decode with --decode path" if(not -e $DECODE);
die "Specify path to lm with --lm path" if(not -e $LM);

print STDERR "Using $THREADS threads\n";

my $DIR = tempdir(CLEANUP => 1);

print STDERR "Creating Graphs\n";
while (<STDIN>) {
    if ($. % 10000 == 0) {
        print STDERR "[$.]\n";
    }

    chomp;
    writeGraph($_, $. - 1, $DIR);
}

print STDERR "Loading $LM\n";
my $WEIGHTS = "LanguageModel=1 LanguageModel_OOV=1 WordPenalty=0";
open(DECODE, "$DECODE -i $DIR --beam 10 --lm $LM -W $WEIGHTS --threads $THREADS |") or die "Could not start decoder";
binmode(DECODE, ":utf8");

my $c = 0;
print STDERR "Recasing\n";
while (<DECODE>) {
    $c++;
    if ($c % 10000 == 0) {
        print STDERR "[$.]\n";
    }
    my (undef, $text) = split(/\s+\|\|\|\s+/, $_);
    print "$text\n";
}
close(DECODE);
print STDERR "Done\n";

sub writeGraph {
    my ($sentence, $no, $dir) = @_;
    my @words = split(/\s/, $sentence);

    my $v = 0;
    my $e = 0;

    my @g;
    push(@g, ["<s>"]); $v++; $e++;
    foreach my $w (@words) {
        my @e = ( $w ); $v++; $e++;
        if ($w ne lc($w)) {
            push(@e, lc($w)); $e++;
        }
        push(@g, [@e]);
    }
    push(@g, ["</s>"]); $v++; $e++;

    open(GRAPH, ">:utf8", "$dir/$no") or die "Could not open $dir/$no: $!\n";
    print GRAPH "$v $e\n";
    my $c = 0;
    foreach(@g) {
        print GRAPH scalar @$_, "\n";
        foreach (@$_) {
            if ($c > 0) {
                print GRAPH "[", ($c - 1), "] ";
            }

            print GRAPH "$_ |||\n";
        }
        $c++;
    }
    close(GRAPH);
}
