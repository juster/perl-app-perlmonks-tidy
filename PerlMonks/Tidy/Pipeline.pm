package PerlMonks::Tidy::Pipeline;

use warnings;
use strict;

use List::MoreUtils qw(none any firstidx);
use List::Util      qw(first);
use Scalar::Util    qw();
use Readonly;
use Carp            qw(carp croak);

use Data::Dumper;

Readonly my $NOTFOUND_EX => 'No matching tank found';

{
    my %_head_tank;
    my %_tail_tank;
    my %_current_tank;
    my %_divert_request;

    sub new
    {
        my $class = shift;

        my $self = bless do { my $anon_scalar; \$anon_scalar }, $class;

        return $self;
    }

    sub flush
    {
        my ($self, $data) = @_;
        my $id = $self->id;

        my $stash = { data => $data };

        my $current_tank = $_current_tank{$id} = $_head_tank{$id};
        while ( defined $current_tank ) {
            $current_tank->{func}->($stash);

            if ($_divert_request{$id}) {
                $current_tank = $_divert_request{$id};
                $_divert_request{$id} = undef;
                next;
            }

            $current_tank = $_current_tank{$id} = $current_tank->{next};
        }

        return $stash->{data};
    }

    sub append
    {
        croak 'Invalid arguments to append' if @_ < 2;
        my ($self) = shift;
        my $id = $self->id;

        my $argnum = 0;

        # We can take a whole bunch of arguments...

        while (@_) {
            my ($name, $code_ref);
            $name = shift;
            ++$argnum;

            # Check all of our arguments...

            # Check if no name is provided, only a coderef...
            if ( eval { ref $name eq 'CODE' } ) {
                $code_ref = $name;
                $name = undef;
            }
            elsif ( ! defined $name || ref $name ) {
                croak qq{Invalid argument number $argnum.\n},
                      q{Must be a name or a code reference}

            }
            else {
                $code_ref = shift;
                ++$argnum;
                croak qq{Invalid argument number $argnum.\n},
                    q{What follows a scalar (name) must be a code reference}
                    if ! eval { ref $code_ref eq 'CODE' };

            }

            croak 'Cannot append a tank while pipeline is flowing'
                if $_current_tank{$id};

            # Add our new tank to the end of our linked list...

            my $old_tail = $_tail_tank{$id};
            my $new_tank = { name       => $name, func => $code_ref,
                             diversions => {},    next => undef };

            if ( defined $old_tail ) {
#                print "DEBUG: old_tail = $old_tail->{name}\n";
                $old_tail->{next} = $new_tank;
            }
            $_tail_tank{$id} = $new_tank;

            if ( ! defined $_head_tank{$id} ) {
                $_head_tank{$id} = $new_tank;
#                print "DEBUG: new head = $new_tank->{name}\n";
            }

        }
    }

    sub allow_diversion
    {
        croak 'Invalid arguments to allow_diversion' if @_ != 3;
        my ($self, $from_name, $to_name) = @_;

        my $from_tank_ref = $self->_find_tank($from_name);
        my $to_tank_ref   = $self->_find_tank($to_name);

        croak qq{Unknown tank to divert from: "$from_name"}
            if !$from_tank_ref;
        croak qq{Unknown tank to divert to: "$to_name"}
            if !$to_tank_ref;

        my $diversions = $from_tank_ref->{diversions};
        return if ( exists $diversions->{$to_name} );

        $diversions->{$to_name} = $to_tank_ref;
        return;
    }

    sub divert_to
    {
        my ($self, $tank_name) = @_;
        my $id = $self->id;

        my $current_tank = $_current_tank{$id} or
            croak qq{Pipeline does not appear to be flowing.\n},
                   q{Can't call divert_to_tank unless it is...};

        if ( ! exists $current_tank->{diversions}->{$tank_name} ) {
            croak qq{Invalid diversion to '$tank_name'.\n},
                  qq{Must register '$tank_name' with make_diversion};
        }

        $_divert_request{$id} = $current_tank->{diversions}->{$tank_name};
        return;
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

    *id = \&Scalar::Util::refaddr;
}
