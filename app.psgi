# -*- mode: cperl -*-
use lib 'lib';
use App::PerlMonks::Tidy;

sub pmtidy_app
{
    my $env    = shift;
    my $tidier = App::PerlMonks::Tidy->new( $env );
    $tidier->response;
}
