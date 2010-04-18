#!/usr/bin/perl

use warnings;
use strict;

use PerlMonks::Tidy::Pipeline;

sub one {
    my $stash = shift;
    $stash->{arg} .= '1...';
    $stash->{arg} .= $stash->{foo};
}

my $pipeline = PerlMonks::Tidy::Pipeline->new
    ( 'three' => sub {
          my $stash = shift;
          $stash->{foo} = 'doh';

          $stash->{arg} .= '3...';
      },
      sub {
          die "This is an exception";
      },
      sub {
          my $stash = shift;
          $stash->{arg} .= '2...';
      },
      'one' => \&one,
     );

$pipeline->allow_diversion( 'three' => 'one' );

my $data = $pipeline->flush( '1...2...3...' . 'a' x 1_000_000 );

print substr( $data, 0, 78 ), "\n", substr( $data, -78 ), "\n";
