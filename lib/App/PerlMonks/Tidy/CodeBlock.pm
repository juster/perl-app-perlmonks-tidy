package App::PerlMonks::Tidy::CodeBlock;

use warnings;
use strict;

use HTML::Entities  qw();
use Perl::Tidy      qw(perltidy);
use English         qw(-no_match_vars);
use Carp            qw();

our $VERSION   = '2.0';

#------------------------------------------------------------------------------
# HELPER FUNCTIONS
#------------------------------------------------------------------------------

#---HELPER FUNCTION---
# Usage    : my $foundlines = _find_word_wraps( \@lines );
# Params   : @lines - Array of the lines of code (HTML from PM)
# Purpose  : Find where PerlMonks has forced line breaks by
#            using HTML.
# Comments : Unless "Code Wrapping Off" or "Auto Code Wrapping" is
#            selected in the "Display" settings nodelet, PerlMonks
#            wraps lines at a certain "Code Wrap Length".
# Returns  : Arrayref of indices into @$lines where line breaks were found.
#-------------------

sub _find_word_wraps
{
    my ($lines_ref)      = @_;
    my ($joined, %found) = 0;

    for my $i ( 0 .. $#$lines_ref ) {
        if ( $lines_ref->[$i] =~ m{ ^ <font color="red">
                                    [+] </font>}xms ) {
            $found{$i-1 - $joined++} = 1;
            # We want the previous line, remember matches get joined
            # to the previous line, hence $joined.
        }
    }

    return [ sort { $a <=> $b } keys %found ];
}

#---HELPER FUNCTION---
# Usage    : $success = _insert_word_wraps( $linewraps_ref,
#                                           $lines_ref,
#                                           $linemax )
# Params   : $linewraps_ref - Arrayref to the results of find_word_wraps
#            $lines_ref     - Arrayref to the lines of source
#                             (HTML from perltidy output)
#            $linemax       - The count of characters at which to wrap a
#                             line
# Purpose  : Re-wraps lines, duplicating Perlmonks's output.  HTML tags and
#            entities must be ignored to not affect the line wrapping.
# Postcond : Array pointed to by $lines_ref will be modified in place.
# Returns  : 1
#-------------------

sub _insert_word_wraps {
    my ($linewraps_ref, $lines_ref, $linemax) = @_;

    LINELOOP:
    for my $wrapline ( @$linewraps_ref ) {
        my $line      = \$lines_ref->[$wrapline];
        my $charcount = 0;
        my @blocks    = grep { length; } split /(<\/?span.*?>)/, $$line;

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
                    last ENTLOOP
                        if ( $entities[0][0]+$newchars > $breakpos );

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
        }                       #BLOCKLOOP

        $$line = join '', @blocks;
    }                           #LINELOOP

    return;
}

#---HELPER FUNCTION---
# Usage    : _perltidy( \$code_ref, $tidyargs )
# Params   : $code_ref - A reference to the code.
#            $tidyargs - Arguments, just like the perltidy commandline.
# Purpose  : Perl::Tidy wrapper that captures error messages.
#-------------------
sub _perltidy
{
    # The stderr option to perltidy does not seem to do anything!.
    # So we force it muahaha! Take that!

    die 'Invalid arguments to _perltidy' if @_ != 2;
    my ($code_ref, $tidyargs) = @_;

    my ($tmpstderr, $oldstderr, $errors, $dest);
    $errors = '';
    open $tmpstderr, '>', \$errors
        or die "open for temp STDERR: $!";

    $oldstderr = *STDERR;
    *STDERR    = $tmpstderr;

    perltidy( source       => $code_ref,
              destination  => \$dest,
              argv         => $tidyargs );

    *STDERR = $oldstderr;
    close $tmpstderr;

    # XXX: Maybe another custom message should be here
    die "Perl::Tidy error:\n$errors" if $errors;

    $$code_ref = $dest;
    return;
}

#------------------------------------------------------------------------------
# PIPELINE METHODS
#------------------------------------------------------------------------------

# These methods are listed in the order they should be ran...

#---PRIVATE METHOD---
sub _remove_trailing_nls
{
    my ($self, $code_ref) = @_;

    # Record the number of trailing newlines to restore later...
    $self->{trailing_NLs} = ( $$code_ref =~ / (\n+) \z /xms
                              ? (length $1) - 1 : 0 );
    return;
}

#---PRIVATE METHOD---
# Usage    : my $success = $codeblock->_remove_word_wraps( \$code )
# Params   : $code - String containing the code to be checked for
#                    wordwrapping by PerlMonks.
# Comments : Should be called after _prepare_code and before _tidycode or
#            _hilitecode.
# Returns  : 1 if wordwrapping <font> tags were found
#            0 otherwise:
#-------------------
sub _remove_word_wraps
{
    my ($self, $text_ref) = @_;

    if ( $$text_ref =~ m{<font color="red">(.*?)</font>} ) {
        if ( $1 eq '+' ) {
            # Explicit word wrapping in Display setting nodelet
            $$text_ref   =~ m{(?:^|\n)(.+?)\n<font color="red">\+</font>};
            $self->{wrap}{len} = length $1;

            # Record all of the wrapped lines, to rewrap them later.
            my @lines            = split /\n/, $$text_ref;
            $self->{wrap}{lines} = _find_word_wraps( \@lines );
            $self->{wrap}{mode}  = 'normal';
            $$text_ref           =~ s{\n<font color="red">\+</font>}{}gm;
        }
        else {
            # Auto wordwrapping
            $$text_ref          =~ /^(.*)<font color="red">/m;
            $self->{wrap}{len}  = length $1;
            $self->{wrap}{mode} = 'auto';
            $$text_ref          =~ s{ <font color="red"><b><u>
                                      \xC2\xAD
                                      </u></b></font> }{}gxms;
        }

        return 1;
    }

    $self->{wrap}{mode} = 'off';

    return 0;
}

#---PRIVATE METHOD---
sub _tidy_code {
    my ($self, $code_ref) = @_;

    my $tidyargs = ( $self->{wrap}{mode} ne 'off'
                     ? "-sil=0 -l=$self->{wrap}{len}"
                     : "-sil=0" );

    _perltidy( $code_ref, $tidyargs );
    return;
}

#---PRIVATE METHOD---
sub _hilite_code {
    my ($self, $code_ref) = @_;

    my $hiliteargs = '-html -pre';

    _perltidy( $code_ref, $hiliteargs );
    $$code_ref =~ s{</?a.*?> }{}gxms; # remove anchors
    $$code_ref =~ s{</?pre>\n}{}gxms; # remove surrounding pre tags

    # For string literals, PerlTidy duplicates the spaces, putting
    # them in front of the <span> tag as well as inside.  A small bug.
    #
    # BUT it doesn't have this bug for strings after __END__
    # ... sheesh
    $$code_ref =~ s{ ^ [ ]+ (?=<span[ ]class="q">\s+) }{}gxms;

    return;
}

#---PRIVATE METHOD---
# Usage    : $wrapped_code = $codeblock->_redo_word_wraps( $code )
# Purpose  : Redo the linewrapping for the hilited version, if
#            linewrapping is explicitly set in PM's User Settings.
# Comments : This won't work for the tidied version because lines could
#            move around or become longer/shorter when tidied.
# Returns  : 1
#-------------------

sub _redo_word_wraps
{
    my ($self, $code_ref) = @_;

    Carp::confess "_remove_word_wraps must be called before _redo_word_wraps"
        unless defined $self->{wrap};

    my $wrap = $self->{wrap};

    if ( $wrap->{mode} eq 'normal' && defined $wrap->{len} ) {
        
        $$code_ref =~ m{(\n)+$};
        my $lostnewlines = $1;

        my @codelines = split /\n/, $$code_ref;
        _insert_word_wraps( $wrap->{lines}, \@codelines, $wrap->{len} );
        $$code_ref = join "\n", @codelines;
        $$code_ref .= $lostnewlines;
    }

    return;
}

#---PRIVATE METHOD---
sub _redo_trailing_nls
{
    Carp::croak 'Invalid arguments to _fix_trailing_lines' if @_ != 2;
    my ($self, $text_ref) = @_;
    Carp::croak 'Code text argument must be a scalar reference'
        unless eval { ref $text_ref eq 'SCALAR' };

    my $trail_lines = $self->{trailing_NLs};

    # If input has no trailing newline, perltidy appends one.
    # If input has 1 or more, perltidy appends only one.
    if ( $trail_lines == 0 ) {
        chomp $$text_ref;
    }
    elsif ( $trail_lines > 0 ) {
        $$text_ref .= "\n" x $trail_lines;
    }

    return;
}

#------------------------------------------------------------------------------
# PUBLIC METHODS
#------------------------------------------------------------------------------

sub new
{
    Carp::croak 'Invalid arguments' if @_ < 2;
    my ($class, $text) = @_;

    my $self = bless { }, $class;

    $self->_remove_trailing_nls( \$text );
    $self->_remove_word_wraps( \$text );
    $self->{code} = $text;

    return $self;
}

sub perform
{
    my ($self, $action) = @_;

    Carp::croak q{Second argument must be "hilite" or "tidy"}
        unless $action eq 'hilite' || $action eq 'tidy';

    # Return a previously cached output...
    return $action if $self->{$action};

    my $result = $self->{code};

    $self->_tidy_code( \$result )         if $action eq 'tidy';
    $self->_hilite_code( \$result );
    $self->_redo_word_wraps( \$result )   if $action eq 'hilite';
    $self->_redo_trailing_nls( \$result ) if $action eq 'hilite';

    return $self->{$action} = $result;
}

sub tidied  { return shift->perform( 'tidy' )   }

sub hilited { return shift->perform( 'hilite' ) }

1;
