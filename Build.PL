use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'Tie::FieldVals',
    license             => 'perl',
    dist_author         => 'Kathryn Andersen',
    dist_version_from   => 'lib/Tie/FieldVals.pm',
	requires            => {
	     'Carp' => 0,
	     'Fcntl' => 0,
	     'Tie::Array' => 0,
	     'Tie::File' => 0,
	     'Data::Dumper' => 0,
	     'Getopt::Long' => 2.34,
	     'Pod::Usage' => 0,
	     'Getopt::ArgvFile' => 1.08,
	},
    build_requires => {
        'Test::More' => 0,
    },
    #add_to_cleanup      => [ 'Tie-FieldVals-*' ],
    script_files => [qw(scripts/fv2xml scripts/xml2fv)],

);

$builder->create_build_script();
# create the Makefile.PL if need be
if (! -f 'Makefile.PL')
{
    use Module::Build::Compat;
    print "creating Makefile.PL\n";
    Module::Build::Compat->create_makefile_pl('passthrough', $builder);
}
