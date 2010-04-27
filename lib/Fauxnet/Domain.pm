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
    $self->{at} = {};
    $self->{chattiness} = 0;
    $self->{notes} = {};
    $self->{perTicks} = [];


    # message queues
    $self->{direct} = [];
    $self->{bcast} = [];

    open TFH,">fauxnet.out";
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
        my $node = Fauxnet::Node->new(
            $n,
            $self->{ chattiness },
            $self->{ node_reliability },
            $self->{ node_recovery_time },
        );
        $self->addNode( $node );
        $n--;
    }
}

sub addNodeEvent {
    my ($self, $when, $named, $cb) = @_;

    $self->{node_tick_cbs}->{$named} = $cb; 
    if ($when eq 'tick') {
        foreach my $n (keys(%{$self->{nodes}})) {
            $self->{nodes}->{$n}->addTickCallback($named);
        }
    } 

}

sub tick {
    my ($self) = @_;

    # any scheduled jobs?
    if ($self->{at}->{ $self->{clock}->time() }) {
        my $jobs = $self->{at}->{$self->{clock}->time()};
        foreach my $j (@$jobs) {
            $j->($self);
        }
    }

    my @downs; # a list of hosts in status "down";
    my $prop = 0;
    foreach my $nodename (keys(%{$self->{nodes}})) {
        $self->{nodes}->{ $nodename }->tick($self);

         # look for "down" hosts
        if ($self->{nodes}->{ $nodename }->{status} eq "dead") {
            push(@downs, $nodename);
        }
        # check propagation of data
        if ($self->{nodes}->{ $nodename }->{aux}->{foo} eq "bar") {
            $prop += 1;
        }
    }
    my $downcount = scalar(@downs);

    # route messages, inefficiently
    my @bcasts = @{$self->{'bcast'}};
    foreach my $b (@bcasts) {
        foreach my $nodename (keys(%{$self->{nodes}})) {
            $self->{nodes}->{ $nodename }->receive_message($b);
            $self->{sent} += 1;
            $self->{broadcasted} += 1;
        }
    }
    my @directs = @{$self->{'direct'}};
    foreach my $m (@directs) {
        my $to = $m->{to};
        next unless defined $self->{nodes}->{$to};
        $self->{nodes}->{ $to }->receive_message($m);
            $self->{sent} += 1;
    }
    $self->{bcast} = [];
    $self->{direct} = [];

    foreach my $p (@{$self->{perTicks}}) {
        # run callback, give it a ref to the domain and the name of the callback
        $p->{code}->($self, $p->{name});
    }

    $self->writenotes();
}

sub addPerTick {
    my ($self, $name, $sub) = @_;

    push(@{$self->{perTicks}}, {name=>$name, code=>$sub});
}

sub note {
    my ($self, $key, $val) = @_;

    $self->{'notes'}->{$key} = $val;
}

sub writenotes {
    my ($self) = @_;

    print "writenotes:\n";
    print Dumper $self->{'notes'};

    open THF, ">>fauxnet.out";
    unless ($self->{_has_written_note_keys}) {
        print THF join(',', keys(%{$self->{'notes'}}));
        print THF "\n";
        $self->{_has_written_note_keys} = 1;
    }
    print THF join(',', values(%{$self->{'notes'}}));
    print THF "\n";
    close THF;

    $self->{'notes'} = {};
}

sub addEvent {
    my ($self, $at, $sub) = @_;

    unless (defined ($self->{at}->{$at})) {
        $self->{at}->{$at} = [];
    }

    push (@{$self->{at}->{$at}}, $sub);
}

# XXX DESIGN DECISION: "perturb" models an event happening within a node
# as opposed to a state-changing message hitting a node
sub perturb {
    my ($self, $thing) = @_;

    # choose a random node
    my $n = $self->{nodes}->{ int(rand(scalar(keys(%{$self->{nodes}})))) };
    $n->perturb($thing);
}

sub sendBroadcast {
    my ($self, $message) = @_;

    push(@{$self->{bcast}}, $message);
}

sub sendMessage {
    my ($self, $message) = @_;

    push(@{$self->{direct}}, $message);
}

sub run {
    my ($self) = @_;

    while ($self->{rounds}) {
        $self->tick();

        print "-------------------------\ndomain: tick " . $self->{clock}->time() . ": $self->{sent} sent ($self->{broadcasted} broadcasted) messages\n";

        $self->{clock}->beat();
        $self->{rounds} -= 1;

        # brute-force large chunk of network falling away
#        if ($self->{rounds} == 900) {
#            foreach my $h (125..250) {
#                delete $self->{nodes}->{$h};
#            }
#        }
#        if ($self->{rounds} == 600) {
#            foreach my $h (125..250) {
#                my $node = Fauxnet::Node->new($h, $self->{ chattiness });
#                $self->addNode($node);
#            }
#        }
     }
}

1;
