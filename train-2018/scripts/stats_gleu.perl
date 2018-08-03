#!/bin/perl

use strict;

my $score = "GLEU";
my @scores = sort { $a <=> $b } map { `cat $_` =~ /^\[\['(\S+)'\]\],\s.*/m; $1 } @ARGV;

my $mean = 0;
$mean += $_ foreach(@scores);
$mean /= @scores;

my $var = 0;
$var += ($mean - $_)**2 foreach(@scores);
$var /= @scores;
my $sd = sqrt($var);

printf("Mean $score : %.4f [%.4f, %.4f]\n", $mean, $scores[0], $scores[-1]);
printf("Std. Dev.  : %.4f\n", $sd);
