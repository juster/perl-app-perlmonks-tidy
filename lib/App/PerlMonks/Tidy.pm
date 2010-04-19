package WWW::PerlMonks::Tidy;
#use base qw(Exporter);

use Scalar::Util qw(refaddr);
use English      qw(-no_match_vars);
use Carp         qw(carp croak);

use WWW::PerlMonks::Tidy::CodeBlock;

sub new
{
    my $class  = shift;

    bless { }, $class;
}

#---PUBLIC FUNCTION---
# Usage    : my $code = decode_x-url_encoding( $cgi_params )
# Params   : $code - String containing 'code' received as CGI parameter.
#                    This would be x-url-encoded, with HTML entities
#                    encoded.
# Returns  : The result here _should_ be regular code.  The only HTML
#            in the code should be optional <font> tags used with the
#            wordwrapping.
#-------------------
sub decode_x-url_encoding
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

sub force_html_whitespace {
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

1;
