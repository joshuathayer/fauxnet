package Fauxnet::Node;

use strict;
use Fauxnet::Clock;
use Fauxnet::Messages::IExist;
use Fauxnet::Messages::IdleGossip;

sub new {
    my $class = shift;
    my $id = shift;
    my $chattiness = shift;
    my $reliability = shift;
    my $recovery = shift;

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
        chattiness => $chattiness,
        reliability => $reliability,
        recovery => $recovery,
        status => "live",
        aux => {},
        tick_cbs => [],
    };

    $self->{incoming_messages} = [];

    # start heartbeats at different times
    $self->{last_heartbeat} = $self->{heartbeat_period} * rand(1);

    print "node $id instantiated\n";

    bless $self, $class;
    return $self;
}

# FOR BOOTSTRAPPING- mutate local state
# XXX notused
#sub addpeer {
#    my ($self, $peer) = @_;


#    $self->{state}->{peers}->{ $peer->{id} } = {};
#    $self->{state}->{peers}->{ $peer->{id} }->{seen} = $self->{clock}->time();
#    $self->{state}->{peers}->{ $peer->{id} }->{version} = $peer->{version};
#}

# called by our scheduler every "clock cycle"-
# this can be used to simulate periodic events within the node
sub tick {
    my ($self, $domain) = @_;

    my $time = $self->{clock}->time();
    my $bcast = []; my $direct = [];

    $self->handle_messages();

    # ok go through our list of subs to run...
    foreach my $cbName (@{$self->{tick_cbs}}) {
        my $s = $domain->{node_tick_cbs}->{$cbName};
        $s->($self, $domain);
        # a sub can (purposefully) kill a node, in which case we don't
        # want to run any other subs
        last if $self->{state} eq 'dead';
    }

    if ($time >= ($self->{last_heartbeat} + $self->{heartbeat_period})) {
        $self->{last_heartbeat} = $time;
        my $t = $self->heartbeat($domain);
    }

}

# push a callback onto the end of the list
# there should be other methods for mutating the list of what-to-do-at-tick-time
sub addTickCallback {
    my ($self, $cb) = @_;

    push(@{$self->{tick_cbs}}, $cb);
}

sub heartbeat {
    my ($self, $domain) = @_;
    # chose random peer 

    my @plist = keys(%{$self->{state}->{peers}});

    return if not (scalar(@plist));

    # XXX rule: per heartbeat call, you pick exactly N hosts to send directly to
    # this is gossip! 
    # don't try to hard to avoid picking the same host twice. at this point, just don't
    # send more than one message to the same host, but don't re-pick

    my $N = 1;
    my @directs;
    my $seens = {};
    foreach my $n (0 .. $self->{chattiness}) {
        my $host = $plist[ int(rand($#plist + 1)) ];

        next if $seens->{host};
        $seens->{$host} = 1;
        my $ret = Fauxnet::Messages::IdleGossip->new();
        $ret->{time} = $self->{clock}->time();
        $ret->{version} = $self->{version};
        $self->{version} += 1;

        $ret->{peers} = $self->{state}->{peers};
        $ret->{to} = $host;
        $ret->{id} = $self->{id};
        $ret->{aux} = $self->{aux};

        $domain->sendMessage($ret);
    }

    # XXX rule: if it has been N ticks since a host has checked-in anywhere, 
    # according to my state, then it's considered offline!
    my $now = $self->{clock}->time();
    foreach my $h (keys (%{$self->{state}->{peers}})) {
       if (($now - 50) > $self->{state}->{peers}->{$h}->{seen}) {
           delete $self->{state}->{peers}->{$h};
       }
   }

}

sub receive_message {
    my ($self, $message) = @_;
    push (@{$self->{incoming_messages}}, $message);
}

sub node_ages {
    my ($self) = @_;
    # return average and max node-peer-ages

    my $count = scalar(keys(%{$self->{state}->{peers}}));
    my $maxage = 0;
    my $average = 0;
    my $now = $self->{clock}->time();

    foreach my $n (keys(%{$self->{state}->{peers}})) {
        my $seen = $self->{state}->{peers}->{$n}->{seen};
        my $age = $now - $seen;
        if ($age > $maxage) { $maxage = $age; }
        $average += $age;
    }

    if ($count) { $average = $average / $count; } 
    else { $average = 0; }

    return($average, $maxage);

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

# ok this models a state-changing event happening within the node!
sub perturb {
    my ($self, $thing) = @_;

    print "!!!! perturbing!!!!\n";

    foreach my $k (keys(%$thing)) {
        print "$k -> $thing->{$k}\n";
        $self->{aux}->{$k} = $thing->{$k};
    }

}

### message handlers!
sub IExist {
    my ($self, $m) = @_;

    # so. we get a heartbeat "i exist" message from someone
    # let's integrate this node into our state

    my $from = $m->{id};

    # do we know this peer at all?
    if (not(defined($self->{state}->{peers}->{$from}))) {
        # print "$self->{id}: received iexist from unknown peer $from\n";
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
        # print "\t$self->{id}: received idlegossip from unknown peer $from!\n";
        $self->{state}->{peers}->{$from} = {};
        $self->{state}->{peers}->{$from}->{version} = 0; # force merge
        $self->{state}->{peers}->{$from}->{seen} = $self->{clock}->time(); 
    }

    # we might have already received this state update
    if ($self->{state}->{peers}->{$from}->{version} <  $version) {
        # nope, it's new

        # ok we blip our knowledge of this host!
        $self->{state}->{peers}->{$from}->{version} = $m->{version};
        $self->{state}->{peers}->{$from}->{seen} = $self->{clock}->time();

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
                my $my_seen = $self->{state}->{peers}->{$host}->{seen};
                my $their_seen = $m->{peers}->{$host}->{seen};
                if ($my_seen < $their_seen) {
                    $self->{state}->{peers}->{$host}->{seen} = $m->{peers}->{$host}->{seen};
                }
            }
        }

        # merge aux data too
        foreach my $k (keys(%{$m->{aux}})) {
            $self->{aux}->{$k} = $m->{aux}->{$k};
        }
    } else {
        #print "\t$self->{id}: received a state from $from that i'd already seen\n";
        $self->{state}->{peers}->{$from}->{seen} = $self->{clock}->time();
    }
}

1;
