use lib "/Users/joshua/projects/fauxnet/lib";

use strict;
use Fauxnet::Clock;

my $clock = Fauxnet::Clock->new();

print $clock->beat() . "\n";
print $clock->beat() . "\n";
my $clock2 = Fauxnet::Clock->new();
print $clock2->beat() . "\n";
print $clock->beat() . "\n";
