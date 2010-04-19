package WWW::PerlMonks::Tidy;
#use base qw(Exporter);

use Scalar::Util qw(refaddr);
use English      qw(-no_match_vars);
use Carp         qw(carp croak);

use WWW::PerlMonks::Tidy::CodeBlock;

{
    my %_code_class, %_dbh;

    sub new
    {
        my $class  = shift;
        my $params = shift;

        my $self = bless do { my $anon_scalar; \$anon_scalar; }, $class;

        *codeblock = $self->_curry_codemethod;

        return $self;
    }

    sub codeblock
    {
        
    }

    sub 
}

1;
