package RPM::Make;

# Scott Harrison

# In order to view the documentation internal to this module,
# please type    "perldoc ./Make.pm"

use vars qw(
	    $VERSION
	    );

$VERSION='0.4';

# ----------------------------------------------------- Plain Old Documentation

=pod

=head1 NAME

RPM::Make - cleanly generate an RPM

=head1 SYNOPSIS

    use RPM::Make;

    my @filelist=('tmproot/file1.txt',
		  'tmproot/file2.txt',
		  'tmproot/file3.txt',
		  'tmproot/file4.txt');

    my %doc; my %conf; my %confnoreplace; my %metadata;

    $doc{'tmproot/file1.txt'}=1;
    $conf{'tmproot/file2.txt'}=1;
    $confnoreplace{'tmproot/file3.txt'}=1;

    my $pathprefix='tmproot';
    my $tag='Test';
    my $version='0.1';
    my $release='1';

    %metadata=(
	       'vendor'=>'Excellence in Perl Laboratory',
	       'summary'=>'Test Software Package',
	       'name'=>$tag,
	       'copyrightname'=>'...',
	       'group'=>'Utilities/System',
	       'AutoReqProv'=>'no',
	       'requires'=>[('PreReq: setup',
			     'PreReq: passwd',
			     'PreReq: util-linux'
			     )],
	       'description'=>'This package is generated by RPM::Make. '.
                      'This implements the '.$tag.' software package',
        'pre'=>'echo "You are installing a package built by RPM::Make; '.
                      'RPM::Make is available at http://www.cpan.org/."',
 	       );

    my $buildloc='TempBuildLoc';

    # the "execute" subroutine coordinates all of the RPM building steps
    RPM::Make::execute($tag,$version,$release,$arch,$buildloc,$pathprefix,
		       \@filelist,\%doc,\%conf,\%confnoreplace,
		       \%metadata);

    # you can also build an RPM in more atomic steps; these three smaller
    # steps are equivalent to the execute command

    # Step 1: generate the rpm source location
    RPM::Make::rpmsrc($tag,$version,$release,$buildloc,$pathprefix,
 	              \@filelist,\%doc,\%conf,\%confnoreplace,
		      \%metadata);

    # Step 2: build the rpm and copy into the invoking directory
    RPM::Make::compilerpm($buildloc,$metadata{'name'},$version,
			  $release,$arch,
			  $currentdir,$invokingdir);

    # Step 3: clean the location used to gather and build the rpm
    RPM::Make::cleanbuildloc($buildloc);

=cut

=pod

=head1 SUBROUTINES

=cut

use strict;

###############################################################################

=pod

=head2 RPM::Make::testsystem()

Check to see if RPM builder application is available

=over 4

=item INPUT

n/a

=item OUTPUT

n/a

=item ERROR

if /usr/lib/rpm/rpmrc does not exist, print error and exit

=item NOTE

To date, this testing action has been fully adequate, though imperfect.

=cut

sub testsystem {
    unless (-e '/usr/lib/rpm/rpmrc') { # part of the expected rpm package
	print(<<END);
**** ERROR **** This script only works with a properly installed RPM builder
application.  
Cannot find /usr/lib/rpm/rpmrc, so cannot generate customized rpmrc file.
Script aborting.
END
        exit(1);
    }
}

###############################################################################

=pod

=head2 RPM::Make::execute($tag,$version,$release,$arch,$buildloc,$pathprefix,\@filelist,\%doc,\%conf,\%confnoreplace,\%metadata);

Build the RPM in one clean sweep.

=over 4

=item INPUT

5 scalar strings, 1 array reference, and 4 hash references

=item OUTPUT

n/a

=item ERROR

n/a (specific to the other subroutines that are called)

=item NOTE

First calls &rpmsrc, then &compilerpm, then &cleanbuildloc.

=cut

sub execute {
    my ($tag,$version,$release,$arch,$buildloc,$pathprefix,
	$filelistref,$docref,$confref,$confnoreplaceref,$metadataref)=@_;
    &testsystem();
    my $name=rpmsrc($tag,$version,$release,$buildloc,$pathprefix,
	   $filelistref,$docref,$confref,$confnoreplaceref,$metadataref);

    my $currentdir=`pwd`; chomp($currentdir); my $invokingdir=$currentdir;
    $currentdir.='/'.$buildloc;
    compilerpm($buildloc,$name,$version,$release,$arch,
	       $currentdir,$invokingdir);
    cleanbuildloc($buildloc);
}

###############################################################################

=pod

=head2 RPM::Make::rpmsrc($tag,$version,$release,$buildloc,$pathprefix,\@filelist,\%doc,\%conf,\%confnoreplace,\%metadata);

Properly assemble the RPM source location (prior to building)

=over 4

=item INPUT

5 scalar strings, 1 array reference, and 4 hash references

=item OUTPUT

n/a

=item ERROR

$version, $release, and $buildloc variables need to have a string length
greater than zero, else the module causes an exit(1).

$tag must only consist of alphanumeric characters, else the module
causes an exit(1).

=item NOTE

Should be called before &compilerpm and &cleanbuildloc.

=cut

sub rpmsrc {
    my ($tag,$version,$release,$buildloc,$pathprefix,
	$filelistref,$docref,$confref,$confnoreplaceref,$metadataref)=@_;
    &testsystem();
    if (!$version or !$release) { # defined and string length greater than zero
	print "**** ERROR **** Invalid version or release argument.\n";
	exit(1);
    }
    if ($tag=~/\W/) { # non-alphanumeric characters cause problems
	print(<<END);
**** ERROR **** Invalid tag name "$tag"
END
        exit(1);
    }
    if (-e "$buildloc") {
	print(<<END);
**** ERROR **** buildloc "$buildloc" already exists; remove it before running!
END
        exit(1);
    }
    if (!length($buildloc)) {
	print(<<END);
**** ERROR **** buildloc "$buildloc" needs to be defined
END
        exit(1);
    }

# ----- Generate temporary directories (subdirs of first command-line argument)

    print('Generating temporary directory ./'.$buildloc."\n");
    mkdir($buildloc,0755) or
	die("**** ERROR **** cannot generate $buildloc directory\n");
    mkdir("$buildloc/BuildRoot",0755);
    mkdir("$buildloc/SOURCES",0755);
    mkdir("$buildloc/SPECS",0755);
    mkdir("$buildloc/BUILD",0755);
    mkdir("$buildloc/SRPMS",0755);
    mkdir("$buildloc/RPMS",0755);
    mkdir("$buildloc/RPMS/i386",0755);

# -------------------------------------------------------- Initialize variables
    my $file;
    my $binaryroot=$buildloc.'/BinaryRoot';
    my ($type,$size,$octalmode,$user,$group);
    
    my $currentdir=`pwd`; chomp($currentdir); my $invokingdir=$currentdir;
    $currentdir.='/'.$buildloc;

# ------------------------------- Create a stand-alone rpm building environment

    print('Creating stand-alone rpm build environment.'."\n");
    open(IN,'</usr/lib/rpm/rpmrc')
	or die('Cannot open /usr/lib/rpm/rpmrc'."\n");
    my @lines=<IN>;
    close(IN);

    open(RPMRC,">$buildloc/SPECS/rpmrc");
    foreach my $line (@lines) {
	if ($line=~/^macrofiles/) {
	    chomp($line);
	    $line.=":$currentdir/SPECS/rpmmacros\n";
	}
	print(RPMRC $line);
    }
    close(RPMRC);

    open(RPMMACROS,">$buildloc/SPECS/rpmmacros");
    print(RPMMACROS <<END);
\%_topdir $currentdir
\%__spec_install_post    \\
/usr/lib/rpm/brp-strip \\
/usr/lib/rpm/brp-strip-comment-note \\
\%{nil}
END
    close(RPMMACROS);

# ----------------------------------------- Determine $name and other variables
    my $name;
    if ($$metadataref{'name'} && $$metadataref{'name'}!~/\W/) {
	$name=$$metadataref{'name'};
    }
    else {
	$name=$tag;
    }
    my $summary=$$metadataref{'summary'};
    my $vendor=$$metadataref{'vendor'};
    my $copyright=$$metadataref{'copyrightname'};
    $copyright='not specified here' unless $copyright;
    my $autoreqprov=$$metadataref{'AutoReqProv'};
    my $requires=join("\n",@{$$metadataref{'requires'}});
    my $description=$$metadataref{'description'};
    my $pre=$$metadataref{'pre'};
    my $rpmgroup=$$metadataref{'group'};

# ------------------------------------- Print header information for .spec file

    open(SPEC,">$buildloc/SPECS/$name-$version.spec");
    print(SPEC <<END);
Summary: $summary
Name: $name
Version: $version
Release: $release
Vendor: $vendor
BuildRoot: $currentdir/BuildRoot
Copyright: $copyright
Group: $rpmgroup
Source: $name-$version.tar.gz
AutoReqProv: $autoreqprov
$requires
# requires: filesystem
\%description
$description

\%prep
\%setup

\%build
rm -Rf "$currentdir/BuildRoot"

\%install
make ROOT="\$RPM_BUILD_ROOT" SOURCE="$currentdir/BinaryRoot" directories
make ROOT="\$RPM_BUILD_ROOT" SOURCE="$currentdir/BinaryRoot" files
make ROOT="\$RPM_BUILD_ROOT" SOURCE="$currentdir/BinaryRoot" links

\%pre
$pre

\%post
\%postun

\%files
END

# ------------------------------------ Process file list and gather information

    my %BinaryRootMakefile;
    my %Makefile;
    my %dotspecfile;

    my @filelist=@{$filelistref}; # do not overwrite $filelistref contents
    foreach my $file (@filelist) {
	chomp($file);
	my $comment="";
	if ($$confref{$file}) {
	    $file.=" # conf";
	}
	if ($$confnoreplaceref{$file}) {
	    $file.=" # conf(noreplace)";
	}
	if ($$docref{$file}) {
	    $file.=" # doc";
	}
	if ($file=~/\s+\#(.*)$/) {
	    $file=~s/\s+\#(.*)$//;
	    $comment=$1;
	}
	my $directive="";
	if ($comment=~/config\(noreplace\)/) {
	    $directive="\%config(noreplace) ";
	}
	elsif ($comment=~/config/) {
	    $directive="\%config ";
	}
	elsif ($comment=~/doc/) {
	    $directive="\%doc";
	}
	if (($type,$size,$octalmode,$user,$group)=find_info($file)) {
	    $octalmode="0" . $octalmode if length($octalmode)<4;
	    if ($pathprefix) {
		$file=~s/^$pathprefix//;
	    }
	    if ($type eq "files") {
	push(@{$BinaryRootMakefile{$type}},"\tinstall -D -m $octalmode ".
		     "$pathprefix$file $binaryroot$file\n");
		push(@{$Makefile{$type}},"\tinstall -D -m $octalmode ".
		     "\$(SOURCE)$file \$(ROOT)$file\n");
	push(@{$dotspecfile{$type}},"$directive\%attr($octalmode,$user,".
		     "$group) $file\n");
	    }
	    elsif ($type eq "directories") {
	push(@{$BinaryRootMakefile{$type}},"\tinstall -m $octalmode -d ".
		     "$binaryroot$file\n");
		push(@{$Makefile{$type}},"\tinstall -m $octalmode -d ".
		     "\$(SOURCE)$file \$(ROOT)$file\n");
		push(@{$dotspecfile{$type}},"\%dir \%attr($octalmode,$user,".
		     "$group) $file\n");
	    }
	    elsif ($type eq "links") {
	my $link=$size; # I use the size variable to pass the link value
		# from the subroutine find_info
		$link=~s/^$pathprefix//;
		push(@{$BinaryRootMakefile{$type}},
		     "\tln -s $link $binaryroot$file\n");
		push(@{$Makefile{$type}},"\tln -s $link \$(ROOT)$file\n");
		push(@{$dotspecfile{$type}},"\%attr(-,$user,$group) $file\n");
	    }
	}
    }
    
# -------------------------------------- Generate SRPM and BinaryRoot Makefiles

# Generate a much needed directory.
# This directory is meant to hold all source code information
# necessary for converting .src.rpm files into .i386.rpm files.
    mkdir("$buildloc/SOURCES/$name-$version",0755);

    open(OUTS,">$buildloc/SOURCES/$name-$version/Makefile");
    open(OUTB, ">$buildloc/BinaryRootMakefile");
    foreach $type ("directories","files","links") {
	print(OUTS "$type\:\n");
	print(OUTS join("",@{$Makefile{$type}})) if $Makefile{$type};
	print(OUTS "\n");
	print(OUTB "$type\:\n");
	print(OUTB join("",@{$BinaryRootMakefile{$type}}))
	    if $BinaryRootMakefile{$type};
	print(OUTB "\n");
	print(SPEC join("",@{$dotspecfile{$type}})) if $dotspecfile{$type};
    }
    close(OUTB);
    close(OUTS);
    
    close(SPEC);

# ------------------ mirror copy (BinaryRoot) files under a temporary directory

    `make -f $buildloc/BinaryRootMakefile directories`;
    `make -f $buildloc/BinaryRootMakefile files`;
    `make -f $buildloc/BinaryRootMakefile links`;

    print('Build a tarball.'."\n");
    my $command="cd $currentdir/SOURCES; tar czvf $name-$version.tar.gz ".
    "$name-$version";

    print (`$command`);

    return $name;
}

###############################################################################

=pod

=head2 RPM::Make::compilerpm($buildloc,$name,$version,$release,$arch,$currentdir,$invokingdir);

Properly assemble the RPM source location (prior to building)

=over 4

=item INPUT

8 scalar strings

=item OUTPUT

n/a

=item ERROR

If the B<rpm -ba> command fails when sent to the system execution shell,
then print an error notice and exit(1).

=item NOTE

Should be called after &rpmsrc and before &cleanbuildloc.

=cut

sub compilerpm {
    my ($buildloc,$name,$version,$release,$arch,$currentdir,$invokingdir)=@_;
    &testsystem();

    # command1a works for rpm version <=4.0.2
    # command1b works for rpm version >4.0.4
    # the strategy here is to...try one approach, and then the other

    my $command1a="cd $currentdir/SPECS; rpm --rcfile=./rpmrc ".
	"--target=$arch -ba ".
	"$name-$version.spec";
    my $command1b="cd $currentdir/SPECS; rpm --rcfile=./rpmrc ".
	"-ba --target $arch ".
	"$name-$version.spec";
    my $command2="cd $currentdir/RPMS/$arch; cp -v ".
	"$name-$version-$release.$arch.rpm $invokingdir/.";
    print "$command1a\n";
    print (`$command1a`);
    if ($?!=0) {
	print(<<END);
**** WARNING **** RPM compilation failed for rpm version 4.0.2 command syntax
(...trying another command syntax...)
END
        print "$command1b\n";
        print (`$command1b`);
        if ($?!=0) {
   	    print(<<END);
**** ERROR **** RPM compilation failed for rpm version 4.0.4 command syntax
(...no more syntax choices to try...)
END
            exit(1);
        }
    }
    print "$command2\n";
    print (`$command2`);
    if ($?!=0) {
   	    print(<<END);
**** ERROR **** Copying from temporary build location failed.
END
            exit(1);
    }
}

###############################################################################

=pod

=head2 RPM::Make::cleanbuildloc($buildloc);

Clean build location - usually F<TempBuildLoc> (all the files normally
associated with a *.src.rpm file).

=over 4

=item INPUT

1 scalar string

=item OUTPUT

n/a

=item ERROR

If the B<rpm -ba> command fails when sent to the system execution shell,
then print an error notice and exit(1).

=item NOTE

Should be called after &rpmsrc and before &cleanbuildloc.

=cut

sub cleanbuildloc {
    my ($buildloc)=@_;
    &testsystem();
    if (!length($buildloc)) {
	print(<<END);
**** ERROR **** buildloc "$buildloc" already exists
END
        exit(1);
    }
    else {
	print (`rm -Rf $buildloc`);
	if ($?!=0) {
	    print(<<END);
**** ERROR **** RPM compilation failed
END
            exit(1);
	}
    }
    return;
}

###############################################################################

=pod

=head2 RPM::Make::find_info($file_system_location);

Recursively gather information from a directory

=over 4

=item INPUT

1 scalar string

=item OUTPUT

n/a

=item ERROR

If $file_system_location is neither a directory, or softlink, or regular file,
then abort.

=item NOTE

Called by &rpmsrc.

=cut

sub find_info {
    my ($file)=@_;
    my $line='';
    if (($line=`find $file -type f -prune`)=~/^$file\n/) {
	$line=`find $file -type f -prune -printf "\%s\t\%m\t\%u\t\%g"`;
	return("files",split(/\t/,$line));
    }
    elsif (($line=`find $file -type d -prune`)=~/^$file\n/) {
	$line=`find $file -type d -prune -printf "\%s\t\%m\t\%u\t\%g"`;
	return("directories",split(/\t/,$line));
    }
    elsif (($line=`find $file -type l -prune`)=~/^$file\n/) {
	$line=`find $file -type l -prune -printf "\%l\t\%m\t\%u\t\%g"`;
	return("links",split(/\t/,$line));
    }
    die("**** ERROR **** $file is neither a directory, soft link, or file.\n");
}

1;

# ------------------------------------------------ More Plain Old Documentation

=pod

=head1 DESCRIPTION

Automatically generate an RPM software package from a list of files.

B<RPM::Make> builds the RPM in a very clean and configurable fashion.
(Finally!  Making RPMs outside of F</usr/src/redhat> without a zillion
file intermediates left over!)

B<RPM::Make> generates and then deletes temporary
files needed to build an RPM with.
It works cleanly and independently from pre-existing
directory trees such as F</usr/src/redhat/*>.

B<RPM::Make> accepts five kinds of
information, three of which are significant:

=over 4

=item *

(significant) a list of files that are to be part of the software package;

=item *

(significant) the filesystem location of these files

=item *

(significant) a descriptive tag and a version tag for the naming of the
RPM software package;

=item *

documentation and configuration files;

=item *

and additional metadata
associated with the RPM software package.

=back

When using RPM::Make::execute, a temporary directory named $buildloc is

=over 4

=item *

generated under the directory from which you run your script.

=item *

then deleted after the *.rpm
file is generated.

=back

The RPM will typically be named
"$metadata{'name'}-$version-$release.i386.rpm".
If $metadata{'name'} is not specified, then $tag is used.

Here are some of the items are generated inside
the $buildloc directory during the construction of an RPM:

=over 4

=item *

RPM .spec file (F<./$buildloc/SPECS/$name-$version.spec>)

=item *

RPM Makefile (F<./$buildloc/SOURCES/$name-$version/Makefile>)

This is the Makefile that is called by the rpm
command in building the .i386.rpm from the .src.rpm.
The following directories are generated and/or used:

=over 4

=item *

SOURCE directory: F<./$buildloc/BinaryRoot/>

=item *

TARGET directory: F<./$buildloc/BuildRoot/>

=back

=item *

BinaryRootMakefile (F<./$buildloc/BinaryRootMakefile>)

This is the Makefile that this script creates and calls
to build the F<$buildloc/BinaryRoot/> directory from the existing
filesystem.
The following directories are generated and/or used:

=over 4

=item *

SOURCE directory: / (your entire filesystem)

=item *

TARGET directory: F<./$buildloc/BinaryRoot/>

=back

=back

The final output of B<RPM::Make::execute> is a binary F<.rpm> file.
The F<./buildloc> directory is deleted (along with the F<.src.rpm>
file).  The typical file name generated by B<RPM::Make> is
F<$tag-$version-$release.i386.rpm>.

B<RPM::Make> is compatible with either rpm version 3.* or rpm version 4.*.

=head1 README

Automatically generate an RPM software package from a list of files.

B<RPM::Make> builds the RPM in a very clean and configurable fashion
without using /usr/src/redhat or any other filesystem dependencies.

B<RPM::Make> generates and then deletes temporary
files (and binary root directory tree) to build an RPM with.

B<RPM::Make> was originally based on a script "make_rpm.pl" available
at http://www.cpan.org/scripts/.

=head1 PREREQUISITES

This script requires the C<strict> module.

=head1 AUTHOR

 Scott Harrison
 sharrison@users.sourceforge.net

Please let me know how/if you are finding this module useful and
any/all suggestions.  -Scott

=head1 LICENSE

Written by Scott Harrison, sharrison@users.sourceforge.net

Copyright Michigan State University Board of Trustees

This file is part of the LearningOnline Network with CAPA (LON-CAPA).

This is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This file is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

The GNU Public License is available for review at
http://www.gnu.org/copyleft/gpl.html.

For information on the LON-CAPA project, please visit
http://www.lon-capa.org/.

=head1 STATUS

This module is new.  It is based on a well-tested (and well-used)
script that I wrote (make_rpm.pl; available at http://www.cpan.org/scripts/).

=head1 OSNAMES

Linux

=cut
