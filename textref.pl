#!/usr/bin/perl

#
# Web-based user interface to selected datasets
#

use CGI('param','cookie');
use CGI::Carp qw(fatalsToBrowser);
use TextRef::Setup;
use TextRef::Util;
use DBI();
use Encode();
use strict;
use utf8;



open my $fh, '<', $templatefile or die;
$/ = undef;
my $html = Encode::decode('utf8', <$fh>);
close $fh;


$dbh = dbiconnect()
  or die "Unable to connect to database: $DBI::errstr\n";

my $content = "";
my $footer = "";
my $pagetitle = "TextRef catalog";
my $cookies = "";

my @endpoints = @defaultendpoints;
# Add any endpoints set as cookies
my $ncookie = 1;
while(defined cookie('endpoint' . $ncookie)) {
  addendpoint(cookie('endpoint' . $ncookie));
  $ncookie++;
}


# We will need endpoint metadata to do anything useful
my %meta = ();
my %endpointbyid = ();

loadmeta();

if(param('method') eq "browse") {
  $content = browse();
}

if(param('method') eq "search") {
  # Show search dialog

  my $searchform = "<div id=\"searchbox\"><form action=\"textref.pl\" method=\"get\"><input type=\"hidden\" name=\"method\" value=\"search\" /><table>";
  my %searchspec = ();
  my $searches = 0;
    foreach my $field (@datafields) {
      if($field->{'searchable'}) {
        if($field->{'type'} eq 'text') {
          $searchform .= "<tr><th>" . $field->{'title'} . "</th><td><input type=\"text\" value=\"" . escapequotes(Encode::decode('utf8', param($field->{'name'}))) . "\" name=\"" . $field->{'name'} . "\" /></td></tr>";
        } else {
        }
        if(param($field->{'name'})) {
          $searches++;
        }
        if(param($field->{'name'})) {
          $searchspec{$field->{'name'}} = escapequotes(Encode::decode('utf8', param($field->{'name'})));
        }
      }
    }
  if(param('page')) {
    $searchspec{'page'} = param('page');
  }
  $searchform .= "</table><input type=\"submit\" value=\"Search\" /></form></div>";

  if($searches) {
    $content .= browse(fields => \%searchspec);
  }

  $content .= $searchform;
}

if(param('method') eq "import") {
  if(param('endpoint')) {
    my $endpoint = param('endpoint');
    # Add an endpoint to this user's list
    # If we haven't seen this endpoint before, we will need to import it
    my $url = param('endpoint');
    my ($error, $errdesc) = (undef, undef);
    if(!$meta{$url}) {
      ($error, $errdesc) = updatecatalogdef($url);
    }

    if($error) {
      $content .= "<div class=\"errorbox\">$errdesc</div>";
    } else {
      # Set a cookie to enable the endpoint for this user
      my $ncookie = 1;
      while(defined cookie('endpoint' . $ncookie)) {
        $ncookie++;
      }
      $cookies .= "\nSet-cookie: endpoint$ncookie=$endpoint";
      addendpoint($endpoint);
      loadmeta();
    }
  }

  $content .= "<p>To import new data into the TextRef system, you first need to <a href=\"https://textref.org/data-model.html\">create and publish your dataset</a>.</p>";
  $content .= "<p>Once your dataset is available online in a supported format, you can add it to the TextRef catalog by entering your metadata URL in the box below:</p>";
  $content .= "<div id=\"importbox\"><form action=\"textref.pl\" method=\"post\"><input type=\"hidden\" name=\"method\" value=\"import\" />";

  $content .= "URL of metadata file: <input type=\"text\" name=\"endpoint\" style=\"width: 300px;\" />";
  $content .= "<input type=\"submit\" value=\"Import\" /></form></div>";

  # Show information about all enabled catalogs
  $content .= "<h3>Currently enabled catalogs</h3>";
  $content .= "<table class=\"resultset\"><tr><th>Short name</th><th>Full name</th><th>Metadata URL</th><th>Data URL</th><th>Last updated</th></tr>";
  foreach my $metaurl (@endpoints) {
    my $data = $meta{$metaurl};
    if($data) {
      $content .= "<tr><td><a href=\"textref.pl?method=browse&amp;\">$data->{'shortname'}</a></td><td>$data->{'longname'}</td><td><a href=\"$metaurl\">$metaurl</a></td><td><a href=\"$data->{'dataurl'}\">$data->{'dataurl'}</a></td><td>$data->{'updated'}</td></tr>";
    }
  }



}

$html =~ s/{pagecontent}/$content/;
$html =~ s/{footer}/$footer/;
$html =~ s/{pagetitle}/$pagetitle/;

print "Content-type: text/html; charset=utf-8$cookies\n\n";
print $html;


#
# 1. Nothing supplied => list default+user endpoints (or "all")
# 2. Endpoint supplied => list all texts in that endpoint
#
sub browse
{
  my %request = @_;

  my ($datarows, $total) = fetchdata(%request);

  my $fragment = "<table class=\"resultset\">";
  my @columnstoshow = qw(title author edition);
  $fragment .=  "<tr><th>Location</th>";
  foreach my $col (@columnstoshow) {
    $fragment .=  "<th>" . fieldbyname($col)->{'title'} . "</th>";
  }
  $fragment .=  "</tr>";

  for(my $i=0;$i<@{$datarows};$i++) {
    my $resourceurl = "";
    if($meta{$endpointbyid{$datarows->[$i]->{'endpointid'}}}->{'resourcetemplate'}) {
      my $template = $meta{$endpointbyid{$datarows->[$i]->{'endpointid'}}}->{'resourcetemplate'};
      $template =~ s/{primary_id}/$datarows->[$i]->{'primary_id'}/g;
      $resourceurl = " <a href=\"$template\" target=\"_blank\"><img src=\"static/link.png\" border=\"0\" title=\"Open this text online\" /></a>";
    }
    $fragment .= "<tr><td>" . $meta{$endpointbyid{$datarows->[$i]->{'endpointid'}}}->{'shortname'} . "$resourceurl</td>";
    foreach my $col (@columnstoshow) {
      my $url = "textref.pl?method=search&amp;" . $col . "=" . $datarows->[$i]->{$col};
      if($col eq 'title') {
      }
      $fragment .=  "<td><a href=\"$url\">" . $datarows->[$i]->{$col} . "</a></td>";
    }
    $fragment .=  "</tr>";
  }
  $fragment .=  "</table>";

  my $pagestotal = int(($total+$resultsperpage-1)/$resultsperpage);
  my $pagedesc = "";
  my $thispage = $request{'fields'}->{'page'};
  if(!$thispage) {
    $thispage = 1;
  }
  my $ss = "";
  foreach my $p (keys %{$request{'fields'}}) {
    $ss .= "&amp;" . $p . "=" . $request{'fields'}->{$p};
  }
  if($pagestotal>1) {
    if($pagestotal > $thispage) {
      $pagedesc .= "<a href=\"textref.pl?method=" . param('method') . "&amp;page=" . ($thispage+1) . "$ss\">Next</a> ";
    }
  }

  $fragment .= "<p>Total: $total ($pagedesc)</p>";
  return $fragment;
}

sub escapequotes
{
  my ($str) = @_;
  $str =~ s/"/&quot;/g;
  return $str;
}

sub fieldbyname
{
  my ($name) = @_;
  foreach my $field (@datafields) {
    if($field->{'name'} eq $name) {
      return $field;
    }
  }
  return undef;
}

#
# Return a result set as an array of hashes with all available data
#
sub fetchdata
{
  my %request = @_;

  my $page = 1;
  my $resultfrom = 0;
  if($request{'fields'}->{'page'}) {
    $page = $request{'fields'}->{'page'};
    $resultfrom = $page*$resultsperpage;
  }
  my $limit = "$resultfrom,$resultsperpage";
  my $order = "title, author";

  # Restrict results to enabled catalogs
  my $ids = "";
  foreach my $endpoint (@endpoints) {
    if($meta{$endpoint}->{'endpointid'}) {
      if($ids) {
        $ids .= ",";
      }
      $ids .= $meta{$endpoint}->{'endpointid'};
    }
  }
  my $where = "endpointid IN ($ids)";


  my @sqlparams = ();

  my $allfields = "endpointid";
  foreach my $field (@datafields) {
    $allfields .= "," . $field->{'name'};
  }

  if($request{'fields'}) {
    # Since fields are user-specified data, we can't include them in the SQL directly; instead, check 
    foreach my $field (@datafields) {
      if($request{'fields'}->{$field->{'name'}}) {
        if($field->{'type'} eq 'text') {
          $where .= " AND $field->{'name'} LIKE BINARY ?";
          push @sqlparams, Encode::encode('utf8', "%" . $request{'fields'}->{$field->{'name'}} . "%");
        } else {
          $where .= " AND $field->{'name'}=?";
          push @sqlparams, Encode::encode('utf8', $request{'fields'}->{$field->{'name'}});
        }
      }
    }
  }
  my $sql = "SELECT $allfields FROM catalog WHERE $where ORDER BY $order LIMIT $limit";

  my $sthlist = $dbh->prepare($sql);
  $sthlist->execute(@sqlparams) or die $dbh->errstr;

  my @results = ();

  while(my $row=$sthlist->fetchrow_arrayref) {
    my %data = ();
    my $i=0;
    $data{'endpointid'} = $row->[0];
    foreach my $field (@datafields) {
      $data{$field->{'name'}} = Encode::decode('utf8', $row->[$i+1]);
      $i++;
    }
    push @results, \%data;
  }

  my $sql = "SELECT COUNT(*) FROM catalog WHERE $where";
  my $sthcount = $dbh->prepare($sql);
  $sthcount->execute(@sqlparams) or die $dbh->errstr;
  my $rowcount = $sthcount->fetchrow_arrayref;


  return (\@results, $rowcount->[0]);
}

sub addendpoint
{
  my ($new) = @_;
  for my $existing (@endpoints) {
    if($existing eq $new) {
      return;
    }
  }
  push @endpoints, $new;
}


sub loadmeta
{
  my $sth = $dbh->prepare("SELECT endpointid, created, updated, dataurl, resourcetemplate, shortname, longname, metaurl FROM catalogdef");
  $sth->execute() or die $dbh->errstr;
  while(my $row = $sth->fetchrow_arrayref) {
    $meta{$row->[7]} = {endpointid => $row->[0], created => $row->[1], updated => $row->[2], dataurl => $row->[3], resourcetemplate => $row->[4], shortname => Encode::decode('utf8', $row->[5]), longname => Encode::decode('utf8', $row->[6])};
    $endpointbyid{$row->[0]} = $row->[7];
  }
}
