# Makefile.PL

use ExtUtils::MakeMaker;

print "No modules required...\n";

WriteMakefile(
    'NAME'          => 'RPM-Tools',
    'VERSION_FROM'  => 'RPM/Make.pm',
    'PMLIBDIRS' => ['RPM'],
    'DISTNAME'      => 'RPM-Tools',
    'dist'          => { COMPRESS => 'gzip --best', SUFFIX => 'gz' },
    ($] >= 5.005 ? (
      'AUTHOR'        => 'Scott Harrison <sharrison@sourceforge.net>',
    ) : () ),
    'clean'		=> {
	'FILES'	=> 'TempBuildLoc/ Test*.rpm',
    },
);
