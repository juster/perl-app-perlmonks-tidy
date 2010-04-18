#!/usr/bin/perl

use warnings;
use strict;

use PerlMonks::Tidy;
use DBI;

my $src_code = do { local (@ARGV, $/) = 'modtest.pl'; <>; };

#print "SOURCE CODE:\n$src_code\n\n";

my $dbh = DBI->connect('dbi:mysql:juster', 'justin', 'laotzu83')
    or die 'Failed to connect to DB: ',$DBI::errstr;
my $tidier = PerlMonks::Tidy->new({ dbh => $dbh });

my $block = $tidier->codeblock({ code => $src_code,
                                action => 'tidy' });
print $block->get_result;

#print "TIDIED:\n", $block->get_result(), "\n\n";

