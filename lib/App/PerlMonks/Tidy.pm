package App::PerlMonks::Tidy;

use Scalar::Util qw(refaddr);
use English      qw(-no_match_vars);
use Carp         qw(carp croak);

use App::PerlMonks::Tidy::CodeBlock;
use App::PerlMonks::Tidy::Client;

sub CLIENT_INPUT_MAX() { 1_048_576 }; # One megabyte

#-----------------------------------------------------------------------------
# PRIVATE METHOD
#-----------------------------------------------------------------------------

#---PRIVATE FUNCTION---
# Usage    : my $code = decode_x-url_encoding( $cgi_params )
# Params   : $code - String containing 'code' received as CGI parameter.
#                    This would be x-url-encoded, with HTML entities
#                    encoded.
# Returns  : The result here _should_ be regular code.  The only HTML
#            in the code should be optional <font> tags used with the
#            wordwrapping.
#-------------------
sub _decode_x-url_encoding
{
    my ($source) = @_;

    my $dest = $source;
    $dest =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg; # from URI::Encode

    HTML::Entities::decode_entities( $dest );

    #if (uc $tag eq 'P') {
    $dest =~ tr{\xA0}{ };       # &nbsp;
    $dest =~ s{<br */?>}{}g;
    #}

    return $dest;
}

sub _force_html_whitespace {
    my ($self, $html) = @_;

    # &nbsp must be intermixed with spaces because two or more spaces
    # are truncated to one inside a <p> html tag...

    $html =~ s{ ( ^ [ ]+ |      # Lines starting with spaces
                     [ ]{2,} ) } # Two or more spaces
               { '&nbsp; ' x ( length($1) / 2 ) .
                     ( length($1) % 2 ? '&nbsp;' : '' ) }gexms;
    $html =~ s{\n}{<br />\n}g;

    return $html;
}

#-----------------------------------------------------------------------------
# PUBLIC METHODS
#-----------------------------------------------------------------------------

sub new
{
    my ($class, $psgi_req) = @_;


    my $input_obj = $psgi_req->{'psgi.input'};
    my $post_data;

    my $read_count = $input_obj->read( $post_data, CLIENT_INPUT_MAX )
        or die 'Invalid client input';

    my $client = App::PerlMonks::Tidy::Client->new
        ( $psgi_req->{'HTTP_USER_AGENT'} );
    
    bless { 'post_data' => $post_data,
            'client'    => $client,
           }, $class;
}

sub response
{
    my ($self) = @_;

    my $block_obj;
    my $compat_mode = $self->{'client'}->wants_html;

    # Old-fashioned compatible mode.
    if ( $compat_mode ) {
        my %params = split /=/, split /[;&]/ $self->{'post_data'};

        my $code = $params{'code'}
            or die q{'code' parameter is missing};
        $code    = _decode_x-url_encoding( $code );

        my $tag = $params{'tag'}
            or die q{'tag' parameters is missing};

        my $block_obj = App::PerlMonks::Tidy::CodeBlock->new( $code );

        my $hilited = $block_obj->hilited();
        my $tidied  = $block_obj->tidied();

        if ( $tag eq 'P' ) {
            $hilited = _force_html_whitespace( $hilited );
            $tidied  = _force_html_whitespace( $tidied );
        }

        my $html = <<"END_HTML";
<html>
<div id="highlight">
${$block_obj->hilited()}
</div>
<div id="tidy">
${$block_obj->tidied()}
</div>
</html>
END_HTML
        return [ '200', 
                 [ 'Content-Type' => 'text/html' ],
                 [ $html ]
                ];
    }
    else {
        # TODO: the new and improved XML version!
        return [ '500',
                 [ 'Content-Type' => 'text/plain' ],
                 [ 'ERROR: Unimplemented' ]
                ];
                 
    }
}

1;


