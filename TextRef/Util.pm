#!/usr/bin/perl

package TextRef::Util;
use utf8;
use strict;
use TextRef::Setup;
use LWP();
use HTTP::Request();
use Text::CSV();
use Digest::MD5();

use DBI();
use Exporter;

our @ISA = qw(Exporter);
our @EXPORT = qw(knownendpoints updatecatalogdef @datafields);
our @EXPORT_OK = @EXPORT;


#
# Lists every registered endpoint known to the system - i.e. *all* data sets we wish to keep track of
#
sub knownendpoints
{
  my $sth = $dbh->prepare("SELECT DISTINCTROW metaurl FROM catalogdef");
  $sth->execute();
  my @list = ();
  while(my $row = $sth->fetchrow_arrayref) {
    push @list, $row->[0];
  }

  # Add the default ones if they are not present
  foreach my $url (@defaultendpoints) {
    my $exists = 0;
    foreach my $existing (@list) {
      if($url eq $existing) {
        $exists = 1;
        last;
      }
    }
    if(!$exists) {
      push @list, $url;
    }
  }
  return @list;
}

#
# Create or update catalog definition data for a particular catalog
# URL must specify location of a CSV file defining a catalog
# This will also request the CSV file containing the data for that catalog
#
sub updatecatalogdef
{
  my ($url) = @_;
  my $ua = LWP::UserAgent->new(agent => "TextRef Update Check");

  my $res = $ua->get($url);
  if(!$res->is_success) {
    return (1, "Error fetching '$url'.");
  }
  my $raw = Encode::decode('utf8', $res->content);

  my @storefields = qw(dataurl resourcetemplate shortname longname metaurl);
  my %data = ();

  # If there is a BOM present, delete it
  $raw =~ s/^\x{FEFF}//;

  my $csv = Text::CSV->new({ sep_char => ',', allow_whitespace => 1, quote_char => '"', 'allow_loose_quotes' => 1, binary => 1 });
  my @lines = split(/[\n\r]+/, $raw);

  if(!$csv->parse($lines[0])) {
    return (1, "Error parsing metadata file header");
  }
  foreach my $line (@lines) {
    if($csv->parse($line)) {
      my @fields = $csv->fields();
      if(@fields >= 2) {
        $data{lc($fields[0])} = $fields[1];
      }
    }
  }
  # Sanity check that we have a valid metadata file
  my @requirefields = qw(ShortName LongName DataURL MetaURL);
  for my $field (@requirefields) {
    if(!$data{lc($field)}) {
      return (1, "Missing '" . $field . "' field in metadata file");
    }
  }

  my $endpointid = undef;

  my $sthcheck = $dbh->prepare("SELECT endpointid, datahash FROM catalogdef WHERE metaurl=?");
  $sthcheck->execute($url) or die $dbh->errstr;
  my $rowcheck = $sthcheck->fetchrow_arrayref;
  my $lastdatahash = undef;
  if($rowcheck->[0]) {
    $endpointid = $rowcheck->[0];
    $lastdatahash = $rowcheck->[1];
  } else {
    my $sthexists = $dbh->prepare("SELECT endpointid FROM catalogdef WHERE endpointid=?");
    while(!defined $endpointid) {
      my $candidate = int(rand(100000))+1;
      $sthexists->execute($candidate) or die $dbh->errstr;
      my $rowexists = $sthexists->fetchrow_arrayref;
      if(!$rowexists->[0]) {
        $endpointid = $candidate;
      }
    }
  }

  # INSERT blank row if no record with same metaurl
  my $sth = $dbh->prepare("SELECT metaurl FROM catalogdef WHERE metaurl=?");
  $sth->execute($url) or die $dbh->errstr;
  my $row = $sth->fetchrow_arrayref;
  if(!$row) {
    my $sth = $dbh->prepare("INSERT INTO catalogdef (metaurl) VALUES (?)");
    $sth->execute($url) or die $dbh->errstr;
  }

  my $sql = "UPDATE catalogdef SET endpointid=?, ";
  my @utfdata = ($endpointid);
  foreach my $field (@storefields) {
    $field = lc($field);
    $sql .= "$field=?, ";
    push @utfdata, Encode::encode('utf8', $data{$field});
#    print "$field => $data{$field}\n";
  }
  $sql .= " updated=NOW() WHERE metaurl=?";

  my $sth = $dbh->prepare($sql);
  $sth->execute(@utfdata, $url) or die $dbh->errstr;


  # Fetch and update data
  my $dataurl = $data{"dataurl"};
  if(!$dataurl) {
    return (1, "No DataURL specified");
  }
  my $res = $ua->get($dataurl);
  if(!$res->is_success) {
    return (1, "Error fetching '$url'.");
  }

  my $datahash = Digest::MD5::md5_hex($res->content);
  if(defined $lastdatahash && $lastdatahash eq $datahash) {
    return (0, "OK - catalog data has not changed.");
  }

  my $raw = Encode::decode('utf8', $res->content);


  my %data = (); # One row of data only
  my %storefield = {};

  for(my $i=0;$i<@datafields;$i++) {
    $storefield{$datafields[$i]->{'name'}} = $i;
  }

  # If there is a BOM present, delete it
  $raw =~ s/^\x{FEFF}//;

  my $csv = Text::CSV->new({ sep_char => ',' }, binary => 1);
  my @lines = split(/[\n\r]+/, $raw);

#  print "Read " . scalar(@lines) . " data rows\n";

  # Work out which columns belong to which fields
  if(!$csv->parse($lines[0])) {
    return (1, "Error parsing data file header");
  }
  my $sqlfields = "endpointid";
  my $sqlvalues = "?";

  my @filecolumns = $csv->fields();
  my @columnbyfield = ();
  for(my $i=0;$i<@filecolumns;$i++) {
    my $filecol = lc($filecolumns[$i]);
#print "$filecol\n";
    if(defined $storefield{$filecol}) {
      $columnbyfield[$i] = $filecol;
#      print "Column $i: $filecol\n";
      if($sqlfields) {
        $sqlfields .= ",";
        $sqlvalues .= ",";
      }
      $sqlfields .= $filecol;
      $sqlvalues .= "?";
    }
  }
  if($sqlfields eq "endpointid") {
    return (1, "Data file header does not contain any recognized columns");
  }

  # Having come this far, we delete all previous data for this endpointid
  my $sqldelete = $dbh->prepare("DELETE FROM catalog WHERE endpointid=?");
  $sqldelete->execute($endpointid) or die $dbh->errstr;


  my $sqlinsert = "INSERT INTO catalog ($sqlfields) VALUES ($sqlvalues)";

  my $sthinsert = $dbh->prepare($sqlinsert) or die $dbh->errstr;

  for(my $l=1;$l<@lines;$l++) {
    my $line = $lines[$l];

    if($csv->parse($line)) {
      my @fields = $csv->fields();
      my $i;

      my @sqldata = ();
      for($i=0;$i<@columnbyfield;$i++) {
        if($columnbyfield[$i]) {
#          print "$columnbyfield[$i] => $fields[$i] => $storefield{$columnbyfield[$i]}\n";
          if($datafields[$storefield{$columnbyfield[$i]}]->{'type'} eq 'bool') {
            if(lc(substr($fields[$i],0,1)) eq 'y') {
              $fields[$i] = 1;
            } elsif(lc(substr($fields[$i],0,1)) eq 'n') {
              $fields[$i] = 0;
            } else {
              $fields[$i] = undef;
            }
          }
          push @sqldata, $fields[$i];
        } else {
#          print "Skipping $fields[$i]\n";
        }
      }
      $sthinsert->execute($endpointid, @sqldata) or die $dbh->errstr;
      
    } else {
      #die $csv->error_input ();
    }
  }

  # Update the catalog data hash
  my $sthupdate = $dbh->prepare("UPDATE catalogdef SET datahash=? WHERE endpointid=?");
  $sthupdate->execute($datahash, $endpointid) or die $dbh->errstr;

  return (0, "OK");
}



1;

