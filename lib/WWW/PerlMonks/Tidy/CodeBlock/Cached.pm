package PerlMonks::Tidy::CodeBlock::Cached;
use base qw(PerlMonks::Tidy::CodeBlock);

use Digest::MD5 qw(md5);
use Readonly    qw(Readonly);
use Carp        qw(carp croak confess);
use DBI;

# Readonly my $DBSOURCE => 'dbi:mysql:juster';
# Readonly my $DBUSER   => 'justin';
# Readonly my $DBPASS   => 'laotzu83';


Readonly my $NOCACHED_EX   => 'Cached tidy code not found';
Readonly my $MISSINGMD5_EX => 'MD5 digest is migging';

{
    Readonly my $INSERT_SQL => 'INSERT INTO pmtidy (md5, tidytype, codetext)
                                VALUES (?,?,?)';
    Readonly my $SELECT_SQL => 'SELECT codetext FROM pmtidy
                                WHERE (md5=? AND tidytype=?)';

    Readonly my $TYPE_IDS   => { 'hilite' => 1, 'tidy' => 2 };

    ####
    #### PRIVATE OBJECT VARIABLES
    ####

    my (%_dbh, %_md5, %_type, %_cached);

    ####
    #### PRIVATE METHODS
    ####

    require Scalar::Util;
    *id = \&Scalar::Util::refaddr;

    #---INSTANCE METHOD---
    # Usage   : $self->_get_cached
    # Purpose : Retrieves a previously cached results from the database.
    # Throws  : $NOCACHED_EX or $MISSINGMD5_EX
    # Returns : Nothing.
    #---------------------
    sub _get_cached
    {
        my ($self, $text_ref) = @_;
        my $id = id $self;

        my $md5 = md5(${$text_ref});

        $_md5{$id} = $md5;

        # XXX: need better error checking
        my $dbh  = $_dbh{$id};
        my $type = $_type{$id};

        my $cols_ref = $dbh->selectrow_arrayref( $SELECT_SQL, undef,
                                                 $md5, $type );
        if ( $cols_ref ) {
            return $cols_ref->[0];
        }

        die $NOCACHED_EX;
    }

    #---INSTANCE METHOD---
    # Usage    : $self->_cache_results
    # Purpose  : Caches a previously tidied/hilited result into the DB.
    # Throws   : $MISSINGMD5_EX
    # Returns  : Nothing.
    #---------------------

    sub _cache_results
    {
        die 'Invalid arguments to _cache_results' if @_ != 2;
        my ($self, $code) = @_;

        my $id   = $self->id;
        my $dbh  = $_dbh{$id};
        my $type = $_type{$id};
        my $md5  = $_md5{$id};

        $dbh->do( $INSERT_SQL, undef, $md5, $type, $code )
            or carp "error caching result into DB: ${\$dbh->errstr}";

        return;
    }


    ####
    #### PUBLIC METHODS
    ####

    sub new
    {
        my $class = shift;
        my ($params) = @_;

        my $self = $class->SUPER::new(@_);

        if ( ! eval { ref $params eq 'HASH' } ) {
            croak 'Invalid parameter, must be a hashref'
        }

        # Extract tidying type from params...
        my $action;
        $action = $params->{'action'};
        $_type{$self->id} = $TYPE_IDS->{$action};

        warn "DEBUG: action=$action, type=$TYPE_IDS->{$action}\n";

        # Extract DB handle from params...
        my $dbh = $params->{dbh};
        if ( ! defined $dbh ) {
            croak qq{Missing parameter "dbh".\n},
                q{You must provide a DBI handle};
        }
        elsif ( ! eval { $dbh->isa('DBI::db') } ) {
            croak qq{Invalid parameter "dbh".\n"dbh" not a database handle};
        }
        $_dbh{$self->id} = $dbh;

        return $self;
    }

    sub pipe_pretidy
    {
        my ($self, $text_ref) = @_;

        warn "DEBUG: pipe_pretidy\n";

        eval {
            $self->_get_cached($text_ref);
            warn "DEBUG: received cache successfully\n";
            $_cached{$self->id} = 1;
            *pipe_tidy     = sub { return; };
            *pipe_hilite   = sub { return; };
        };

        if ($EVAL_ERROR) {
            die $EVAL_ERROR if $EVAL_ERROR !~ / \A $NOCACHED_EX /xms;
            return;
        }

        $self->SUPER::pipe_tidy($text_ref);

        return;
    }

    sub pipe_posttidy
    {
        my ($self, $text_ref) = @_;

        warn "DEBUG: pipe_posttidy\n";

        if ( !$_cached{$self->id} ) {
            $self->_cache_results($$text_ref);
            warn "DEBUG: cached results\n";
        }

        $self->SUPER::pipe_posttidy($text_ref);

        return;
    }

}

1;
