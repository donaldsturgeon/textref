#!/usr/bin/perl

#
# Command-line script to update data for all known endpoints
#
#

use TextRef::Setup;
use TextRef::Util;
use DBI();
use Encode();
use strict;
use utf8;


$dbh = dbiconnect()
  or die "Unable to connect to database: $dbh->errstr\n";

# Before trying to update/import data, check that our table definitions are correct

my $sthcheck = $dbh->prepare("SELECT * FROM catalogdef LIMIT 1");
if(!$sthcheck->execute()) {
  $dbh->do("DROP TABLE catalogdef");
  my $sql = "CREATE TABLE `catalogdef` (`endpointid` int(11) NOT NULL, `created` datetime NOT NULL, `updated` datetime NOT NULL, `dataurl` text, `resourcetemplate` text, `shortname` varchar(30) DEFAULT NULL, `longname` text, `metaurl` text)";
  $dbh->do($sql) or die $dbh->errstr;
}


# If anything has changed in Setup.pm or if the data table does not exist, replace it with a new table first
# We only do this if the catalog table does not contain required fields (i.e. we do not try to 'shrink' it)

my %sqltypes = ('text' => "VARCHAR(255)", bool => "TINYINT");
my $sqlfields = "endpointid"; # This is fundamental to the system and should not be removed
my $sqlcreatefields = "endpointid INTEGER NOT NULL"; #"primary_id " . $sqltypes{'text'};


for my $field (@datafields) {
  $sqlfields .= "," . $field->{'name'};
  if($sqlcreatefields) {
    $sqlcreatefields .= ",";
  }
  $sqlcreatefields .= $field->{'name'} . " " . $sqltypes{$field->{'type'}};
}
my $sthcheck = $dbh->prepare("SELECT $sqlfields FROM catalog LIMIT 1");
if(!$sthcheck->execute()) {
  $dbh->do("DROP TABLE catalog");
  my $sql = "CREATE TABLE catalog ($sqlcreatefields)";
  print $sql;
  $dbh->do($sql) or die $dbh->errstr;
}

my @urls = knownendpoints();

foreach my $url (@urls) {
  print "Fetching $url...\n";
  updatecatalogdef($url);
}


