package Fauxnet::Domain;

# simulates a broadcast domain

use strict;
use Fauxnet::Node;
use Fauxnet::Clock;
use Data::Dumper;

sub new {
    my ($class) = @_;

    my $self = {};
    $self->{clock} = Fauxnet::Clock->new();
    $self->{sent} = 0;
    $self->{broadcasted} = 0;

    return(bless($self, $class));
}

sub addNode {
    my ($self, $node) = @_;

    $self->{nodes}->{ $node->{id} } = $node;
}

sub tick {
    my ($self) = @_;
    my @bcast; my @direct;

    foreach my $nodename (keys(%{$self->{nodes}})) {
        my $t = $self->{nodes}->{ $nodename }->tick();
        my $b = $t->{broadcast};
        my $d = $t->{direct};
        @bcast = (@bcast, @$b);
        @direct = (@direct, @$d);
    }

    # route messages, inefficiently
    foreach my $b (@bcast) {
        foreach my $nodename (keys(%{$self->{nodes}})) {
            $self->{nodes}->{ $nodename }->receive_message($b);
            $self->{sent} += 1;
            $self->{broadcasted} += 1;
        }
    }
    foreach my $m (@direct) {
        my $to = $m->{to};
        $self->{nodes}->{ $to }->receive_message($m);
            $self->{sent} += 1;
    }
}

sub run {
    my ($self) = @_;

    while (1) {
        $self->tick();
        print "-------------------------\ndomain: tick " . $self->{clock}->time() . ": $self->{sent} sent ($self->{broadcasted} broadcasted) messages\n";
        sleep(1);
        $self->{clock}->beat();
    }
}

1;
