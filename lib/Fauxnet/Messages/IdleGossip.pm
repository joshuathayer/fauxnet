package Fauxnet::Messages::IdleGossip;

use strict;

# message that only has gossip data

sub new {
    my $class = shift;
    my $self = {};

    $self->{'command'} = "IdleGossip";
    $self->{'id'} = undef;  # the sender's ID ("from")
    $self->{'to'} = undef;
    $self->{'time'} = undef;
    $self->{'peers'} = undef;
    $self->{'version'} = undef;

    return bless $self, $class;
}

1;

