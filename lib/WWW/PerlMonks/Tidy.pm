package PerlMonks::Tidy;
#use base qw(Exporter);

use Scalar::Util qw(refaddr);
use English      qw(-no_match_vars);
use Carp         qw(carp croak);

{
    my %_code_class, %_dbh;

    sub new
    {
        my $class  = shift;
        my $params = shift;

        my $self = bless do { my $anon_scalar; \$anon_scalar; }, $class;

        # If a DBH is supplied in our argument hashref, load
        # PerlMonks::Tidy::CodeBlock::Cached objects...
        if ( eval { ref $params eq 'HASH' } &&
             exists $params->{dbh} ) {

            if ( ! eval { $params->{dbh}->isa('DBI::db') } ) {
                croak qq{Invalid 'dbh' parameter supplied.\n}.
                    qq{Must be a DBI::db object};
            }

            require PerlMonks::Tidy::CodeBlock::Cached;
            $_dbh{refaddr $self} = $params->{dbh};
        }
        else {
            require PerlMonks::Tidy::CodeBlock;
        }

        *codeblock = $self->_curry_codemethod;

        return $self;
    }

    sub _curry_codemethod
    {
        my ($self) = @_;

        my $dbh = $_dbh{refaddr $self};
        if ( defined $dbh ) {
            return sub {
                my ($self, $params) = @_;
                if ( ! eval { ref $params eq 'HASH' } ) {
                    croak 'Parameter must be a hashref';
                }

                my $newparams = { %{$params}, dbh => $dbh };
                return PerlMonks::Tidy::CodeBlock::Cached->new( $newparams );
            };
        }

        return sub {
            return &PerlMonks::Tidy::CodeBlock::new;
        }
    }
}

1;
