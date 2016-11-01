#!/usr/bin/perl

my %phrases;

foreach my $FILE (@ARGV) {
    open(FILTER, "<", $FILE) or die "Could not open $FILE\n";
    while(<FILTER>) {
        my @tokens = split;
        foreach my $length (1 .. 7) {
            foreach my $start (0 .. $#tokens) {
                if ($start + $length - 1 < @tokens) {
                    my $phrase = join(" ", @tokens[$start .. $start + $length - 1]);
                    $phrases{$phrase} = 1;
                }
            }
        }
    }
    close(FILTER);
    print STDERR "Read filter\n";
}

$| = 1;

my $c1 = 0;
my $c2 = 0;
while (<STDIN>) {
    my @parts = split(/\s\|\|\|\s/, $_);
    if (exists($phrases{$parts[0]})) {
        print $_;
        $c2++;
    }
    $c1++;
}
print STDERR "$c2/$c1\n";
