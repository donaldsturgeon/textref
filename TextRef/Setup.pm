#!/usr/bin/perl

package TextRef::Setup;
use utf8;
use strict;

use DBI();
use Exporter;

our @ISA = qw(Exporter);
our @EXPORT = qw($dbh dbiconnect @datafields $templatefile @defaultendpoints $resultsperpage);
our @EXPORT_OK = @EXPORT;

our @datafields = (
  ['primary_id', 'text'],
  ['title', 'text'],
  ['author', 'text'],
  ['edition', 'text'],
  ['fulltext_read', 'bool'],
  ['fulltext_search', 'bool'],
  ['fulltext_download', 'bool'],
  ['image', 'bool'],
);

our @datafields = (
  {
    name => 'primary_id',
    type => 'text',
    required => 1
  },
  {
    name => 'secondary_id',
    type => 'text'
  },
  {
    name => 'title',
    type => 'text',
    title => 'Title',
    required => 1,
    searchable => 1,
  },
  {
    name => 'author',
    type => 'text',
    title => 'Author',
    searchable => 1,
  },
  {
    name => 'edition',
    type => 'text',
    title => 'Edition',
    searchable => 1,
  },
  {
    name => 'fulltext_read',
    type => 'bool',
    icon => '<img src="static/icon-read-small.png" title="Full-text view" width="12px" />',
  },
  {
    name => 'fulltext_search',
    type => 'bool',
    icon => '<img src="static/icon-search-small.png" title="Full-text search" width="12px" />',
  },
  {
    name => 'fulltext_download',
    type => 'bool',
    icon => '<img src="static/icon-download-small.png" title="Full-text download" width="12px" />',
  },
  {
    name => 'image',
    type => 'bool',
    icon => '<img src="static/icon-image-small.png" title="Scanned image view" width="12px" />',
  }
);

our $templatefile = "textreftemplate.html";

our @defaultendpoints = qw(http://ctext.org/static/textrefmeta.csv);

our $resultsperpage = 25;

our $dbh = undef;

sub dbiconnect {
  $dbh = DBI->connect("DBI:mysql:database=database_name","database_user","database_password", {'RaiseError' => 0, 'PrintError' => 0, 'AutoCommit' => 1});
}

1;

