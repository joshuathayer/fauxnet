package Fauxnet::Clock;

use strict;

# singleton monotomically-increasing clock

our $instance = undef;

sub new {
    my ($class) = @_;

    return $instance if $instance;

    my $self = {};
    $self->{clock} = 0;

    bless $self, $class;

    $instance = $self;
    return $instance;
}

sub beat {
    my $self = shift;
    $self->{clock} += 1;
    return $self->{clock};
}

sub time {
    my $self = shift;
    return $self->{clock};
}

1;
