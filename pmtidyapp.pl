use Mojolicious::Lite;
use PMTidy::CodeBlock;

#---PRIVATE FUNCTION---
# Usage    : my $code = decode_xurl( $cgi_params )
# Params   : $code - String containing 'code' received as CGI parameter.
#                    This would be x-url-encoded, with HTML entities
#                    encoded.
# Returns  : The result here _should_ be regular code.  The only HTML
#            in the code should be optional <font> tags used with the
#            wordwrapping.
#-------------------
sub _decode_xurl
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

sub _force_htmlws {
    my ($html_ref) = @_;

    # &nbsp must be intermixed with spaces because two or more spaces
    # are truncated to one inside a <p> html tag...

    $$html_ref =~ s{ ( ^ [ ]+ |      # Lines starting with spaces
                         [ ]{2,} ) } # Two or more spaces
                   { '&nbsp; ' x ( length($1) / 2 ) .
                         ( length($1) % 2 ? '&nbsp;' : '' ) }gexms;
    $$html_ref =~ s{\n}{<br />\n}g;
}

sub codeblock { new PMTidy::CodeBlock(@_) }

get '/pmtidy-1.3.pl' => sub {
    my $self = shift;
    my $code = $Req->param('code');
    my $tag  = $Req->param('tag');

    if ( !$code || !$tag ) {
        $Res->code( 500 );
        $Res->content_type( 'text/plain' );
        return '500 Invalid Input';
    }

    $code = _decode_xurl( $code );

    my $block_obj = PMTidy::CodeBlock->new( $code );

    my ($hilited, $tidied);
    eval {
        $hilited = $block_obj->hilited();
        $tidied  = $block_obj->tidied();
    };

    if ( $@ ) {
        return 'How very unperlish of you!' if ( $@ =~ /^Perl::Tidy error:/ );

        { local $@; $LOG->error( $@ ); }
        die;
    }

    if ( uc $tag eq 'P' ) {
        _force_htmlws( \$hilited );
        _force_htmlws( \$tidied );
    }

    return <<"END_HTML";
<html>
<div id="highlight">$hilited</div>
<div id="tidy">$tidied</div>
</html>
END_HTML
};

1;
