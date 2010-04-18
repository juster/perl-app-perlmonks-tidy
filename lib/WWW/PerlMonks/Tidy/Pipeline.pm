package PerlMonks::Tidy::Pipeline;

use warnings;
use strict;

use List::MoreUtils qw(none any firstidx);
use List::Util      qw(first);
use Scalar::Util    qw();
use Readonly;
use Carp            qw(carp croak confess);

use Storable        qw(freeze thaw);
use IO::Handle;

use Data::Dumper;


Readonly my $NOTFOUND_EX => 'No matching tank found';

{
    Readonly my $STATE_STOPPED => 0;
    Readonly my $STATE_STARTED  => 1;

    Readonly my $HDRCODE_EOF  => 0;
    Readonly my $HDRCODE_DATA => 1;


    my %_head_tank;
    my %_tail_tank;
#    my %_current_tank;
    my %_state;
    my %_parent_pipes;
    my %_child_pipes;

    *id = \&Scalar::Util::refaddr;

    sub new
    {
        my $class = shift;

        my $self = bless do { my $anon_scalar; \$anon_scalar }, $class;

        $_state{$self->id} = $STATE_STOPPED;

        $self->append(@_) if @_;

        return $self;
    }

    sub start
    {
        my ($self) = @_;
        my $id = $self->id;

        local $SIG{CHLD} = undef;

        # Create async. pipes to communite between child and parent processes
        my ($parent_read, $child_write);
        pipe $parent_read, $child_write or die "pipe failed: $!";
        pipe $child_read, $parent_write or die "pipe failed: $!";

        binmode $parent_write;
        binmode $parent_read;
        binmode $child_write;
        binmode $child_read;

        $child_write->autoflush(1);
        $parent_write->autoflush(1);

        $_parent_pipes{$id} = { 'write' => $parent_write,
                                'read'  => $parent_read, };
        $_child_pipes{$id}  = { 'write' => $child_write,
                                'read'  => $child_read,  };

        # Fork off! Creates a new child process to do our work.
        my $child_pid = fork;
        return $child_pid if $child_pid;

        # In the child process, start listening for input from our
        # child "read" pipe and sending it along the linked list...
        print "### Started child process...\n";

        DATA_PACKET:
        while (1) {
            eval {
                my $data = $self->_read_pipe_data($_child_pipes{$id}->{'read'});
            };

            if ( $EVAL_ERROR ) {
                die $EVAL_ERROR if $EVAL_ERROR !~ / \A $DATA_EOF_EX /xms;

                $self->_write_pipe_hdr($_child_pipes{$id}->{'write'},
                                       EOF);
                last DATA_PACKET;
            }

            my $divert_request;
            my $current_tank = $_head_tank{$id};
            my $stash = { arg => $data,
                          divert_to => sub { $divert_request = shift; },
                          undivert  => sub { $divert_request = undef; },
                         };

            PIPE_TANK:
            while ( defined $$current_tank ) {
                print "### Current tank name: ",
                    ( defined $current_tank->{name} ?
                      $$current_tank->{name} : 'undef' ), "\n";
                $current_tank->{func}->($stash);

                if ( $divert_request ) {
                    my $divert_dest = $divert_request;
                    $divert_request = undef;

                    if ( $self->_has_diversion( $current_tank, $divert_dest )) {
                        $$current_tank = $self->_get_diversion( $current_tank,
                                                                $divert_dest );
                        next PIPE_TANK;
                    }
                    else {
                        carp qq{Invalid diversion to $divert_dest },
                            qq{attempted by $current_tank->{name}};
                    }

                }

                $current_tank = $current_tank->{next};
            }

            $current_tank = undef;

            # Pass the result to the parent process and exit the child...
            my $frozen_result = freeze(\$stash->{arg})
                or die "freezing pipeline result failed";
            use bytes;
            print $child_write pack( 'L', bytes::length $frozen_result ),
                $frozen_result;
        }
        close $child_write;

        print "### Child process exiting...\n";
        exit 0;
    }

    sub dequeue
    {
        print "### Parent process waiting for data...\n";

        my $self = shift;
        my $id = $self->id

        my ($result_hdr, $result_frozen, $result);

        my $pipe = $_parent_pipes{$self}->{read};
        $result_hdr = $self->_read_pipe_hdr($pipe);

        if ( $result_hdr->{code} == $HDRCODE_EOF ) {
            $_state{$self->id} = $STATE_STOPPED;
            return undef;
        }

        print "### Parent, pipe is $result_hdr->{length} bytes\n";
        read $pipe, $result_frozen, $result_len
            or "failed to read frozen result from pipe: $!";
        $result = thaw($result_frozen)
            or die 'failed thawing result from pipe';
        print "### Parent process retrieved result\n";

        return $$result;
    }

    sub append
    {
        croak 'Invalid arguments to append' if @_ < 2;
        my ($self) = shift;
        my $id = $self->id;

        croak 'Cannot append a tank while pipeline is flowing'
            if $self->is_flowing();

        my $argnum = 0;

        # We can take a whole bunch of arguments...

        while (@_) {
            my ($next_arg, $name, $code_ref);
            $next_arg = shift;
            ++$argnum;

            # Check all of our arguments...

            # Check if no name is provided, only a coderef...
            if ( eval { ref $next_arg eq 'CODE' } ) {
                $code_ref = $next_arg;
                #$name = undef;
            }
            elsif ( ref $next_arg ) {
                croak qq{Invalid argument number $argnum.\n},
                       q{Must be a name or a code reference}
            }
            else {
                $name = $next_arg;
                $code_ref = shift;
                ++$argnum;

                croak qq{Invalid argument number $argnum.\n},
                       q{What follows a scalar (name) must be a code reference}
                    if ! eval { ref $code_ref eq 'CODE' };
            }

            # Add our new tank to the end of our linked list...

            $self->insert( $name, $code_ref );
        }
    }

    sub insert
    {
        croak 'Invalid arguments to insert' if @_ < 3;
        my ($self, $new_name, $new_code_ref, $before_this) = @_;
        my $id = $self->id;

        croak "Cannot insert a new tank while pipeline is flowing"
            if $self->is_flowing();

        my $new_tank = $self->_make_new_tank($new_name, $new_code_ref);

        if ( !defined $before_this ) {
            # The list is empty there is no head
            # node or tail node...
            if ( !$_head_tank{$id} ) {
#                warn "DEBUG: Assigning new head & tail\n";
                $_head_tank{$id} = $new_tank;
                $_tail_tank{$id} = $new_tank;
                return;
            }

            # $before_this is undefined, the new tank goes
            # to the end, becoming the tail node...
#            warn "DEBUG: New tank is the new tail node\n";
            $_tail_tank{$id}->{next} = $new_tank;
            $_tail_tank{$id} = $new_tank;
            return;
        }

        # $before_this is the head node,
        # the new tank becomes the head tank...
        if ( $before_this == $_head_tank{$id} ) {
            $new_tank->{next} = $_head_tank{$id};
            $_head_tank{$id} = $new_tank;
            return;
        }

        my $prev = $_head_tank{$id};
        my $iter = $prev->{next};
        while ($iter) {
            if ( $iter->{name} eq $before_this ) {
                $prev->{next} = $new_tank;
                $new_tank->{next} = $iter;
                return;
            }

            $prev = $iter;
            $iter = $iter->{next};
        }

        die $NOTFOUND_EX . " ($before_this)";
    }

    sub allow_diversion
    {
        croak 'Invalid arguments to allow_diversion' if @_ != 3;
        my ($self, $from_name, $to_name) = @_;

        croak 'Cannot create a diversion while pipeline is flowing'
            if $self->is_flowing();

        my $from_tank_ref = $self->_find_tank($from_name)
            or croak qq{Unknown tank to divert from: "$from_name"};
        my $to_tank_ref   = $self->_find_tank($to_name)
            or croak qq{Unknown tank to divert to: "$to_name"};

        my $diversions = $from_tank_ref->{diversions};
        return if ( exists $diversions->{$to_name} );

        $diversions->{$to_name} = $to_tank_ref;
        return;
    }

#     sub divert_to
#     {
#         my ($self, $tank_name) = @_;
#         my $id = $self->id;

#         if ( !$self->is_flowing() ) {
#             croak qq{Pipeline does not appear to be flowing.\n},
#                    q{Can't call divert_to unless it is...};
#         }

#         my $current_tank = $_current_tank{$id};

#         if ( ! exists $current_tank->{diversions}->{$tank_name} ) {
#             croak qq{Invalid diversion to '$tank_name'.\n},
#                   qq{Must register '$tank_name' with make_diversion};
#         }

#         $_divert_request{$id} = $current_tank->{diversions}->{$tank_name};
#         return;
#     }

#     sub undivert
#     {
#         my ($self) = @_;
#         $_divert_request{$self->id} = undef;
#         return;
#     }

    sub is_flowing
    {
        my $self = shift;
        return defined $_current_tank{$self->id};
    }

    sub _write_pipe_hdr
    {
        die 'Invalid arguments to _write_pipe_hdr' if @_ != 3;
        my ($self, $pipe, $header) = @_;

        print $pipe pack 'CL', @{header}{'code','length'};
        return;
    }

    sub _read_pipe_hdr
    {
        die 'Invalid arguments to _read_pipe_hdr' if @_ != 2;
        my ($self, $pipe) = @_;

        my $pipe_hdr;
        read $pipe, $pipe_hdr, 5 or die "failed to read header from pipe: $!";
        my ($hdr_code, $result_len) = unpack 'CL', $result_hdr;

        return { code => $hdr_code, length => $result_len };
    }

    sub _find_tank
    {
        my ($self, $tank_name) = @_;
        my $id = $self->id;

        my $iter = $_head_tank{$id};

#        print "DEBUG: _find_tank started\n";

        while ( defined $iter ) {
#            print "DEBUG: iter name = ",$iter->{name},"\n";
            return $iter if defined $iter->{name} &&
                $iter->{name} eq $tank_name;

            $iter = $iter->{next};
        }

        croak $NOTFOUND_EX . " ($tank_name)";
    }

    sub _make_new_tank
    {
        confess 'Invalid arguments to _make_new_tank' if @_ != 3;
        my ($self, $new_name, $new_code_ref) = @_;

        return { name       => $new_name, func => $new_code_ref,
                 diversions => {},        next => undef };
    }

    sub _has_diversion
    {
        my ($self, $tank_ref, $divert_name) = @_;
        return defined $tank_ref->{diversions}->{$divert_name};
    }

    sub _get_diversion
    {
        my ($self, $tank_ref, $divert_name) = @_;
        return $tank_ref->{diversions}->{$divert_name};
    }
}
