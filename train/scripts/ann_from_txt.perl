#!/usr/bin/perl
use strict;
use Getopt::Long;

$| = 0;

my %KEYS;
my @DATA;

my ($PATTERN, $_2013, $LC);
GetOptions(
    "p|pattern=s" => \$PATTERN,
    "2013" => \$_2013,
    "lc" => \$LC,
);

if ($_2013 and $PATTERN) {
    die "Do not specify '--2013' and '--pattern arg' at the same time!";
}

if ($PATTERN) {
    $PATTERN = "\\|($PATTERN)\\|";
}

if ($_2013) {
    $PATTERN = "\\|(ArtOrDet|Nn|Prep|SVA|Vform)\\|";
}

my $LASTKEY;

open(ANOT, $ARGV[0]);
while(<ANOT>) {
    chomp;
    if(/^S\s/) {
        $KEYS{$LASTKEY} = [ @DATA ] if(@DATA);
        ($LASTKEY) = /^S (.*)$/;
        if ($LC) {
            $LASTKEY = lc($LASTKEY);
            s/^S (.*)$/"S " . lc($1)/eg;
        }
        $LASTKEY = makeKey($LASTKEY);
        @DATA = ( $_ );
    }
    else {
        next if(/^A\s/ and $PATTERN and !/$PATTERN/);
        if (/^A/) {

            if ($LC) {
                my @parts = split(/\|\|\|/, $_);
                $parts[2] = lc($parts[2]);
                $_ = join("|||", @parts);
            }
        }
        push(@DATA, $_);
    }
}
$KEYS{$LASTKEY} = [ @DATA ] if(@DATA);


while(<STDIN>) {
    chomp;
    s/^\s+|\s+$//g;
    my @DATA;
    if(exists($KEYS{makeKey($_)})) {
        @DATA = @{$KEYS{makeKey($_)}};
    }
    else {
        @DATA = ("S MISSING!");
    }
    print join("\n", @DATA), "\n";
}

sub makeKey {
    my $key = shift;
    $key = lc($key);
    #$key =~ s/\P{L}/_/g;
    return $key;
}
