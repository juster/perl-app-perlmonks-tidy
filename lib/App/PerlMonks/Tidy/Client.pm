package App::PerlMonks::Tidy::Client;

use warnings;
use strict;

use version qw();

sub new
{
    my ($class, $useragent) = @_;

    my ($name, $version) = split m{/}, $useragent;
    bless { name    => $name,
            version => version->new( $version ),
           }, $class;
}

sub name
{
    return shift->{name};
}

sub version
{
    return shift->{version};
}

sub wants_html
{
    return shift->{version} < '2.0';
}

sub wants_xml
{
    return ! shift->wants_html;
}

1;

__END__
