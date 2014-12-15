#!/usr/bin/perl

#* get_news.pl: Retrieves news items for inclusion in front and news pages.
#* Copyright 2003-2014, Joseph T. Richardson.
#* All comments prefixed with asterisks (*) are new annotations on
#* historical code.

use strict;
use warnings 'all';

use Getopt::Long;

$| = 1;

chdir "$ENV{'HOME'}/bin" || die "Couldn't chdir to ~/bin";

#=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=#

#* The news file was a plain text file with news items delimited
#* by __ITEM__ lines.

my $newsfile = '../meta/news';
my $separator = '__ITEM__';

my $number = 0;
my $order = 'newest';

GetOptions (
	'number=i' => \$number,
	'order=s'  => \$order,
);

if ($order ne 'newest' && $order ne 'oldest') {
	$order = 'newest';
}

my (@allrecords, @records);

{
	#* Read in all the records.
	local $/ = "$separator\n";
	open (NEWS, "<$newsfile") || die "Couldn't open $newsfile: $!";
	@allrecords = <NEWS>;
	chomp(@allrecords);
	close (NEWS);
}

if ($number == 0 || $number > scalar(@allrecords)) {
	$number = scalar(@allrecords);
}

while ($number) {
	my $record;
	if ($order eq 'newest') {
		$record = pop @allrecords;
	} else {
		$record = shift @allrecords;
	}
	push (@records, $record);
	$number--;
}

#* Format them for inclusion into the calling webpage.

print "<ul class=\"news\">\n";
foreach my $record (@records) {
	#print "-" x 80, "\n";
	$record = "<li class=\"newsitem\">$record</li>\n";
	print "$record";
}
print "</ul>\n";
