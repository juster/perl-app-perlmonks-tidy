#!/usr/local/bin/perl -w

package PMTidy::CodeBlock;
use warnings;
use strict;

use HTML::Entities  qw{decode_entities};
use Perl::Tidy;
use Carp            qw{carp croak confess};

our $VERSION = '1.4';

#----------------------------------------------------------------------------
# PRIVATE METHODS
#----------------------------------------------------------------------------

##
## $success = $codeblock->_prepare_code( \$code, \$dest )
##
##  $code - String containing 'code' received as CGI parameter.
##          This will be x-url-encoded, with HTML entities encoded.
##  $dest - String to place the cleaned up code, (the "result")
##
## The result here _should_ be regular code.  The only HTML in the
## code should be optional <font> tags used with the wordwrapping. See
## below.
##
## Returns: 1
##
#

sub _prepare_code
{
    my ($self, $source, $dest) = @_;
    die unless eval { ref $source eq 'SCALAR' && ref $dest eq 'SCALAR' };

    $$dest = $$source;
    $$dest =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg; # from URI::Encode

    decode_entities($$dest);

#    if (uc $tag eq 'P') {
    $$dest =~ tr{\xA0}{ }; # &nbsp;
    $$dest =~ s{<br */?>}{}g;
#    }

    $$dest =~ /(\n+)$/;
    $self->{'traillines'} = (length $1)-1;

    return 1;
}

##
## $success = $codeblock->_remove_word_wraps( \$code )
##
##  $code - String containing the code to be checked for wordwrapping
##          by PerlMonks.
##
## Should be called after _prepare_code and before _tidycode or
## _hilitecode.
##
## (See POD documentation for details on PerlMonks' wordwrapping
## format.)
##
## Returns: 1 if wordwrapping <font> tags were found
##          0 otherwise
##
#

sub _remove_word_wraps
{
    my ($self, $code) = @_;

    if ( $$code =~ m{<font color="red">(.*?)</font>} ) {
        if ($1 eq '+') {
            # Exlicit word wrapping in Display setting nodelet
            $$code =~ m{(?:^|\n)(.+?)\n<font color="red">\+</font>};
            $self->{'wraplen'} = length $1;

            # Record all of the wrapped lines, to rewrap them later.
            my @lines = split /\n/, $$code;
            $self->{'wrappedlines'} = $self->_find_word_wraps( \@lines );
            $self->{'wrapmode'} = 'normal';
            $$code =~ s{\n<font color="red">\+</font>}{}gm;
        }
        else {
            # Auto wordwrapping
            $$code =~ /^(.*)<font color="red">/m;
            $self->{'wraplen'}  = length $1;
            $self->{'wrapmode'} = 'auto';
            $$code =~ s{<font color="red"><b><u>\xC2\xAD</u></b></font>}{}g;
        }

        return 1;
    }

    $self->{'wrapmode'} = 'off';
    return 0;
}

##
## $success = $codeblock->_restore_word_wraps( \$code )
##
## Returns: 1
##
#

sub _restore_word_wraps
{
    my ($self, $code) = @_;

    # Redo the linewrapping for the hilited version, if linewrapping
    # is explicitly set in PM's User Settings.  This won't work for
    # the tidied version because lines could move around or become
    # longer/shorter.

    croak "_remove_word_wraps must be called before _restore_word_wraps"
        unless defined $self->{'wrapmode'};

    if ( $self->{'wrapmode'} eq 'normal' && defined $self->{'wraplen'} ) {
        $$code =~ m{(\n)+$};
        my $lostnewlines = $1;

        my @codelines = split /\n/, $$code;
        $self->_insert_word_wraps( $self->{'wrappedlines'},
                                   \@codelines,
                                   $self->{'wraplen'} );
        $$code = join "\n", @codelines;
        $$code .= $lostnewlines;
    }

    return 1;
}

##
## $success = $codeblock->_tidy_code( \$source, \$dest )
##
##  $source - String containing the code to be tidied up
##  $dest   - String to place results into
##
## Tidies up the source code from plain text into plain text.
## Works similar to perltidy on command line but into a string.
##
## Returns: 0 if perltidy displayed error messages do to bad syntax
##          1 on success
##
#

sub _tidy_code {
    my ($self, $src, $dest) = @_;
    die unless eval { ref $dest eq 'SCALAR' && ref $src eq 'SCALAR' };

    my $errors;
    my $tidied;

    # The stderr option to perltidy does not seem to do anything!.
    # So we force it muahaha! Take that!
    open my $tmpstderr, '>', \$errors or die "open for temp STDERR: $!";
    my $oldstderr = *STDERR;
    *STDERR = $tmpstderr;

    my $tidyargs;
    if ($self->{'wrapmode'} ne 'off') {
        $tidyargs = "-sil=0 -l=$self->{wraplen}";
    }
    else {
        $tidyargs = "-sil=0";
    }
    perltidy( source => $src, destination => $dest, argv => $tidyargs );

    *STDERR = $oldstderr;
    close $tmpstderr;
    return ! $errors;
}

##
## $success = $codeblock->_hilite_code( \$source, \$dest )
##
##  $source - String containing plain-text code to tidy up.
##  $dest   - String to place HTML, highlighted version of code
##
## Unlike normal perltidy HTML output, we also remove the enclosing
## <pre></pre> tags as well as all <a> anchors since we don't use
## these.
##
## Returns: 1
##
#

sub _hilite_code {
    my ($self, $src, $dest) = @_;
    die unless eval { ref $dest eq 'SCALAR' && ref $src eq 'SCALAR' };

    my $hiliteargs = '-html -pre';

    # I'm hoping errors won't happen with perltidy below if they
    # did not happen with _tidy_code
    # TODO: better error checking
    perltidy( source      => $src,
              destination => $dest,
              argv        => $hiliteargs );

    $$dest  =~ s{</?a.*?>}{}g;  # remove anchors
    $$dest  =~ s{</?pre>\n}{}g; # remove surrounding pre tags

    # For string literals, PerlTidy duplicates the spaces, putting
    # them in front of the <span> tag as well as inside.  A small bug.
    #
    # BUT it doesn't have this bug for strings after __END__
    # ... sheesh
    $$dest  =~ s{^ +(?=<span class="q">\s+)}{}gm;

    return 1;
}

##
## $foundlines = $codeblock->_find_word_wraps( $lines );
##
##  $lines - Arrayref to the lines of the code (HTML from PM)
##
## Unless "Code Wrapping Off" or "Auto Code Wrapping" is selected in
## the "Display" settings nodelet, PerlMonks wraps lines at a certain
## "Code Wrap Length".  Find where PerlMonks has forced line breaks in
## the HTML.  Return each line where one was found.
##
## Returns: Arrayref of indices into @$lines where line breaks were found.
##
#

sub _find_word_wraps
{
    my $lines = shift;
    my ($joined, %found) = 0;
    for my $i (0 .. @$lines-1) {
        if ( $lines->[$i] =~ m|^<font color="red">\+</font>| ) {
            $found{$i-1 - $joined++} = 1;
            # We want the previous line, remember matches get joined
            # to the previous line, hence $joined.
        }
    }
    return [ sort { $a <=> $b } keys %found ];
}

##
## $success = $codeblock->_insert_word_wraps( \@linewraps, \@lines, $linemax )
##
##  @linewraps - Array to the results of find_word_wraps
##  @lines     - Array to the lines of source (HTML from perltidy)
##  $linemax   - The count of characters at which to wrap a line
##
## $lines will be modified in place.  Lines will be wrapped at $linemax
## characters.  HTML tags and entities are ignored and do not affect the
## line wrapping.  Lines are wrapped duplicating Perlmonks's output.
##
## Returns: 1
##
#

sub _insert_word_wraps {
    my ($wraps, $lines, $linemax) = @_;

  LINELOOP:
    for my $wrapline ( @$wraps ) {
        my $line = \$lines->[$wrapline];
        my $charcount = 0;
        my @blocks = grep { length; } split /(<\/?span.*?>)/, $$line;

      BLOCKLOOP:
        for my $block (@blocks) {
            next BLOCKLOOP if($block =~ /^<.*>$/);
            my $blockchars = length $block;

            # HTML entities must be counted as one character.
            # But when inserting the linebreak we must skip them.
            my @entities;   # ([ entity_start, entity_length-1 ], ...)
            while ($block =~ /&#?\w+;/g) {
                my $len = $+[0] - $-[0] - 1;
                push @entities, [ $-[0], $len ];
                $blockchars -= $len;
            }

            my ($breakpos, $newchars) = (0, 0);
            while ( $charcount + $blockchars > $linemax ) {
                # This is the span we are going to wordwrap
                # Breakpos    = where we are looking to insert a linebreak
                # Blockchars  = # of chars left unwrapped in this block.
                # Charcount   = # of chars in the current line
                $breakpos += $linemax - $charcount;
                $blockchars -= $linemax - $charcount;

                # Skip past entities.  Entity indices were stored with
                # the content of original string so we save entoffset
                # to keep track of how many characters we have added
                # ourselves.
              ENTLOOP:
                while (@entities) {
                    last ENTLOOP if( $entities[0][0]+$newchars > $breakpos );
                    $breakpos += $entities[0][1];
                    shift @entities;
                }

                my $linebreak = "\n<font color=\"red\">+</font>";
                substr $block, $breakpos, 0, $linebreak;
                $breakpos += length $linebreak;
                $newchars += length $linebreak;
                $charcount = 1;
            }
            $charcount += $blockchars;
        } #BLOCKLOOP

        $$line = join '', @blocks;
    } #LINELOOP

    return 1;
}

##
## $success = $codeblock->_fix_trailing_lines( \$code )
##
## Fixes trailing newlines given by perltidy to match the trailing
## newline that were in the PerlMonks' original.
##
## PRECOND: _prepare_code must be called before this is used.
##
#

sub _fix_trailing_lines {
    my ($self, $code) = @_;
    croak unless eval { ref $code eq 'SCALAR' };

    croak "_prepare_code must be run before _fix_trailing_lines"
        unless defined $self->{'traillines'};

    # Match trailing to the original so the code doesn't move up.
    # If input has no trailing newline, perltidy appends one.
    # If input has 1 or more, perltidy appends only one.
    if ( $self->{'traillines'} == 0 ) {
        chomp $$code;
    }
    elsif ( $self->{'traillines'} > 0 ) {
        $$code .= "\n" x ($self->{'traillines'});
    }

    return 1;
}

#----------------------------------------------------------------------------
# PUBLIC FUNCTIONS
#----------------------------------------------------------------------------

sub new
{
    my ($class, $formcode) = @_;
    croak "Original code wasn't provided" unless $formcode;

    my $self = bless { 'processed'     => 0,
                       'origcode'      => $formcode,
                       'cleancode'     => '',
                       'tidycode'      => '',
                       'hilitecode'    => '',
                       'traillines'    => undef,
                       'wrapmode'      => 'off',
                       'wraplen',      => undef,
                       'wrappedlines'  => [] }, $class;

    return $self;
}

sub process {
    my $self = shift;
    $self->pre_perltidy();
    $self->do_perltidy() || return undef;;
    $self->post_perltidy();
    $self->{'processed'} = 1;
    return $self;
}

sub pre_perltidy {
    my $self = shift;

    # Prepare our input from PerlMonks for PerlTidy

    $self->_prepare_code( \$self->{'origcode'}, \$self->{'cleancode'} )
        or die '_prepare_code';

    $self->_remove_word_wraps( \$self->{'cleancode'} );

    return $self;
}

sub do_perltidy {
    my $self = shift;

    # We return two versions, both are converted to html and colorized
    # But one is also tidied up (reformatted) first.

    $self->_tidy_code( \$self->{'cleancode'}, \$self->{'tidycode'} )
        or croak "Not perl code";

    my $newtidycode;
    $self->_hilite_code( \$self->{'tidycode'}, \$newtidycode )
        or confess 'unknown error in _hilite_code';
    $self->{'tidycode'} = $newtidycode;

    $self->_hilite_code( \$self->{'cleancode'}, \$self->{'hilitecode'} )
        or confess 'unknown error in _hilite_code';

    $self->_fix_trailing_lines( \$self->{'hilitecode'} );
    $self->_fix_trailing_lines( \$self->{'tidycode'} );

    return $self;
}

sub post_perltidy {
    # Fixup formatting to match originals.
    my $self = shift;
    $self->_restore_word_wraps( $self->{'hilitecode'} );
    return $self;
}

sub force_whitespace {
    my $self = shift;

    $self->process unless $self->{'processed'};

    # &nbsp must be intermixed with spaces because two or more spaces
    # are truncated to one inside a <p> html tag.
    $self->{'tidycode'}   =~
        s!(^ +| {2,})!
            '&nbsp; ' x (length($1)/2) . (length($1)%2 ? '&nbsp;' : '')!gem;
    $self->{'hilitecode'} =~
        s!(^ +| {2,})!
            '&nbsp; ' x (length($1)/2) . (length($1)%2 ? '&nbsp;' : '')!gem;

    $self->{'tidycode'}   =~ s|\n|<br />\n|g;
    $self->{'hilitecode'} =~ s|\n|<br />\n|g;

    return 1;
}

# Giving references to our internal data is technically unsafe.
# Owell, I'm hoping it is more efficient for large strings.

sub tidied {
    my $self = shift;
    $self->process unless $self->{'processed'};
    return \$self->{'tidycode'};
}

sub hilited {
    my $self = shift;
    $self->process unless $self->{'processed'};
    return \$self->{'hilitecode'};
}

1;

#----------------------------------------------------------------------------

package PMTidy::CodeBlock::DB;
#use base PMTidy::CodeBlock;
our @ISA = qw{PMTidy::CodeBlock};

use Digest::MD5 qw{md5};
use Carp        qw{croak confess};
use DBI;

sub DBSOURCE() { 'dbi:mysql:juster'; };
sub DBUSER()   { 'justin'; }
sub DBPASS()   { 'laotzu83'; }

#----------------------------------------------------------------------------
# PRIVATE METHODS
#----------------------------------------------------------------------------

sub _get_cached
{
    my ($self) = @_;

    my ($dbh, $md5) = @{$self}{'dbh', 'md5'};
    confess "MD5 digest is missing" unless defined $md5;

    my $sql = 'SELECT tidycode, hilitecode FROM pmtidy WHERE md5=?';
    my @cols = $dbh->selectrow_array( $sql, undef, $md5 );

#        or warn "error searching for md5 match: ${\$dbh->errstr}";

    if( @cols ) {
        $self->{'tidycode'}   = $cols[0];
        $self->{'hilitecode'} = $cols[1];
        return 1;
    }

    return 0;
}

sub _cache_results
{
    my ($self) = @_;

    my ($dbh, $md5) = @{$self}{'dbh', 'md5'};
    confess "MD5 digest is missing" unless defined $md5;

    my $sql = 'INSERT INTO pmtidy (md5, tidycode, hilitecode) VALUES (?,?,?)';
    $dbh->do( $sql, undef, $md5, @{$self}{'tidycode', 'hilitecode'} )
        or warn "error caching result into DB: ${\$dbh->errstr}";

    return 1;
}


#----------------------------------------------------------------------------
# PUBLIC METHODS
#----------------------------------------------------------------------------

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);

    my $dbh;
    if ( scalar @_ == 3 ) {
        ($dbh) = splice @_, 2, 1;
        croak "invalid second argument to PMTidy::CodeBlock::DB->new"
            unless $dbh->isa('DBI::db');
    }

    unless ( $dbh ) {
        $dbh = DBI->connect( DBSOURCE, DBUSER, DBPASS ) or
            die "failed DBI->connect: $DBI::errstr";
    }

    $self->{'dbh'} = $dbh;
    return $self;
}

sub do_perltidy
{
    my $self = shift;

    my $md5 = md5( $self->{'cleancode'} );
    $self->{'md5'} = $md5;

    unless ( $self->_get_cached ) {
        $self->SUPER::do_perltidy;
        $self->_cache_results;
    }
    return $self;
}

1;

#----------------------------------------------------------------------------

package main;
use strict;
use warnings;

use File::Spec;
use CGI         qw{:standard};

sub UNPERLMSG() { return 'How very unperlish of you!' }

my $cgi       = new CGI;
my $code      = $cgi->param('code');
my $tag       = $cgi->param('tag');

$tag = '' unless defined $tag;

eval {
    die 'No code given' unless(defined $code);

    # put the perltidy.ERR file in a temporary directory
    my $tmpdir = File::Spec->tmpdir;
    chdir $tmpdir or die "could not chdir to $tmpdir: $!";

    my $codeblock = PMTidy::CodeBlock::DB->new($code);

    $codeblock->force_whitespace if ( lc($tag) eq 'p' );

    print $cgi->header('-content-type' => 'text/xml; charset=ISO-8859-1'),
        <<"END_XML";
<?xml version="1.0" ?>
<pmtidy>
<status>success</status>
<hilitecode>

<![CDATA[
${$codeblock->hilited()}
]]>

</hilitecode>
<tidycode>

<![CDATA[
${$codeblock->tidied()}
]]>

</tidycode>
</pmtidy>
END_XML

};

if ($@) {
    if( $@ =~ /^Not perl code/ ) {
        print $cgi->header('-content-type' => 'text/xml; charset=ISO-8859-1'),
            <<"END_XML";
<?xml version="1.0" ?>
<pmtidy>
<status>failure</status>
<error>$@</error>
</pmtidy>
END_XML
    }
    else {
        print $cgi->header(-status => 500), $@;
    }
}

exit 0;

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

PMTidy::CodeBlock - Object to do all the work

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

=head1 CREDITS

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
