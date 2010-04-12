package Fauxnet::Messages::IExist;

use strict;

# a broadcast "i am here and i exist" message

sub new {
    my $class = shift;
    my $self = {};

    $self->{'command'} = "IExist";
    $self->{'id'} = undef;
    $self->{'time'} = undef;

    return bless $self, $class;
}

1;

