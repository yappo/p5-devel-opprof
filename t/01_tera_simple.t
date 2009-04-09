use strict;
use warnings;
use Test::More tests => 1;
use Devel::OpProf;

is(ref(Devel::OpProf::profile(sub{+{}})), 'HASH');

