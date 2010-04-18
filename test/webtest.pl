#!/usr/bin/perl -w

use warnings;
use strict;
use LWP;
use utf8;

my $cgiuri = 'http://juster.info/perl/pmtidy/pmtidy-1.3.pl';
my $agent = 'PerlMonksHighlight/1.4';

my $code = do { local $/; <> };

my ($ua, $resp) = (LWP::UserAgent->new( agent => $agent );
$resp = $ua->post($cgiuri, Content => { 'code' => $code, 'tag' => 'P' });
print map { "$_ = ".$resp->header($_)."\n"; } $resp->header_field_names;
print $resp->content;
print "CODE: ${\$resp->code}\n";
