#!/usr/bin/perl -w

use warnings;
use strict;
use utf8;

use HTTP::Request::Common qw(POST GET);
use Getopt::Long          qw(GetOptions);
use URI::Escape           qw(uri_escape);
use LWP;

my ($USE_GET);

GetOptions( 'get' => \$USE_GET );

die 'Provide a perl filename to send as argument'
    unless @ARGV;

my $cgiuri = 'http://juster.info/perl/pmtidy/pmtidy-1.3.pl';
my $agent = 'PerlMonksHighlight/1.4';

my $code = do { local $/; <> };

my $ua   = LWP::UserAgent->new( agent => $agent );
my $req;
if ( $USE_GET ) {
    $code   = uri_escape( $code );
    my $uri = $cgiuri . qq{?code=$code;tag=P};
    $req    = GET $uri;
}
else {
    $req = POST $cgiuri, [ 'code' => $code, 'tag' => 'P' ];
}

print "REQUEST:\n", $req->as_string, "\n", (q{-} x 70), "\n\n";

my $resp = $ua->request( $req );
print "RESPONSE:\n";
print map { "$_ = ".$resp->header($_)."\n"; } $resp->header_field_names;
print $resp->content;
print "CODE: ${\$resp->code}\n";
