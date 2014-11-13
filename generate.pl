#!/usr/bin/perl

#* generate.pl: Preprocessor to apply headers and footers to raw HTML files.
#* Ca. 2003, Joseph T. Richardson.
#* All comments prefixed with asterisks (*) are new annotations on
#* historical code.

use strict;
use warnings 'all';
use File::stat;
use File::Touch;
use File::Spec;
use File::Path;
use File::Copy;
use Getopt::Long;

#* I didn't like the implementations of these functions
#* so I modified them in my own libraries.

use lib $ENV{PERLUSERLIB};
use JTRLib::Date::Format qw(strftime);
use JTRLib::Time qw(jtrtime);
use JTRLib::File::Recurse;

$| = 1;

chdir "$ENV{'HOME'}/bin" || die "Couldn't chdir to ~/bin";

#=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=#

#* This overly complex file system had a purpose. Each directory tree
#* was for a different class of file, and all were merged together just
#* prior to upload:
#*      meta:  Metadata to be used in dynamically creating headers and footers.
#*      raw:   HTML files to which headers and footers would be applied.
#*      merge: HTML files to simply be merged, mostly created dynamically
#*             by other processes, like the changelog and name indices.
#*      ready: Non-HTML files that were "ready" to be merged, like CSS,
#*             JavaScript, and XML data.
#*      binary: Binary files to be merged, mostly image files.
#*      live:  The "live" website into which everything else was merged,
#*             ready to be uploaded.

my $globals_file = '../meta/globaldata';
my $footer_file = '../meta/footer';

my $input_root = '../raw';
my $merge_root = '../merge';
my $ready_root = '../ready';
my $binary_root = '../binary';
my $output_root = '../live';
my $working_root;

#* The "config" file consists only of the timestamp of the last time the
#* the website was generated.

my $config = 'generate.conf';
my $override_config; #= 1118688822 - 3600000;

my $debug = 1;
my $show_include_tags = 1;
my $force_all = 0;
my $rooted = 0;
my $show_unchanged = 0;
my $show_ignore = 0;
my $help = 0;

# Regexes of paths of directories or files not to upload
my @ignore_dirs = (
    qr[/CVS$],
    qr[e-mail list backup],
);

my @queue;

for ($input_root, $output_root, $merge_root) {
    # Make sure the paths are in the format we want (unixized, with
    # no trailing slashes)
    s!\\!/!g;
    s!/$!!;
}

#=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=#

GetOptions (
    "force_all"        => \$force_all,
    "debug"            => \$debug,
    "show_include|i"   => \$show_include_tags,
    "show_unchanged|u" => \$show_unchanged,
    "show_ignore|g"    => \$show_ignore,
    "help|?"           => \$help,
);

if ($help) {
    print "generate.pl for Zachariah Dutton Genealogy Web (zdutton.org).\n";
    print "Joseph T. Richardson, 2003-2010.\n";
    print "Generates live files from raw files.\n\n";
    print "Usage:\n";
    print "--force_all      -f   Force regeneration of all files\n";
    print "--debug          -d   Print debugging data\n";
    print "--show_include   -i   Show file inclusions\n";
    print "--show_unchanged -u   Show unchanged files\n";
    print "--help           -?   Show this message\n";
    exit(0);
}

#* Read in and parse the global metadata.

my %globals;
open (GLOBAL, "<$globals_file") || die "Can't open $globals_file: $!";
{
        my $state = 0;
        my $bufferkey;
        my @bufferlines;

        LINE: while (my $line = <GLOBAL>) {
            next LINE if ($line =~ m/^$/);
            if ($state == 0) {
                if ($line =~ m/^(.*?)=>$/) {
                    $bufferkey = $1;
                    $state = 2;
                }
                elsif ($line =~ m/^(.*?)=(.*)$/) {
                    my ($key, $value) = ($1, $2);
                    $globals{$key} = $value;
                }
            }
            elsif ($state == 2) {
                if ($line =~ m/^\.$/) {
                    my $buffer = join("", @bufferlines);
                    @bufferlines = ();
                    $buffer =~ s/\s+$//;
                    $globals{$bufferkey} = $buffer;
                    $state = 0;
                }
                push @bufferlines, $line;
            }
        }

        # End of file
        if ($state == 2) {
            my $buffer = join("", @bufferlines);
            @bufferlines = ();
            $buffer =~ s/\s+$//;
            $globals{$bufferkey} = $buffer;
        }

        if ($debug >= 2) {
            foreach (sort keys %globals) {
                print "$_ => ^$globals{$_}\$\n";
            }
        }
}
close (GLOBAL);
#print "Globals read: @{[keys %globals]}\n";

#* Read the standard footer.

my $footer_template;
open (FOOTER, "<$footer_file") || die "Can't open $footer_file: $!";
{
    local $/ = undef;
    $footer_template = <FOOTER>;
}
close (FOOTER);

my $lastrun = get_config($config);
if (defined $override_config) { $lastrun = $override_config; }
my $lastrunt = localtime($lastrun);
print "Running against $lastrunt\n";

#* This table defines all of the recognized meta headers and how they
#* should be processed. The values are:
#*     [type, long_name, label, title_element, value]

my @meta_headers = (
    ['meta-http',   'Content-Type',          'CONTENTTYPE'                                ],
    ['meta-http',   'Content-Style-Type',    'STYLETYPE'                                  ],
    ['meta-script', 'Content-Script-Type',   'SCRIPTTYPE'                                 ],
    ['meta',        'Author',                'AUTHOR'                                     ],
    ['meta',        'Data-Last-Modified',    'TIMESTAMP'                                  ],
    ['meta',        'Last-Modified',         'TIMESTAMP'                                  ],
    ['meta',        'Description',           'DESCRIPTION'                                ],
    ['meta',        'Keywords',              'KEYWORDS'                                   ],
    ['title',       'TITLE'                                                               ],
    ['link',        'Stylesheet',            'STYLESHEET',    undef,           'text/css' ],
    ['link',        'Up',                    'UP_HREF',      'UP_TITLE'                   ],
    ['link',        'Top',                   'TOP_HREF',     'TOP_TITLE'                  ],
    ['link',        'Index',                 'INDEX_HREF',   'INDEX_TITLE'                ],
    ['link',        'Home',                  'HOME_HREF',    'HOME_TITLE'                 ],
    ['link',        'Search',                'SEARCH_HREF',  'SEARCH_TITLE'               ],
    ['link',        'Contact',               'CONTACT_HREF', 'CONTACT_TITLE'              ],
    ['script'],
);

#* The dynamic part of the header was a set of nav links, generated based on
#* the UP_HREF, UP_TITLE, etc. of each page's meta headers -- to give the
#* site a basic hierarchical structure. As applied, the nav header appeared
#* in the following form:

# <!--Begin Page Header-->
# <div class="header">
# <a href="eddutton.html">[Up]</a>
# <a href="zdutton.html">[Top]</a>
# <a href="../nameindex.html">[Index]</a>
# <a href="../index.html">[Home]</a>
# <a href="../contact.html">[Contact]</a>
# <hr>
# </div>
# <!--End Page Header-->

#* The name of each page header and the location of its metadata.

my @page_headers = (
    ['Up',      'UP_HREF'],
    ['Top',     'TOP_HREF'],
    ['Index',   'INDEX_HREF'],
    ['Home',    'HOME_HREF'],
    ['Search',  'SEARCH_HREF'],
    ['Contact', 'CONTACT_HREF'],
);

#* I was HTML 4.01 conformant.

my $file_header = "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01//EN\" \"http://www.w3.org/TR/REC-html40/strict.dtd\">\n<html lang=\"en-US\">";
my $file_footer = "</body>\n</html>\n";
my $default_body_header = "<body class=\"gendata\">\n";

#* My 'recurse' sub was based on a version of File::Recurse from the
#* ActivePerl repository that eventually went away. I liked it and didn't
#* like change so figured I would keep using this rather than learn the new one.

#* Recurse each tree.
#* (You'd think I could have done this a little more elegantly.)

$working_root = $input_root;
JTRLib::File::Recurse::recurse(\&check_file_raw, $input_root);
run_queue($input_root);
@queue = ();

$working_root = $merge_root;
JTRLib::File::Recurse::recurse(\&check_file_raw, $merge_root);
run_queue($merge_root);
@queue = ();

$working_root = $ready_root;
JTRLib::File::Recurse::recurse(\&check_file_ready, $ready_root);
merge_queue($ready_root);
@queue = ();

$working_root = $binary_root;
JTRLib::File::Recurse::recurse(\&check_file_ready, $binary_root);
merge_queue($binary_root);
@queue = ();

# All done
write_config($config);

#* This is the main loop for preprocessing the HTML files.
sub run_queue {
    my $input_root = shift;
    my $input_root_q = quotemeta($input_root) . '\/';

    foreach my $path (@queue) {
        open(INFILE, "<$path") || die "Can't open $path for input: $!";
        my @lines = <INFILE>;
        close (INFILE);

        #* Get relative and absolute paths.
        my $rel_path = $path;
        $rel_path =~ s!^$input_root_q!!;
        my $path_to_root = path_to_root($rel_path);
        my $output_path = "$output_root/$rel_path";

        my $body_header = $default_body_header;

        next if ($debug >= 2);

        my $state = 0;
        my $line;
        my ($uptitle, $uphref, $title);
        my @datalines;
        my %filevars;
        my $bufferkey;
        my @bufferlines;

        #* Read the meta headers.
        LINE: while ($line = shift(@lines)) {
            next LINE if ($line =~ m/^$/);
            if ($line =~ m/^__DATA__$/) {
                if ($state == 2) {
                    my $buffer = join("", @bufferlines);
                    @bufferlines = ();
                    $buffer =~ s/\s+$//;
                    $filevars{$bufferkey} = $buffer;
                }
                $state = 1;
                next LINE;
            }
            if ($state == 0) {
                if ($line =~ m/^(.*)=>$/) {
                    $bufferkey = $1;
                    $state = 2;
                }
                elsif ($line =~ m/^(.*)=(.*)$/) {
                    my ($key, $value) = ($1, $2);
                    $filevars{$key} = $value;
                }
            }
            elsif ($state == 1) {
                push @datalines, $line;
            }
            elsif ($state == 2) {
                if ($line =~ m/^\.$/) {
                    my $buffer = join("", @bufferlines);
                    @bufferlines = ();
                    $buffer =~ s/\s+$//;
                    $filevars{$bufferkey} = $buffer;
                    $state = 0;
                }
                push @bufferlines, $line;
            }
        }
        if ($state != 1) {
            warn "Never reached data stage in $path";
        }

        #* All of the metadata has been read into $filevars and the
        #* remainder of the file buffered into @bufferlines.

        #* The modification time for the 'last updated' footer.
        my $st = stat($path);
        my $mtime = $st->mtime;  # Modification time
        $filevars{'TIMESTAMP'} = isodate($mtime);
        $filevars{'TIMESTAMPS'} = sdate($mtime);

        my %vars = %globals;
        foreach my $key (sort keys %filevars) {
            $vars{$key} = $filevars{$key};
        }
        foreach my $value (sort values %vars) {
            $value =~ s/%%PATH_TO_ROOT%%/$path_to_root/g;
        }

        #* Can suppress default headers or add special notes.
        if (! is_data($rel_path)) {
            $vars{'SPECNOTE'} = '';
        }
        if (exists $vars{'SUPPRESS'}) {
            my @suppress = split(/,/, $vars{'SUPPRESS'});
            foreach my $value (@suppress) {
                delete $vars{$value};
            }
        }

        if (exists $vars{'BODYCLASS'}) {
            $body_header = "<body class=\"$vars{'BODYCLASS'}\">\n";
        }

        if ($debug >= 2) {
            foreach (sort keys %globals) {
                print "$_ => ^$globals{$_}\$\n";
            }
        }

        unshift @datalines, "<!--Begin Data-->\n";
        push @datalines, "<!--End Data-->\n";

        #* Now generate and apply the headers and footers from the metadata.

        my ($meta, $head, $foot) = ('', '', '');
        $meta = generate_meta_header(\%vars);
        unless (exists $vars{'NOPAGE'}) {
            $head = generate_page_header(\%vars);
        }
        $foot = generate_footer(\%vars);

        my $data = join("", @datalines);

        #* Process requests for file includes.
        $data =~ s/<!--\@include(.+)-->/
            my $include = process_include($1);
            defined $include ? $include : "";
        /eg;

        my $document = $file_header . $meta . $body_header .
            $head . $data . $foot . $file_footer;

        { #* Make the path if it doesn't exist.
            my ($vol, $directory, $file) = File::Spec->splitpath($output_path);
            if (! -d $directory) {
                warn "Directory \"$directory\" does not exist; creating.\n";
                mkpath($directory);
            }
        }

        #* Output the finished file.
        open (OUTFILE, ">$output_path") || die "Can't open $output_path for output: $!";
        print OUTFILE $document;
        close (OUTFILE);
        print "$output_path\n";
        touch("$output_path", $mtime);
    }
}

#* Merge the non-HTML files into the live tree.
sub merge_queue {
    my $input_root = shift;
    my $input_root_q = quotemeta($input_root) . '\/';

    foreach my $path (@queue) {
        my $rel_path = $path;
        $rel_path =~ s!^$input_root_q!!;

        my $output_path = "$output_root/$rel_path";

        next if ($debug >= 2);

        my $st = stat("$path");
        my $mtime = $st->mtime;  # Modification time

        {
            my ($vol, $directory, $file) = File::Spec->splitpath($output_path);
            if (! -d $directory) {
                warn "Directory \"$directory\" does not exist; creating.\n";
                mkpath($directory);
            }
        }

        if (! copy($path, $output_path)) {
            warn "Couldn't copy $path to $output_path: $!";
            next;
        }
        print "$output_path\n";
        touch("$output_path", $mtime);
    }
}

#* The finished meta header (<head> element) should look like this:

#<head>
#   <meta http-equiv="Content-Type" content="text/html; charset=iso-8859-1">
#   <meta name="Author" content="Joseph Thomas Richardson">
#   <meta name="Data-Last-Modified" content="2001-04-09T22:15:50-0500">
#   <title>John Dutton, Son of Edmund Dutton</title>
#   <link rel="Stylesheet" type="text/css" href="../zdutton1.css">
#   <link rel="Up" title="Edmund Dutton" type="text/html" href="eddutton.html">
#   <link rel="Top" title="Zachariah Dutton" type="text/html" href="zdutton.html">
#   <link rel="Index" title="Full Name Index" type="text/html" href="../nameindex.html">
#   <link rel="Home" title="Home" type="text/html" href="../index.html">
#   <link rel="Contact" title="Contact Information" type="text/html" href="../contact.html">
#</head>

#* Generate a meta header from the passed metadata. See the @meta_headers
#* table above.
sub generate_meta_header {
    my $vars = shift;

    my $meta = "<head>\n";
    HEADER: foreach (@meta_headers) {
        my $header = "\t";
        my $type = $_->[0];

        #* Form each header based on its element type (e.g. meta, link, title).

        if ($type eq 'meta-http') {
            my ($name, $var) = @{$_}[1..2];
            next HEADER unless exists $vars->{$var};

            $header .= sprintf("<meta http-equiv=\"%s\" content=\"%s\">",
                $name, $vars->{$var});

            if (! defined $vars->{$var}) {
                warn "Variable $var not defined";
            }
        } elsif ($type eq 'meta') {
            my ($name, $var) = @{$_}[1..2];

            next HEADER unless exists $vars->{$var};
            $header .= sprintf("<meta name=\"%s\" content=\"%s\">",
                $name, $vars->{$var});
        } elsif ($type eq 'link') {
            my ($rel, $href, $title, $type) = @{$_}[1..4];
            next HEADER unless exists $vars->{$href};
            if (! defined $type) { $type = 'text/html'; }
            $header .= sprintf("<link rel=\"%s\"", $rel);
            if (defined $title) {
                $header .= sprintf(" title=\"%s\"", $vars->{$title});
            }
            $header .= sprintf(" type=\"%s\" href=\"%s\">",
                $type, $vars->{$href});
        } elsif ($type eq 'title') {
            my $title = $_->[1];
            if (! $title) {
                warn "No title";
                next HEADER;
            }
            $header .= sprintf("<title>%s</title>", $vars->{$title});
        } elsif ($type eq 'meta-script') {
            if (exists $vars->{'SCRIPTTYPE'}) {
                my ($name, $var) = @{$_}[1..2];
                $header .= sprintf("<meta http-equiv=\"%s\" content=\"%s\">",
                    $name, $vars->{$var});
            } else {
                next HEADER;
            }
        } elsif ($type eq 'script') {
            if (exists $vars->{'SCRIPT'}) {
                my @scripts = split(/,/, $vars->{'SCRIPT'});
                while (my $script = shift @scripts) {
                    $header .= sprintf("<script type=\"text/javascript\"" .
                        " src=\"%s\" charset=\"iso-8859-1\"></script>", $script);
                    $header .= "\n" if @scripts;
                }
            } else {
                next HEADER;
            }
        }
        $header .= "\n";
        $meta .= $header;
    }

    #* META contains any extra metadata that should be included.
    if (exists $vars->{'META'}) {
        $meta .= $vars->{'META'};
    }

    $meta .= "</head>\n";
    return $meta;
}

#* The page (nav) header should look like this:

# <!--Begin Page Header-->
# <div class="header">
# <a href="eddutton.html">[Up]</a>
# <a href="zdutton.html">[Top]</a>
# <a href="../nameindex.html">[Index]</a>
# <a href="../index.html">[Home]</a>
# <a href="../contact.html">[Contact]</a>
# <hr>
# </div>
# <!--End Page Header-->

#* Generate the page (nav) header.
sub generate_page_header {
    my $vars = shift;

    my $header = '';
    $header .= "<!--Begin Page Header-->\n<div class=\"header\">\n";
    foreach (@page_headers) {
        my ($name, $var) = @{$_};
        $header .= sprintf("<a href=\"%s\">[%s]</a>\n", $vars->{$var}, $name);
    }
    $header .= "</div>\n<hr>\n<!--End Page Header-->\n";
    return $header;
}

#* Generate the page footer.
sub generate_footer {
    my $vars = shift;
    my $footer = "<!--Begin Footer-->\n";
    $footer .= $footer_template;
    $footer =~ s/%%([\w]+)%%/$vars->{$1}/eg;
    $footer .= "\n<!--End Footer-->\n";
    return $footer;
}

#* Process file includes.
sub process_include {
    my $string = shift;
    my $include;
    my %attribs = $1 =~ m/\b(\w+)="([^\"]+)"/g;
    if (! exists $attribs{'name'}) {
        warn "Found include tag without name attribute.";
        return undef;
    }
    #* If it is a command to execute and include, do that.
    if (exists $attribs{'exec'}) {
        $include = `$attribs{'exec'}`;
    } elsif (exists $attribs{'file'}) {
        #* Else it's just a file to paste in.
        open (INCLUDE, "<$attribs{'file'}") || do {
            warn "Couldn't open include file $attribs{'file'}: $!";
            return undef;
        };
        local $/ = undef;
        $include = <INCLUDE>;
        close INCLUDE;
    }
    return undef unless defined $include;
    chomp $include;
    if ($show_include_tags) {
        if ($include =~ m/\n/) {
            $include = "<!--Begin Include $attribs{'name'}-->\n"
                . $include . "\n<!--End Include $attribs{'name'}-->";
        } else {
            $include = "<!--Begin Include $attribs{'name'}-->"
                . $include . "<!--End Include $attribs{'name'}-->";
        }
    }
    return $include;
}

#* This sub goes through the requested directory tree and picks out any
#* files that have been modified since the last generation. Only those
#* are run through run_queue(). Old files are left alone.
sub check_file_raw {
    # Make sure our path is unixized
    s!\\!/!g;

    if (-d) {  # If path is a directory
        # Check to see if directory should be ignored
        foreach my $ignore (@ignore_dirs) {
            if ($_ =~ $ignore) {
                print "Not descending into $_\n" if $show_ignore;
                return -1;  # Do no descend
            }
        }
        # Otherwise, don't add the directory entry to the queue.
        return 0;
    }

    my $st = stat($_);
    my $mtime = $st->mtime;  # Modification time
    # If not modified since the last run
    if (($mtime < $lastrun) && ! $force_all) {
        print "$_ has not changed.\n" if $show_unchanged;
        return;
    }

    m!(.*)/([^/]+)$!;
    my ($dir, $file) = ($1, $2);

    if ($file =~ m/\.html$/) {
        #print "$_\n";
        push(@queue, $_);
    }
}

#* This likewise picks out modified files, from the 'ready' directory trees.
#* Seems rather redundant.
sub check_file_ready {
    # Make sure our path is unixized
    s!\\!/!g;

    if (-d) {  # If path is a directory
        # Check to see if directory should be ignored
        foreach my $ignore (@ignore_dirs) {
            if ($_ =~ $ignore) {
                print "Not descending into $_\n" if $show_ignore;
                return -1;  # Do no descend
            }
        }
        # Otherwise, don't add the directory entry to the queue.
        return 0;
    }

    my $st = stat($_);
    my $mtime = $st->mtime;  # Modification time
    # If not modified since the last run
    if (($mtime < $lastrun) && ! $force_all && is_live($_)) {
        print "$_ has not changed.\n" if $show_unchanged;
        return;
    }

    push(@queue, $_);
}

#* Checks to see if a particular file exists in the live tree.
sub is_live {
    my $path = shift;

    my $working_root_q = quotemeta($working_root) . '\/';
    my $rel_path = $path;
    $rel_path =~ s!^$working_root_q!!;
    my $output_path = "$output_root/$rel_path";

    if (-e $output_path) {
        return 1;
    }
    return 0;
}

#* Checks to see if a file is part of the 'data' directory (i.e. family data).
sub is_data {
    if ($_[0] =~ m/^data\//) {
        return 1;
    }
}

#* Given a relative path, returns the relative path back to the document root.
sub path_to_root {
    my $relpath = shift;
    my ($vol, $directory, $file) = File::Spec->splitpath("$relpath");
    my $path_to_root = File::Spec->abs2rel("/", "/$directory");
    if ($path_to_root eq '/') { $path_to_root = "."; }
    return $path_to_root;
}

#* Returns the date as an ISO-compliant timestamp.
sub isodate {
    my $mtime = shift;
    my @ltime = localtime($mtime);
    my $isodate = Date::Format::Generic->strftime(
        "%Y-%m-%eT%X%z", [@ltime], $ltime[8] == 1 ? 'CDT' : 'CST');
    return $isodate;
}

#* Returns the date in the pretty format I liked.
sub sdate {
    my $mtime = shift;
    my $jtrdate = jtrtime($mtime);
    return $jtrdate;
}

#* Touch the files in the live directory to give them the same
#* modification times as the original raw files -- so the upload
#* script will be able to tell that they are new.
sub touch {
    my ($file, $touchtime) = @_;
    my $touch_obj = File::Touch->new(mtime => $touchtime, no_create => 1);
    $touch_obj->touch($file);
}

#* Get the last time this script was run from the config file.
sub get_config {
    my $config = shift;
    print "Reading config file...\n";

    # Does config file exist?
    if (! -e $config) {
        # If no config file, script has never been run,
        # so return "the beginning of time" (so all files are treated as new)
        return 0;
    }

    # Get the config file (containing the last run date)
    open (CONFIG, "<$config") ||
        die "Couldn't open config file to read settings: $!";
    my $lastrun = <CONFIG>;
    close CONFIG;
    chomp($lastrun);
    if (! $lastrun || $lastrun !~ /^\d+$/) { return 0; }
    return($lastrun);
}

#* Write the time at the end of this run, for get_config() next time.
sub write_config {
    # Write the time, to compare to the next time the script is run.
    my $config = shift;
    print "Writing config file...\n";
    open (CONFIG, ">$config") ||
        die "Couldn't open config file to write settings: $!";
    print CONFIG time;
    close CONFIG;
}
