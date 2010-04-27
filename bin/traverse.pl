use lib '/Users/joshua/projects/fauxnet/lib';

use strict;
use Fauxnet::Node;
use Fauxnet::Domain;

my $domain = Fauxnet::Domain->new();
$domain->{rounds} = 1220;
$domain->{nodecount} = 250;
$domain->{chattiness} = 2;

$domain->{node_reliability} = 99.99;
$domain->{node_recovery_time} = 100;

$domain->init();

$domain->addPerTick('report', sub {
    my ($self, $name) = @_;
    print "in pertick callback $name\n";

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

    $self->note('newly_completed',$newly_completed);
    $self->note('completed',$self->{completed});
    $self->note('sent',$self->{sent});
});

$domain->addNodeEvent('tick', 'iDontKnowAnyone', sub {
    my ($self, $domain) = @_;
    # XXX rule: if you tick and know no peers, throw a D-100 and if it comes up 42, 
    # send out a broadcast "i exist" message

    my @plist = keys(%{$self->{state}->{peers}});
    if (not (scalar(@plist))) {
        if (int(rand(100)) == 42) {
            print "$self->{id}: i would like to heartbeat, but i know no peers to send to\n";

            my $b = Fauxnet::Messages::IExist->new();
            $b->{id} = $self->{id};
            $b->{time} = $self->{clock}->time();

            $domain->sendBroadcast($b);
        }
    }

});



$domain->addEvent(100, sub {
    my $domain = shift;
    $domain->perturb({ foo => "bar", });
});


$domain->run();
