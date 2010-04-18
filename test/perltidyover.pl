#!/usr/bin/perl -w

use warnings;
use strict;
use lib qw{/home/justin/src/PMTidy};

use Perl::Tidy;


print $INC{'Perl/Tidy.pm'}, "\n";

#my $test = "ÀÁÂÃ";

my $infile = do { local (@ARGV, $/) = 'naturalsorting.pl'; <>; };
my $outfile;

perltidy( source => \$infile, destination => \$outfile,
         argv => '-html' );
#print Perl::Tidy::escape_html($test), "\n";
print $outfile;
