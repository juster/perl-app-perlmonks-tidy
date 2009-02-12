#!/usr/local/bin/perl -w

package main;
use strict;
use warnings;

use PerlMonks::Tidier;
use File::Spec;
use Readonly;
use English  qw( -no_match_vars );
use CGI      qw( :standard );

Readonly my $SCRIPT_UA  => 'PerlMonksHighlight';

# Crude templates used for output:
Readonly my $RESP_FMT_13 => <<'END_HTML';
<html>
<div id=\"highlight\">
%s
</div>
<div id=\"tidy\">
%s
</div>
</html>
END_HTML

Readonly my $RESP_FMT_14 => <<'END_XML';
<?xml version="1.0" ?>
<pmtidy status="%s">
%s
</pmtidy>
END_XML

Readonly my $RESP_FMT_14_CODE => <<'END_XML';
<code type="tidy">
<![CDATA[
%s
]]>
</code>
END_XML

Readonly my $RESP_FMT_14_ERR => <<'END_XML';
<error>
%s
</error>
END_XML

#---UTILITY FUNCTION---
# Usage   : print_sourcecode( $ver, $codeblock, $cgi )
# Purpose : Prints our HTMLized source code to the userscript.  Checks script
#         : version to be backwards compatible.
# Params  : $ver       - Version of the user script, see get_uscript_ver.
#         : $codeblock - PerlMonks::Tidy::CodeBlock object.
#         : $cgi       - CGI object.
# Returns : None.
#----------------------

sub print_sourcecode
{
    die 'Invalid arguments to print_sourcecode' if @_ != 3;
    my ($version, $codeblock, $cgi) = @_;

    # Old versions use HTML...
    if ( $version <= 1.3 ) {
        print $cgi->header('-content-type' => 'text/html; charset=ISO-8859-1');
        printf $RESP_FMT_13, ${$codeblock->hilited()}, ${$codeblock->tidied()};
        return;
    }

    # New versions use XML...
    print $cgi->header('-content-type' => 'text/xml; charset=ISO-8859-1');

    my $code_tags = join "\n",
        map { sprintf $RESP_FMT_CODE, $_ }
            ( ${$codeblock->hilited()}, ${$codeblock->tidied()} );
    printf $RESP_FMT_14, 'success', $code_tags;

    return;
}


#---UTILITY FUNCTION---
# Usage   : print_error( $version, $error_string, $cgi )
# Purpose : Prints out an error message, checks $version to be backwards
#         : compatible.
# Params  : $version      - Version of the user script, see get_uscript_ver.
#         : $error_string - The error message, ie: $@, $EVAL_ERROR
#         : $cgi          - CGI object.
# Returns : None.
#----------------------

sub print_error
{
    die 'Invalid arguments to print_error' if @_ != 3;
    my ($version, $errstr, $cgi) = @_;

    print $cgi->header( $errstr =~ $PerlMonks::Tidy::CodeBlock::UNPERLMSG
                        ? ('-content-type' => 'text/xml; charset=ISO-8859-1')
                        : ('-status' => 500) );

    # Old versions just printed the error out...
    if ( $version <= 1.3 ) {
        $errstr =~ s/ at .* $ //xms;
        print $errstr;
        return;
    }

    # New versions use XML...
    my $err_tag = sprintf $RESP_FMT_14_ERR, $errstr;
    printf $RESP_FMT_14, 'error', $err_tag;

    return;
}

#---UTILITY FUNCTION---
# Usage   : my $ver = get_uscript_ver();
# Purpose : Retrieve the javascript's version from the UserAgent HTTP field.
# Throws  : 'Unknown UserAgent: ...' or 'Invalid version: ...'
# Returns : A version string.
#----------------------

sub get_uscript_ver
{
    my ($agent, $version) = split m{/}, $ENV{'User-Agent'};

    die "Unknown UserAgent: $agent" if $agent ne $SCRIPT_UA;
    die "Invalid version: $version" if $version =~ /[^.\d]/;

    return $version;
}


{
    my $cgi         = new CGI;
    my $source_code = $cgi->param('code');
    my $tag_name    = $cgi->param('tag') || q{};
    my $script_version;

    eval {
        $script_version = get_uscript_ver();

        die 'No code given' if ! $source_code;

        # Make sure the perltidy.ERR file goes into a temporary
        # directory...
        my $tmpdir = File::Spec->tmpdir;
        chdir $tmpdir or die "could not chdir to $tmpdir: $!";

        my $codeblock = PerlMonks::Tidy::CodeBlock::DB->new($source_code);

        if ( uc($tag_name) eq 'P' ) {
            $codeblock->force_whitespace();
        }

        print_sourcecode( $script_version, $codeblock, $cgi );
    };

    if ($EVAL_ERROR) {
        # The exception may have been thrown by get_uscript_ver()...
        ( $script_version
          ? print_error( $script_version, $EVAL_ERROR, $cgi )
          : print $EVAL_ERROR_ );
    }

    exit 0;
}

__END__

=pod

=head1 NAME

pmtidy.pl - Perlmonks code block tidier CGI script

CGI backend for the Perlmonks Code Tidier Greasemonkey Script.

=head1 DESCRIPTION

A CGI script that reads in a source code file or code snippet and runs
the text through Perl::Tidy.  The code snippet is actually the html
representation of code blocks as PerlMonks formats them.  The script
is very specialized for PM's formatting and first attempts to strip
out and undo all of PM's formatting to pass in plain text to
Perl::Tidy.

Two versions of the code are returned to the browser.  One has syntax
highlighting with color and the other is also reformatted to be nicer
on the eyes.  Both versions are returned as HTML tags and colors are
set using spans with css classes.  The stylesheet is not sent so you
have to include that elsewhere.

The scripts attempts to keep the formatting (whitespace, linebreaks,
word wrapping) in the highlighted version as close to the original as
possible.  The tidied version reformats/rearranges code by its nature
but will also try to wrap lines.  It fails to wrap long comments and
quoted strings.

=head1 MODULE

PerlMonks::Tidy::CodeBlock - Object to do all the work

=head1 CGI PARAMETERS

=over

=item code

The html representation of the (possibly) perl code from the Perlmonks
website.  This should be URL encoded.

=item tag

The name of the tag that encloses the codeblock. This should be either
C<PRE> or C<P>.  This is case-insensitive. If tag is C<P>, this tells
the script to perform more post-processing. C<&nbsp;> entities are
inserted as well as C<< <br> >> html tags for linebreaks.

=back

=head1 PERLMONKS' CODE HTML

Perlmonks can format code blocks differently depending on the Display
settings set in your Display nodelet.  Code inside readmore tags also
have their own rules.  Perlmonks can also wrap code to line lengths.
All of the html tags have to be stripped and lines unwrapped to keep
Perl::Tidy from choking and failing.

=head2 Code Blocks

PM has code text of two different kinds.  Code blocks and inline code.
Code blocks have their C<< <tt> >> tags surrounded by C<< <span
class='codeblock'> >> tags.  Inline code does not.  We are only trying
to reformat the code blocks, not inline code.  This is handled in the
Greasemonkey userscript.

=head2 Assumptions

There is always a C<< <tt class="codetext"> >> inside the C<< <pre> >> or
C<<p>> tags as described below.  The code is inside the C<< <font> >>
tag which is inside the C<< <tt> >> tag if there is a font tag.

=head2 Quirks

There are C<< <font size="2"> >> tags everywhere.  Who knows what they
are for?  They don't seem to do anything except confuse Firefox's DOM
model.

=head2 Section-specific HTML

I first started examining the HTML of the "Seekers of Perl Wisdom".  I
found out later that some sections have slightly different formatting.

=head3 Code

Top-level posts in Code sections do not have C<< <div> >> or C<< <span> >>
tags enclosing the C<< <tt> >> codetext.  They are the same otherwise,
but these things are missing.

=head2 Display Settings

=head3 Large Code Font

PM's default behavior is to wrap code blocks with C<< <font size="-1">
>>.  This is inside the C<< <tt> >> tags.  If Large Code Font is
turned on these font tags are ommitted.  This logic is taken care of
by the Greasemonkey userscript.  The pmtidy.pl script is obvlivious to
this.  If C< <<font>> > tags are not removed from code they will be
treated as perlcode, highlighted, and encoded as HTML entities so that
the user will see the font tags displayed around the code.

=head3 Autowrap

Autowrap breaks lines using C<< <font
color="red"><b><u>&#173;</u></b></font> >>.  C<&#173;> is the html
entity for "small-hyphen".  This doesn't seem to display anything and
I'm not sure why it is there..?  The small hyphen has the hex value of
0xC2AD when decoded with
L<HTML::Entities|http://search.cpan.org/~gaas/HTML-Parser-3.56/lib/HTML/Entities.pm>.
It must be removed before processing with Perltidy.

Code blocks are enclosed in C<< <p class="code"> >> tags.  Linebreaks are
forced using C<< <br> >> tags.  &nbsp; spaces must be used for spaces.
You must alternate each "&nbsp; ", starting with 1 &nbsp;

 <p class="code">
  <span class="codeblock">
   <tt class="codetext">
    CODE
   </tt>
  </span>
  <span class="codeblock"><a href="...">...</a></span>
 </p>


=head3 Regular wordwrap (no Autowrap)

The default word wrapping breaks lines with C<< <font color="red">+</font> >>,
uses C<< <pre> >> tags for the topmost tag, and C<< <div> >> tags.

 <pre class="code">
  <div class="codeblock">
   <tt class="codetext">CODE</tt>
  </div>
  <div class=""><a href="...">...</a></span>
 </pre>

=head3 Disable wordwrap

There is no wordwrapping done at all, obviously.  Code tags are
enclosed in C<< <pre class="code"> >> tags and there are no C<< <br> >> tags
needed.

 <pre class="code">
  <div class="codeblock">
   <tt class="codetext">CODE</tt>
  </div>
  <div class=""><a href="...">...</a></span>
 </pre>

=head2 Readmore tags

Readmore tags override the above wordwrapping Display settings.  No
wordwrapping is performed.  Code is enclosed in C<< <pre class="code"> >>
tags, always.  There are no C<< <br> >>'s or C<&nbsp;>'s.

Font size still affects readmore tags and C<< <font size="-1"> >> may or
may not be in effect.

=head2 Summary

=head3 Hierarchy

 <(pre|p) class="code">
   <(div|span) class="codeblock">**
     <tt class="codetext">
       <font size="-1">*
         CODE
       </font>*
     </tt>
   </(div|span)>**
   <(div|span) class="embed-dl-code">
     <font size="-1">*
       <a>[download]</a>
     </font>*
   </(div|span)>
 </(pre|p)>

 *  = Not used if Large Code Font is enabled in Display nodelet.
 ** = Not used in Code section.

=head1 ACKNOWLEDGEMENTS

=over

=item Jon Allen

This script was inspired by and started from Jon Allen's L<AJAX perl
highlighter|http://perl.jonallen.info/projects/syntaxhighlighting>

=back

=head1 AUTHOR

juster <jrcd83 @t gmail d0t com> on www.perlmonks.com

=head1 LICENSE

Copyright (c) 2008 by Justin Davis.

Released under the Artistic License.

=cut
