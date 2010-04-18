#!/usr/bin/perl -w

use strict;
use feature 'say';

my $string = << 'EOF';
test
<br>

EOF

my $found = $string =~ m|<br>\s*$|;
say $found ? "FOUND IT" : "DIDN'T FIND SHIT";

