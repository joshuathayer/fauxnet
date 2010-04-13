package Fauxnet::Node;

use strict;
use Fauxnet::Clock;
use Fauxnet::Messages::IExist;
use Fauxnet::Messages::IdleGossip;

sub new {
    my $class = shift;
    my $id = shift;

    # peer list looks like
    # state => { 
    #       peers => {
    #           host0 => {
    #               lastseen => ...,
    #               heartbeat => ...,
    #           },
    #            host1 => { ... },
    #            ...
    #        }
    #    }

    my $self = {
        id => $id,
        state => {},
        clock => new Fauxnet::Clock,
        version => 0,
        heartbeat_period => 10,
        last_heartbeat => 0,
    };

    $self->{incoming_messages} = [];

    # start heartbeats at different times
    $self->{last_heartbeat} = $self->{heartbeat_period} * rand(1);

    print "node $id instantiated\n";

    bless $self, $class;
    return $self;
}

# FOR BOOTSTRAPPING- mutate local state
sub addpeer {
    my ($self, $peer) = @_;

    print "$self->{id}: manually adding peer $peer->{id}\n";

    $self->{state}->{peers}->{ $peer->{id} } = {};
    $self->{state}->{peers}->{ $peer->{id} }->{lastseen} = $self->{clock}->time();
    $self->{state}->{peers}->{ $peer->{id} }->{version} = $peer->{version};

}

# called by our scheduler every "clock cycle"-
# this can be used to simulate periodic events within the node
sub tick {
    my ($self) = @_;

    my $time = $self->{clock}->time();
    my $bcast = []; my $direct = [];

    $self->handle_messages();

    if ($time >= ($self->{last_heartbeat} + $self->{heartbeat_period})) {
        $self->{last_heartbeat} = $time;
        my $t = $self->heartbeat();
        $bcast = $t->{broadcast};
        $direct = $t->{direct};
    }

    # XXX rule: if you tick and know no peers, throw a D-100 and if it comes up 42, 
    # send out a broadcast "i exist" message

    my @plist = keys(%{$self->{state}->{peers}});
    if (not (scalar(@plist))) {
        if (int(rand(100)) == 42) {
            print "$self->{id}: i would like to heartbeat, but i know no peers to send to\n";

            my $b = Fauxnet::Messages::IExist->new();
            $b->{id} = $self->{id};
            $b->{time} = $self->{clock}->time();

            push(@$bcast, $b);
        }
    }
    return({broadcast => $bcast, direct => $direct});
}

sub heartbeat {
    my ($self) = @_;
    # chose random peer 

    my @plist = keys(%{$self->{state}->{peers}});

    if (not(scalar(@plist))) {
        return({broadcast => [], direct => []});
    }

    # XXX rule: per heartbeat call, you pick exactly one host to send directly to
    # this is gossip!
    my $host = $plist[ int(rand($#plist + 1)) ];

    my $ret = Fauxnet::Messages::IdleGossip->new();
    $ret->{time} = $self->{clock}->time();
    $ret->{version} = $self->{version};
    $self->{version} += 1;

    $ret->{peers} = $self->{state}->{peers};
    $ret->{to} = $host;
    $ret->{id} = $self->{id};

    # support returning messages to multiple peers
    my @directs;
    push(@directs, $ret);

    # XXX rule: if it has been N ticks since a host has checked-in anywhere, 
    # according to my state, then it's considered offline!
    my $now = $self->{clock}->time();
    foreach my $h (keys (%{$self->{state}->{peers}})) {
        if (($now - 200) > $self->{state}->{peers}->{$h}->{seen}) {
            print "***** $self->{id} sees a host $h as being down! *****\n";
            delete $self->{state}->{peers}->{$h};
        }
    }

    print "$self->{id}: i know of " . scalar(keys(%{$self->{state}->{peers}})) . " peers at time " . $self->{clock}->time() . "\n";
    
    return({broadcast => [], direct => \@directs});
}

sub receive_message {
    my ($self, $message) = @_;
    push (@{$self->{incoming_messages}}, $message);
}

sub handle_messages {
    my ($self) = @_;

    return unless scalar(@{$self->{incoming_messages}});

    # print "$self->{id}: " . scalar(@{$self->{incoming_messages}}) . " messages enqueued\n";
    foreach my $m (@{$self->{incoming_messages}}) {
        # print "\tfrom $m->{'id'}: $m->{'command'}\n";
        my $ref = $self->can($m->{'command'});
        if ($ref) {
            $ref->($self, $m);
        } else {
            print "$self->{id}: unknown command $m->{command}\n";
        }
    }

    $self->{incoming_messages} = [];

}

### message handlers!
sub IExist {
    my ($self, $m) = @_;

    # so. we get a heartbeat "i exist" message from someone
    # let's integrate this node into our state

    my $from = $m->{id};

    # do we know this peer at all?
    if (not(defined($self->{state}->{peers}->{$from}))) {
        print "$self->{id}: received iexist from unknown peer $from\n";
        $self->{state}->{peers}->{$from} = {};
        $self->{state}->{peers}->{$from}->{version} = 0; # force merge
        $self->{state}->{peers}->{$from}->{seen} = $self->{clock}->time(); 
    }
}

sub IdleGossip {
    my ($self, $m) = @_;

    # print "$self->{id}: received idlegossip from $m->{id}\n";

    my $from = $m->{id};
    my $version = $m->{version};

    # do we know this peer at all?
    if (not(defined($self->{state}->{peers}->{$from}))) {
        print "\t$self->{id}: received idlegossip from unknown peer $from!\n";
        $self->{state}->{peers}->{$from} = {};
        $self->{state}->{peers}->{$from}->{version} = 0; # force merge
        $self->{state}->{peers}->{$from}->{seen} = $self->{clock}->time(); 
    }

    # we might have already received this state update
    if ($self->{state}->{peers}->{$from}->{version} <  $version) {
        print "\t$self->{id}: received a new state via idlegossip from $from ($version)\n";

        # merge logic!
        foreach my $host (keys(%{$m->{peers}})) {
            
            if(not(defined($self->{state}->{peers}->{$host}))) {
                # this is a host that we don't know about yet, so we will add it
                #print "\t$self->{id}: fruitful gossip! hearing about host $host\n";
                $self->{state}->{peers}->{$host} = $m->{peers}->{$host};
            } else {
                # ok this is a host we know about... what do we do?
                # meaning: do we increment the last-seen? does this count as being seen?
                # XXX we say yes: we know that *some* host saw it at some explicit time more
                # recent than we saw it
                if ($self->{state}->{peers}->{$host}->{seen} < $m->{peers}->{$host}->{seen}) {
                    $self->{state}->{peers}->{$host}->{seen} = $m->{peers}->{$host}->{seen};
                }
            }
        }
    } else {
        print "\t$self->{id}: received a state from $from that i'd already seen\n";
    }
}

1;
