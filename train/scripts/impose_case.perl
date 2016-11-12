#!/usr/bin/perl
use strict;

if (not $ARGV[0] or not -e $ARGV[0]) {
    die "Missing cased source\n";
}

if (not $ARGV[1] or not -e $ARGV[1]) {
    die "Missing alignment file\n";
}

open(SRC, "<:utf8", $ARGV[0]) or die "Cannot open $ARGV[0]\n";
open(ALN, "<:utf8", $ARGV[1]) or die "Cannot open $ARGV[1]\n";

binmode(STDIN, ":utf8");
binmode(STDOUT, ":utf8");

while (defined(my $trg = <STDIN>)
       and defined(my $src = <SRC>)
       and defined(my $aln = <ALN>)) {

    chomp($trg, $src, $aln);

    my @src = split(/\s/, $src);
    my @trg = split(/\s/, $trg);

    my @aln = map { [ split(/-/) ] } split(/\s/, $aln);

    my %done;
    foreach my $p (@aln) {
        my ($i, $j) = @$p;

        if (lc($src[$i]) eq lc($trg[$j])) {
            $trg[$j] = $src[$i];
            $done{$i} = 1;
        }
    }

    foreach my $p (@aln) {
        my ($i, $j) = @$p;

        next if(exists($done{$i}));

        #if($src[$i] =~ "'" and $src[$i] ne "n't" and $trg[$j] !~ "'") {
        #    $trg[$j] = $src[$i];
        #}

        if($src[$i] =~ /\"/ and $trg[$j] !~ /[a-z]/i) {
            $trg[$j] = $src[$i];
        }


        if ($src[$i] =~ /^\p{Lu}[\p{Ll}\d]+$/) {
            $trg[$j] = ucfirst($trg[$j]);
        }
        elsif ($src[$i] =~ /^\p{Lu}[\p{Lu}\d]+$/) {
            $trg[$j] = uc($trg[$j]);
        }
        elsif ($src[$i] =~ /^\p{Lu}/) {
            $trg[$j] = ucfirst($trg[$j]);
        }

        $done{$i} = 1;
    }

    if ($src[0] =~ /^\p{Lu}/) {
        $trg[0] = ucfirst($trg[0]);
    }

    #foreach my $i (0 .. $#src) {
    #    if ($src[$i] =~ "'") {
    #        my @a = grep { $_>[0] == $i } @aln;
    #        if (not @a) {
    #            my ($first) = map { $_->[1] } grep { $_>[0] == $i-1 } @aln;
    #            if (defined($first)) {
    #                $trg[$first] = $trg[$first] . " " . $src[$i]
    #            }
    #        }
    #    }
    #}

    print join(" ", @trg), "\n";
}
