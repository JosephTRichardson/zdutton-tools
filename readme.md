# ZDutton Tools
An HTML preprocessor, automatic upload script, and other Perl goodies from my old website.

## Overview

This repository is a collection of Perl tools I wrote years ago
(ca. 1999–2006) in service of my old genealogy website,
the [Zachariah Dutton Genealogy Web](http://www.zdutton.org).

They included:

Tool                | Description
--------------------|---------------------------------------------------
`generate.pl`       | An HTML preprocessor that read my "raw" HTML files and generated more-or-less dynamic headers and footers for them based on metadata, substituted variables, and handled file includes.
`get_news.pl`       | Read recent site news data from a file and formatted them for inclusion by the generate script.
`merge.pl`          | Merged files from disparate directory trees together in one structure in preparation for upload.
`zd_upload.pl`      | An upload script that scanned for files modified since the last upload and uploaded them via FTP.
`make_indices.pl`   | An indexer that read tagged names from genealogical data files and generated a full name index.
`make_changelog.pl` | Generated a changelog (in HTML and XML/RSS) based on the CVS commit log and messages.
`make_sitemap.pl`   | Generated an XML sitemap in the Google Sitemaps 0.84 schema.
`cvs_status.pl`     | Read the output from the `cvs status` command and reported briefly on modified files.

I am annotating these scripts for explanatory purposes, but altering
the historical code as little as possible. These are museum pieces.
I share them here not because they are anything particularly special
or useful (though it is my hope that they will help someone),
but because my brother thought it was kind of cool that a self-taught
twenty-year-old did all of this for no other reason than his own
enjoyment and annoyance at repetitive tasks.

I will be uploading these a few at a time, as I have time to annotate them.

## License

I release these scripts and this code under the [MIT License] (http://opensource.org/licenses/MIT).
This means you are free to use, copy, edit, modify, reuse, redistribute,
incorporate all or part into your own project, or do pretty much anything
else you'd like with this code and software, provided you keep intact the
attribution to me and this license information.

Copyright 1999–2014, Joseph T. Richardson (LonelyPilgrim @ GitHub).
