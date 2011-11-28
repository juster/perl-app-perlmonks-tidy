use Mojolicious::Lite;
use HTML::Entities;
use lib 'lib';
use CodeBlock;

sub _decodews
{
    my ($cr) = @_;

    decode_entities($$cr);
    $$cr =~ tr{\xA0}{ }; # &nbsp;
    $$cr =~ s{<br */?>}{}g;
    return;
}

sub _forcews
{
    # &nbsp must be intermixed with spaces because two or more spaces
    # are truncated to one inside a <p> html tag...

    s{ ( ^ [ ]+ |      # Lines starting with spaces
           [ ]{2,} ) } # Two or more spaces
     { '&nbsp; ' x (length($1) / 2) . (length($1) % 2 ? '&nbsp;' : '') }gexms;

    s{\n}{<br />\n}g;
}

sub _rmlinenums
{
    s{^\d+: }{}gm;
}

get '/' => sub { shift->render_static('index.html') };

post '/' => sub {
    my $c = shift;

    my $dom = Mojo::DOM->new($c->req->body);
    my $req = $dom->at('tidyreq');
    unless($req && $dom->at('tidyreq > code') && $dom->at('tidyreq > tag')){
        $c->render('text' => "500 Invalid Request\n", 'status' => 500);
        return;
    }

    my $code = $dom->at('tidyreq > code')->text;
    my $tag  = $dom->at('tidyreq > tag')->text;
    my $numbered;

    _decodews(\$code);
    $numbered = _rmlinenums() for($code);

    my $b = new CodeBlock($code);
    my($hilited, $tidied);
    eval { $hilited = $b->hilited(); $tidied  = $b->tidied(); };
    if($@){
        my $err = $@;
        if($err =~ /^Perl::Tidy error:/){
            $c->app->log->debug($err);
            $c->stash('errmsg' => $err);
            $c->render('template' => 'error', format => 'xml');
            return;
        }
        die; # rethrow
    }

    # TODO: move to CodeBlock class?
    if(uc $tag eq 'P'){
        _forcews() for($hilited, $tidied);
    }

    $c->stash('hilited' => $hilited);
    $c->stash('tidied' => $tidied);
    $c->render('resp', 'format' => 'xml');
};

app->start;

__DATA__

@@ error.xml.ep
<?xml version="1.0" encoding="UTF-8" ?>
<tidyresp>
<error>
<%= $errmsg %>
</error>
</tidyresp>

@@ resp.xml.ep
<?xml version="1.0" encoding="UTF-8" ?>
<tidyresp>
<hilited><![CDATA[<%== $hilited %>]]></hilited>
<tidied><![CDATA[<%== $tidied %>]]></tidied>
</tidyresp>
