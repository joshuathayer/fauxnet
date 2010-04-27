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

$domain->addEvent(100, sub {
    my $domain = shift;
    $domain->perturb({ foo => "bar", });
});

$domain->init();

$domain->run();
