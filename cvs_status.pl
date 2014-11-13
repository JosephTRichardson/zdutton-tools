#!/usr/bin/perl

#* cvs_status.pl: Parse the output from `cvs status` and report on modified files.
#* Ca. 2003, Joseph T. Richardson.
#* All comments prefixed with asterisks (*) are new annotations on
#* historical code.

use strict;
use warnings 'all';
use Getopt::Long;
use lib $ENV{PERLUSERLIB};
#* My own hacked version of File::Recurse.
use JTRLib::File::Recurse;

my $root = "$ENV{'HOME'}";
my $cvsroot = "$ENV{'CVSROOT'}/zdutton";
#* Directory trees that were in the CVS repository.
my @cvs_dirs = qw(raw ready meta bin);
my @ignore_dirs = (
	qr[/CVS$],
);
my @ignore_files = (
	qr[\.conf$],
	'commitlog',
	qr[changelog\.(xml|html)$],
	qr[sitemap\.(xml|html)$],
);

chdir $root || die "Can't change to $root: $!";

# Catalog all files in CVS directories
my (@files, %cvsfiles);
foreach (@cvs_dirs) {
	JTRLib::File::Recurse::recurse(\&check_file, $_);
}

my $silent = '';
my $modified = 1;
my $all = '';
GetOptions (
	'silent' => \$silent,
	'modified' => \$modified,
	'all' => \$all,
);

my $cvs = `cvs status`;
my @cvsfiles = split(/^={10,}$/m, $cvs);
shift(@cvsfiles); # Blank
my $changed = 0;
my $missing = 0;
foreach (@cvsfiles) {
	my $cvsfile;
	if (m/Repository revision:\s+\S+\s+(\S+),v/m) {
		$cvsfile = $1;
		$cvsfile =~ s/^$cvsroot\///;
		$cvsfiles{$cvsfile} = $cvsfile;
	} else {
		warn "Couldn't parse repository entry";
		print "$_\n";
	}

	if (m/^File: (.*?)\s+Status: (.*)$/m) {
		#print "$1 => $2\n" unless $silent;
		my $status = $2;
		if (! defined $cvsfile) { $cvsfile = $1; }
		if ($status !~ /^Up-to-date$/) {
			$changed++;
			print "$cvsfile => $status\n" unless $silent;
		} else {
			print "$cvsfile => $status\n" if ((! $silent) &&
				(! $modified || $all));
		}
	} else {
		warn "Couldn't parse file entry";
		print "$_\n";
	}	
}

foreach (sort @files) {
	if (! exists $cvsfiles{$_}) {
		print "MISSING FROM CVS: $_\n";
		$missing++;
	}
}

if ($changed && $missing) { exit(5); }
elsif ($changed) { exit(2); }
elsif ($missing) { exit(3); }
exit(0);

sub check_file {
	# Make sure our path is unixized
	s!\\!/!g;

	if (-d) {  # If path is a directory
		# Check to see if directory should be ignored
		foreach my $ignore (@ignore_dirs) {
			if ($_ =~ $ignore) {
				#print "Not descending into $_\n";
				return -1;  # Do no descend
			}
		}
		# Otherwise, don't add the directory entry to the queue.
		return 0;
	}
	
	foreach my $ignore (@ignore_files) {
		if ($_ =~ $ignore) {
			return 0;
		}
	}

	#$files{$_} = $_;
	push (@files, $_);
}

__END__
#* The format of the CVS status data (for my reference).

RCS file: /public/cvsroot/zdutton/raw/about.html,v
Working file: about.html
head: 2.0
branch:
locks: strict
access list:
symbolic names:
        main: 1.1.1.1
        zdutton: 1.1.1
keyword substitution: kv
total revisions: 4;     selected revisions: 1
description:
----------------------------
revision 2.0
date: 2002/10/28 00:57:01;  author: jtr;  state: Exp;  lines: +0 -0
Overhaul updates
