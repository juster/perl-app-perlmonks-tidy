#!/usr/local/bin/perl -w

# CGI backend for the Perlmonks Code Tidier Greasemonkey Script
# by [juster]
#
# Copyright (c) 2008 Justin Davis <jrcd83@gmail.com>
# Released under the Perl Artistic License.
# http://www.perlfoundation.org/legal/licenses/artistic-2_0.html
#
# Inspired by and started from Jon Allen's AJAX perl highlighter:
# Project website: http://perl.jonallen.info/projects/syntaxhighlighting
#
# $Id: pmtidy.pl,v 1.2 2008/10/28 23:16:14 justin Exp $

use strict;
use warnings;
use CGI qw/:standard/;
use Perl::Tidy;
use HTML::Entities;
use XML::Simple;

our $VERSION = 'BETA';

use constant {
  UNPERLMSG  => 'How very unperlish of you!',
};

my $cgi       = new CGI;
my $code      = $cgi->param('code');
my $wordwrap  = $cgi->param('wrap');
my $wrapmode  = $cgi->param('lb');
my $tabsize   = $cgi->param('tabsize');

eval {
  die 'No code given' unless(defined $code);
  $wordwrap = 80 unless(defined $wordwrap);
  $code =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg; # from URI::Encode
  decode_entities($code);

  open LOGFILE, '>>', '/usr/www/users/juster/log/pmtidyerr.log';
	print LOGFILE ($code =~ /\+/ ? "THAR BE PLUS SIGNS!\n" : "AVAST NO PLUS\n");
	close LOGFILE;

	$code =~ s|<font\ color="red">\s*<b>\s*
						 <u>\s*\xAD\s*</u>\s*
						 </b>\s*</font>\s*||gx if($wrapmode);
  $code =~ s/\xA0/ /g; # &nbsp;
  $code =~ s|<br\s*/?>||g;

  # put the perltidy.ERR file in /tmp
  chdir('/tmp') or die "could not chdir to /tmp: $!";

  # We return two versions, both are converted to html and colorized
  # But one is also tidied up (reformatted) first.
  my $errors;
  my $tidied;

# 	open LOGFILE, '>>', '/usr/www/users/juster/log/pmtidyerr.log';
# 	print LOGFILE "$code\n******\n";
# 	close LOGFILE;

  # The stderr option to perltidy does not seem to do anything!.
  # So we force it muahaha! Take that!
  open my $tmpstderr, '>', \$errors or die "open for temp STDERR: $!";
  my $oldstderr = *STDERR;
  *STDERR = $tmpstderr;
  perltidy( source => \$code, destination => \$tidied );
  *STDERR = $oldstderr;
  close $tmpstderr;
  if( $errors ) {

    print $cgi->header;
    print UNPERLMSG;
    exit 0;
  }

  # I'm thinking errors won't happen with perltidy below if they
  # did not above...

  # BUG: wordwrap option doesn't work for long string, need to manually
  #      fix that
  my $tidyargs = "-html -pre -l=$wordwrap";
  $tidyargs .= "-i=$tabsize" if(defined $tabsize);

  my $result;
  perltidy( source      => \$code,
            destination => \$result,
            argv        => $tidyargs );
  $code = $result;
  perltidy( source      => \$tidied,
            destination => \$result,
            argv        => $tidyargs );
  $tidied = $result;

  $code   =~ s|</?a.*?>||g;
  $code   =~ s|</?pre>\n||mg;
  $tidied =~ s|</?pre>\n||mg;

#	chomp $code;   # Chop 1 newline off
#	chomp $tidied; 

	if($wrapmode) {
		$code   =~ s|$|<br />|mg;
		$tidied =~ s|$|<br />|mg;
		$code   =~ s|^(\s+)|'&nbsp;' x length($1)|gem;
		$tidied =~ s|^(\s+)|'&nbsp;' x length($1)|gem;
	}
  my $html = join "\n", ("<html>",
                         "<div id=\"highlight\">$code</div>",
                         "<div id=\"tidy\">$tidied</div>",
                         "</html>");
  print $cgi->header;
  print $html;
};

if($@) {
#   open my $errlog, '>>', ERRLOGFILE;
#   print $errlog "$@";
#   close $errlog;

  print $cgi->header(-status => 500);
  #die "$0: $@";
}

exit 0;

