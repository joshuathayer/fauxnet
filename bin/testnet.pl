use lib '/Users/joshua/projects/fauxnet/lib';

use strict;
use Fauxnet::Node;
use Fauxnet::Domain;

my $domain = Fauxnet::Domain->new();
$domain->{rounds} = 120;

my $nodes;
my $n = 250;
while ($n > 0) {
    $domain->addNode( Fauxnet::Node->new($n) );
    $n--;
}

$domain->run();
