use lib '/Users/joshua/projects/fauxnet/lib';

use strict;
use Fauxnet::Node;
use Fauxnet::Domain;

my $domain = Fauxnet::Domain->new();
$domain->{rounds} = 120;
$domain->{nodecount} = 2500;
$domain->init();
$domain->run();
