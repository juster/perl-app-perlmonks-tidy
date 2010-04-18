#!/usr/bin/perl -w

use strict;

my $code = do { local (@ARGV, $/) = 'msg'; <> };
$code =~ s|<font\ color="red">\s*<b>\s*
#					 <u>\s*\x{c2ad}\s*</u>\s*
					 <u>\s*\xc2\xad\s*</u>\s*
					 </b>\s*</font>||gxs;

print $code;





