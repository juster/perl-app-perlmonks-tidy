package PerlMonks::Tidy::CodeBlock;
use warnings;
use strict;

use HTML::Entities  qw(decode_entities);
use Perl::Tidy      qw(perltidy);
use Readonly        qw(Readonly);
use English         qw(-no_match_vars);
use Carp            qw(carp croak confess);

our $VERSION = '1.4';

Readonly my $UNPERLMSG  => 'How very unperlish of you!';
Readonly my $ENDPIPE_EX => 'Pipeline finished early';

{# BEGIN Package Scope

    # Create an id function
    require Scalar::Util;
    *id = \&Scalar::Util::refaddr;

    ####
    #### PRIVATE MEMBERS (Inside-out Object)
    ####

    my (%_code, %_trail_lines, %_wrap,
        %_pipeline, %_pipestatus);

    ####
    #### PRIVATE METHODS
    ####

    #---OBJECT METHOD---
    # Usage    : my $result = $codeblock->_decode_cgi_param( $code )
    # Params   : $code - String containing 'code' received as CGI parameter.
    #                    This would be x-url-encoded, with HTML entities
    #                    encoded.
    # Returns  : The result here _should_ be regular code.  The only HTML
    #            in the code should be optional <font> tags used with the
    #            wordwrapping.
    #-------------------

    sub _decode_cgi_param
    {
        my ($self, $source) = @_;
        #die unless eval { ref $source eq 'SCALAR' && ref $dest eq 'SCALAR' };

        my $dest = $source;
        $dest =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg; # from URI::Encode

        decode_entities($dest);

        #if (uc $tag eq 'P') {
        $dest =~ tr{\xA0}{ }; # &nbsp;
        $dest =~ s{<br */?>}{}g;
        #}

        return $dest;
    }

    #---OBJECT METHOD---
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

        my $wrap = $_wrap{id $self};
        if ( $$text_ref =~ m{<font color="red">(.*?)</font>} ) {
            if ($1 eq '+') {
                # Exlicit word wrapping in Display setting nodelet
                $$text_ref =~ m{(?:^|\n)(.+?)\n<font color="red">\+</font>};
                $wrap->{len} = length $1;

                # Record all of the wrapped lines, to rewrap them later.
                my @lines = split /\n/, $$text_ref;
                $wrap->{lines} = $self->_find_word_wraps( \@lines );
                $wrap->{mode}  = 'normal';
                $$text_ref =~ s{\n<font color="red">\+</font>}{}gm;
            }
            else {
                # Auto wordwrapping
                $$text_ref =~ /^(.*)<font color="red">/m;
                $wrap->{len}  = length $1;
                $wrap->{mode} = 'auto';
                $$text_ref =~ s{ <font color="red"><b><u>
                                 \xC2\xAD
                                 </u></b></font> }{}gxms;
            }

            return 1;
        }

        $wrap->{mode} = 'off';
        return 0;
    }

    #---OBJECT METHOD---
    # Usage    : $self->_perltidy( $text_ref, $tidyargs )
    # Params   : $text_ref - Reference to the code plaintext to tidy.
    #            $tidyargs - Arguments, just like the perltidy commandline.
    # Purpose  : Perl::Tidy wrapper that captures error messages.
    # Throws   : $UNPERLMSG if perltidy displayed errors (usually syntax).
    #-------------------
    sub _perltidy
    {
        # The stderr option to perltidy does not seem to do anything!.
        # So we force it muahaha! Take that!

        die 'Invalid arguments to _perltidy' if @_ != 3;
        my ($self, $text_ref, $tidyargs) = @_;

        my ($tmpstderr, $oldstderr, $errors, $dest);
        $errors = '';
        open $tmpstderr, '>', \$errors
            or die "open for temp STDERR: $!";

        $oldstderr = *STDERR;
        *STDERR    = $tmpstderr;

        perltidy( source       => $text_ref,
                  destination  => \$dest,
                  argv         => $tidyargs );

        *STDERR = $oldstderr;
        close $tmpstderr;

        # XXX: Maybe another custom message should be here
        confess $errors if $errors;

        $$text_ref = $dest;
        return;
    }


    #---OBJECT METHOD---
    # Usage    : my $foundlines = $codeblock->_find_word_wraps( $lines );
    # Params   : $lines - Arrayref to the lines of the code (HTML from PM)
    # Purpose  : Find where PerlMonks has forced line breaks in
    #            the HTML.
    # Comments : Unless "Code Wrapping Off" or "Auto Code Wrapping" is
    #            selected in the "Display" settings nodelet, PerlMonks
    #            wraps lines at a certain
    #            "Code Wrap Length".
    # Returns  : Arrayref of indices into @$lines where line breaks were found.
    #-------------------

    sub _find_word_wraps
    {
        my ($self, $lines_ref) = @_;
        my ($joined, %found) = 0;
        for my $i ( 0 .. scalar(@$lines_ref) - 1 ) {
            if ( $lines_ref->[$i] =~ m{ ^ <font color="red">
                                        [+] </font>}xms ) {
                $found{$i-1 - $joined++} = 1;
                # We want the previous line, remember matches get joined
                # to the previous line, hence $joined.
            }
        }
        return [ sort { $a <=> $b } keys %found ];
    }

    #---OBJECT METHOD---
    # Usage    : $success = $codeblock->_insert_word_wraps( $linewraps_ref,
    #                                                       $lines_ref,
    #                                                       $linemax )
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
            my $line = \$lines_ref->[$wrapline];
            my $charcount = 0;
            my @blocks = grep { length; } split /(<\/?span.*?>)/, $$line;

            BLOCKLOOP:
            for my $block (@blocks) {
                next BLOCKLOOP if($block =~ /^<.*>$/);
                my $blockchars = length $block;

                # HTML entities must be counted as one character.
                # But when inserting the linebreak we must skip them.
                my @entities; # ([ entity_start, entity_length-1 ], ...)
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
            } #BLOCKLOOP

            $$line = join '', @blocks;
        } #LINELOOP

        return;
    }


    sub _anon_scalar {
        my $anon_scalar;
        return \$anon_scalar;
    }

    ####
    #### PUBLIC METHODS
    ####

    sub new
    {
        croak 'Invalid arguments to new' if @_ < 2;
        my ($class, $params) = @_;

        croak 'Must provide a hashref for the constructor'
            if ! eval { ref $params eq 'HASH' };

        my $html_tag  = $params->{tag} || 'P';
        my $tidy_type = $params->{action};
        $tidy_type = lc $tidy_type;

        if ( ! $tidy_type ) {
            croak qq{Must provide an 'action' key/value.\n},
                q{Action can be either 'tidy' or 'hilite'};
        }

        my $self = bless _anon_scalar(), $class;
        my $id   = id $self;
        my $skip_prepare;
        if ( exists $params->{code} || exists $params->{uri} ) {
            $_code{$id} = $params->{code} || $params->{uri};
            $skip_prepare = 0;
        }
        elsif ( exists $params->{plaintext} ) {
            $_code{$id} = $params->{plaintext};
            $skip_prepare = 1;
        }
        else {
            croak  q{Missing required 'code', 'uri', or 'plaintext' } .
                  qq{parameter\n to PerlMonks::CodeBlock->new};
        }

        $_wrap{$id} = { mode => 'off', len => undef, lines => [] };

        $_pipeline{$id}   = [

            ( $skip_prepare
              ? ()                     : 'pipe_toplaintext' ),

            'pipe_pretidy',

            ( $tidy_type eq 'tidy'
              ? 'pipe_tidy'            : () ),

            'pipe_hilite',

            'pipe_posttidy',

            ( $tidy_type eq 'hilite'
              ? 'pipe_rewordwrap'      : () ),

            ( $html_tag  eq 'P'
              ? 'pipe_forcewhitespace' : () ),

        ];

        $_pipestatus{$id} = 0;

        return $self;
    }

    sub process_code
    {
        my $self = shift;
        my $id   = $self->id;

        my $methods = $_pipeline{$id};
        my $start   = $_pipestatus{$id};
        my $text_ref = \$_code{$id};

        # Filter our code through each step in the pipeline...
        PIPE_SEGMENT:
        for my $step_num ( $start .. $#{$methods} ) {
            my $method_name = $methods->[$step_num];

            eval {
                $self->$method_name($text_ref);
            };

            # Allow skipping past the rest of the methods...
            if ($EVAL_ERROR) {
                if ( $EVAL_ERROR =~ /^ $ENDPIPE_EX /xms ) {
                    $_pipestatus{$id} = scalar @$methods;
                    last PIPE_SEGMENT;
                }

                croak $EVAL_ERROR;
            }

            $_pipestatus{$id} = $step_num + 1;
        }

        return;
    }

    sub _is_pipedone {
        my $self = shift;
        my $id = id $self;
        return $_pipestatus{$id} == scalar $_pipeline{$id};
    }

    sub pipe_toplaintext {
        my ($self, $block_ref) = @_;
        my $id = id $self;

        # Decode the x-url encoded cgi parameter and remove html...
        $self->_decode_cgi_param($block_ref);

        # Record the number of trialing newlines to restore later...
        $_trail_lines{$id} = ( $$block_ref =~ / (\n+) \z /xms
                               ? (length $1)-1 : 0 );

        # Record and remove word wraps...
        $self->_remove_word_wraps($block_ref);

        return;
    }

    sub pipe_pretidy {
        return;
    }

    sub pipe_tidy {
        my ($self, $text_ref) = @_;
        die 'Code text argument must be a reference'
            unless eval { ref $text_ref eq 'SCALAR' };

        my $tidyargs;

        if ( $_wrap{id $self}->{mode} ne 'off' ) {
            my $wraplen = $_wrap{id $self}->{len};
            $tidyargs = "-sil=0 -l=$wraplen";
        }
        else {
            $tidyargs = "-sil=0";
        }

        $self->_perltidy( $text_ref, $tidyargs );
        return;
    }

    sub pipe_hilite {
        my ($self, $text_ref) = @_;
        die unless eval { ref $text_ref eq 'SCALAR' };

        my $hiliteargs = '-html -pre';

        $self->_perltidy( $text_ref, $hiliteargs );

        $$text_ref =~ s{</?a.*?> }{}gxms; # remove anchors
        $$text_ref =~ s{</?pre>\n}{}gxms; # remove surrounding pre tags

        # For string literals, PerlTidy duplicates the spaces, putting
        # them in front of the <span> tag as well as inside.  A small bug.
        #
        # BUT it doesn't have this bug for strings after __END__
        # ... sheesh
        $$text_ref =~ s{ ^ [ ]+ (?=<span[ ]class="q">\s+) }{}gxms;

        return;
    }

    sub pipe_posttidy
    {
        return;
    }

    sub pipe_fixtrailing
    {
        croak 'Invalid arguments to _fix_trailing_lines' if @_ != 2;
        my ($self, $text_ref) = @_;
        croak 'Code text argument must be a scalar reference'
            unless eval { ref $text_ref eq 'SCALAR' };

        my $trail_lines = $_trail_lines{id $self};

        die 'pipe_prepare_code must be run before _fix_trailing_lines'
            unless defined $trail_lines;

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

    #---OBJECT METHOD---
    # Usage    : $success = $codeblock->_restore_word_wraps( \$code )
    # Purpose  : Redo the linewrapping for the hilited version, if
    #            linewrapping is explicitly set in PM's User Settings.
    # Comments : This won't work for the tidied version because lines could
    #            move around or become longer/shorter when tidied.
    # Returns  : 1
    #-------------------

    sub pipe_rewordwrap
    {
        my ($self, $text_ref) = @_;

        croak "_remove_word_wraps must be called before _restore_word_wraps"
            unless defined $_wrap{id $self}->{mode};

        my $wrap = $_wrap{id $self};
        if ( $wrap->{mode} eq 'normal' && defined $wrap->{len} ) {
            $$text_ref =~ m{(\n)+$};
            my $lostnewlines = $1;

            my @codelines = split /\n/, $$text_ref;
            $self->_insert_word_wraps( $wrap->{lines},
                                       \@codelines,
                                       $wrap->{len} );
            $$text_ref = join "\n", @codelines;
            $$text_ref .= $lostnewlines;
        }

        return;
    }

    sub pipe_forcewhitespace {
        my ($self, $text_ref) = @_;

        # &nbsp must be intermixed with spaces because two or more spaces
        # are truncated to one inside a <p> html tag...

        $$text_ref =~
            s{ ( ^ [ ]+ |      # Lines starting with spaces
                   [ ]{2,} ) } # Two or more spaces
             { '&nbsp; ' x ( length($1) / 2 ) .
                   ( length($1) % 2 ? '&nbsp;' : '' ) }gexms;

        $$text_ref =~ s|\n|<br />\n|g;

        return;
    }

    # END pipeline methods

    sub get_result
    {
        my $self = shift;

        if ( !$self->_is_pipedone() ) {
            $self->process_code();
        }

        return $_code{id $self};
    }

} # END Package-wide Scope

1;
