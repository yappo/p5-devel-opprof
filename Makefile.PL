use inc::Module::Install;
name 'Devel-OpProf';
all_from 'lib/Devel/OpProf.pm';

# requires '';

tests 't/*.t';
author_tests 'xt';

build_requires 'Test::More';
use_test_base;
auto_include;
auto_set_repository;
WriteAll;
