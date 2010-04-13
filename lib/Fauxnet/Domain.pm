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
    $self->{completed} = 0;
    $self->{broadcasted} = 0;
    $self->{rounds} = 0;
    $self->{nodes} = {};

    open TFH,">fauxnet-average.out";
    close TFH;

    return(bless($self, $class));
}

sub addNode {
    my ($self, $node) = @_;

    $self->{nodes}->{ $node->{id} } = $node;
}

sub init {
    my $self = shift;
    my $n = $self->{nodecount};
    while ($n) {
        $self->addNode( Fauxnet::Node->new($n) );
        $n--;
    }
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

    my @reportline;
    my $total = 0;
    my $completed = 0;
    foreach my $nodename (sort(keys(%{$self->{nodes}}))) {
        my $count = scalar(keys(%{$self->{nodes}->{$nodename}->{state}->{peers}}));
        push(@reportline, $count);
        if ($count == $self->{nodes}) {
            $completed += 1;
        }
        $total += $count;
    }

    my $newly_completed = $completed - $self->{completed};
    $self->{completed} = $completed;

    my $av = $total / scalar(keys(%{$self->{nodes}}));

    open TFH,">>fauxnet-average.out";
    print TFH "$newly_completed,$self->{completed},$self->{sent}\n";
    close TFH;
}

sub run {
    my ($self) = @_;

    while ($self->{rounds}) {
        $self->tick();
        print "-------------------------\ndomain: tick " . $self->{clock}->time() . ": $self->{sent} sent ($self->{broadcasted} broadcasted) messages\n";
# sleep(1);
        $self->{clock}->beat();
        $self->{rounds} -= 1;
    }
}

1;
