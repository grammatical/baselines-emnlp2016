#!/usr/bin/perl
use strict;
use Getopt::Long;
use File::Spec;
use Data::Dumper;

my $i = 0;
my @files = @ARGV;

my $AVG = pop(@files);

my $files = join(" ", @files);

open(INIS, "paste $files |") or die "Problem 1\n";
my @inis = <INIS>;
close(INIS);

my @names = qw(UnknownWordPenalty WordPenalty PhrasePenalty TranslationModel LexicalReordering Distortion LM OpSequenceModel EditSequenceModel EditOps VW);
my $pattern = join("|", @names);

my $sparse = "";

my %inis;
my $next_is_weight_file = 0;
foreach my $FIELD (0 .. $#files) {
    my $content = "";
    foreach (@inis) {
        chomp;
        my @t = split(/\t/, $_);

        if ($t[0] =~ /^((${pattern})\d+=)/) {
            my $name = $1;
            my @weights = map { my ($name, @values) = split(/\s+/, $_); [@values] } @t;


            my @sumsArr;
            my $j = 0;
            foreach my $set (@weights) {
                foreach my $i (0 .. $#{$set}) {
                    $sumsArr[$i] = [] if not defined $sumsArr[$i];
                    $sumsArr[$i]->[$j] = $set->[$i];
                }
                $j++;
            }

            my @sums;
            foreach my $w (@sumsArr) {
                my @w = sort { $a <=> $b } @$w;

                #shift @w; pop @w;

                my $avg = 0;
                $avg += $_/@w foreach (@w);
                push(@sums, sprintf("%.9f", $avg));
            }

            my $values = join(" ", @sums);
            $content .=  "$name $values\n";
        }
        else {
            if ($next_is_weight_file) {
                $content .= File::Spec->rel2abs($files[$FIELD]) . ".sparse\n";
                print STDERR Dumper(\@t);
                $sparse = average_sparse(@t) if not($sparse);
                $next_is_weight_file = 0;
            }
            else {
                $content .= $t[$FIELD] . "\n";
                if ($t[0] =~ /\[weight-file\]/) {
                    $next_is_weight_file = 1;
                }
            }
        }

    }
    $inis{$AVG} = $content;
}

foreach my $ini (sort keys %inis) {
    open(INI, ">", $ini) or die "Problem 2: Could not create $ini\n";
    print INI $inis{$ini};
    close(INI);

    if ($sparse) {
        open(SPARSE, ">", "$ini.sparse") or die "Problem 3\n";
        print SPARSE $sparse;
        close(SPARSE);
    }
}

sub average_sparse {
    my @weights = @_;
    my %weights;
    my %counts;

    foreach my $file (@weights) {
        print STDERR $file, "\n";
        open(W, "<", $file) or die "Problem 4: Could not open $file: $!\n";
        while (<W>) {
           chomp;
           my ($f, $w) = split;
           $weights{$f} += $w;
           $counts{$f}++;
        }
        close(W);
    }

    foreach (keys %weights) {
        $weights{$_} /= $counts{$_};
    }

    return join("\n", map { "$_ $weights{$_}" } sort keys %weights);
}

