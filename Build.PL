use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'App::PerlMonks::Tidy',
    license             => 'perl',
    dist_author         => q{Justin Davis <juster@cpan.org>},
    dist_version_from   => 'lib/App/PerlMonks/Tidy.pm',
    build_requires => {
        'Test::More' => 0,
    },
    add_to_cleanup      => [ 'App-PerlMonks-Tidy-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
