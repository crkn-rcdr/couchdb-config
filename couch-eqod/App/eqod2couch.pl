#!/usr/bin/perl
# processes csv and posts to couch db


use 5.010;
use strict;
use warnings;

use utf8;
use JSON;
use Text::CSV;
use FindBin;
use lib "$FindBin::Bin/../lib";
use CouchDB;
use Data::Dumper;

foreach my $filename (@ARGV){
	my $csv = Text::CSV->new({binary=>1}) or die "Cannot use CSV: ".Text::CSV->error_diag();
	open my $fh, "<:encoding(utf8)", $filename or die "Can't open ".$filename."\n";
	my $header = $csv->getline ($fh);
	process($fh, $csv, $header);	
}
exit;

sub process{
	my($fh, $csv, $header) = @_;
	
	# Get reel information and add corresponding pages to each reel
	my $csv_data = [];
	while (my $row = $csv->getline($fh)) {
		print Dumper($row);
		my $reel = get_reel($csv_data, $row, $header);
		#print Dumper($row);
		die;
	}
	# Create json document for each reel, containing corresponding pages and tags
	my %page_data = ();
	foreach my $reel (keys(%csv_data)){	
		#json structure
		my $doc = {reel => $reel, tag_source => 'eqod', pages => []};
		
		# process each page
		%page_data = get_page($reel, $csv_data{$reel});
		foreach my $page (sort({$a <=> $b} keys(%page_data))){
			my $properties = [];
			my %types = ();
			get_properties ($properties, $page_data{$page});
			
			#combine properties under the same tag
			foreach my $prop(@$properties){	
				my $value = $prop->{'value'};
				my $type = $prop->{'type'};
				unless ($types{$type}){
					$types{$type} = [];
				}
				push ($types{$type}, $value);
			} 
			
			#remove duplicate values
			foreach my $tag (keys(%types)){
				foreach my $value ($types{$tag}){
					my $values = remove_duplicates_array($value);
					$types{$tag} = [keys(%$values)];					
				}
			}
		push ($doc->{pages}, {page => $page, tags => \%types});	
		}
	json_eqod ($reel, $doc);	
	}	
}
sub get_reel{
	my($csv_data, $row, $header) = @_;
	
	# Reel information can only be extracted from the url column (#24)
	my %cells;
	print Dumper($row);
	#next;
	#die;
	foreach my $property(@$header){
		warn $property;
		my $value = shift(@$row);
		warn $value;
		
		next unless ($value);
		unless ($cells{$property}){
			$cells {$property} = [];
		}
		push ($cells{$property}, $value);		
	}
		print Dumper(%cells);
	
	foreach my $tag(keys(%cells)){
		warn $tag;
		if ($tag eq "URLs" || $tag eq "URL"){
			my $value = shift ($cells{$tag});
			my ($url, $page) = $value =~ m{(.*/)([^?]*)}m;
			my $reel = substr $url, 34, 21;
			warn $reel;
			#return $reel;	
			next unless ($reel);
			unless ($csv_data {$reel}){	
				$csv_data {$reel} = [];
			}
			push (@$csv_data {$reel}, $row);	 
		}
	}
}
sub get_csv_data{
	my($page, $value) = @_;
				
	my %csv_data;
	if ($value){
		%csv_data = (
		        type => $page,
		        tags => $tags
		    );
	}
	return \%csv_data;
}
}
sub get_page{
	my ($reel, $pages) = @_;
	my %page_data = ();
	
	# Get page number and corresponding rows
	foreach my $page (@{$pages}){
		my ($url, $page_id) = @$page[24] =~ m{(.*/)([^?]*)}m; #page number is acquired from url column
		next unless ($page_id);
		unless ($page_data {$page_id}){
			$page_data {$page_id} = [];
		}		
		push ($page_data {$page_id}, $page);
	}
	return %page_data;
}
sub get_properties{
	my($properties, $page) = @_;
	
	# Eqod columns to Slim properties
	my %eqod2slim = (
		'Author' => 'tag:person',
		'Place' => 'tag:place',
        'Recipient' => 'tag:person',
        'Name' => 'tag:person',
        'Place' => 'tag:place',
        'Family Name' => 'tag:person',
        'Year1' => 'tag:date', 	#TODO: eventually will update these dates to represent an ISO range
        'Year2' => 'tag:date',
        'NoteBook' => 'tag', #Notebook is a potentially useful category for developing micro-collections - ways of organizing pages within reels (items)
        'Content/Comment' => 'tag', #tag is used as a catchall property for eqod, but these are not really tag categories and should be updated in later versions
	);
	
	foreach $page(@$page){
		# Extract properties for each page only if the row contains a valid url sequence (to match to a page)
		if (@$page[24] =~ m{(.*/)([^?]*)}m){
		
			if (@$page[1]){
				push (@$properties, add_eqod_property("tag:person", @$page[1])); #author
			}
			if (@$page[2]){
				push (@$properties, add_eqod_property("tag:person", @$page[2])); #recipient
			}
			if (@$page[3]){
				push (@$properties, add_eqod_property("tag:person", @$page[3])); #name
			}
			if (@$page[4]){	
				push (@$properties, add_eqod_property("tag:place", @$page[4])); #place
			}
			if (@$page[6]){	
				push (@$properties, add_eqod_property("tag:person", @$page[6])); #family name
			}
			
			if (@$page[8]){ #year1
				my $date = get_date(@$page[8], @$page[10], @$page[9]);	 #tag:date for year2
				push (@$properties, add_eqod_property("tag:date", $date));
			}
		
			if (@$page[11]){ #year2
				my $date = get_date(@$page[11], @$page[13], @$page[12]);	 #tag:date for year2
				push (@$properties, add_eqod_property("tag:date", $date));
			}

			if (@$page[22]){
				#my $notebook = lc(@$page->[22]);	
				push (@$properties, add_eqod_property("tag", @$page[22])); #notebook
			}
			if (@$page[23]){	
				push (@$properties, add_eqod_property("tag", @$page[23])); #content/comment
			}	
		}	
	}
}
sub get_date{
	my($y, $m, $d) = @_;
	my $date;
	
	# year values that start with 'circa' or 'after' - these will be handled as a single year
	if ($y =~ m{^[Cc]irca}m || $y =~ m{^[Aa]fter}m){
		$date = $y; #tag:date
	}
	
	# year values that contain question marks 
	elsif ($y =~ m{\?}m){
		$date = $y; #tag:date			
	}
	
	# year values that are regular format: yyyy
	elsif ($y =~ m{\d\d\d\d}m){
		$date = $y;
		#print $date;
		# if there is a month value create a date with yyyy-mm-dd 								
		if ($m){ #month2
			$m = get_month($m);
			$date = sprintf("%04d-%02d", $y, $m);	
		}
		if ($d){ #month2
			$date = sprintf("%04d-%02d-%02d", $y, $m, $d);	
		}
	}
	return $date;
}
sub get_month{
	my($month) = @_;
	
	#convert month to number
	my %mon2num = qw(
	jan 1  feb 2  mar 3  apr 4  may 5  jun 6
	jul 7  aug 8  sep 9  oct 10 nov 11 dec 12
	);	
	my $m = $mon2num{lc substr($month, 0, 3)};	
	return $m;
}
sub add_eqod_property{
	my($type, $value) = @_;
				
	my %property;
	if ($value){
		%property = (
		        type => $type,
		        value => $value
		    );
	}
	return \%property;
}
sub remove_duplicates_array{
	my($value) = @_;
	my %values = map {$_ => 1} @$value;
	return \%values;
}
sub json_eqod {
	my($reel, $data) = @_;
		
	my $json = JSON->new->utf8(1)->pretty(1)->encode($data);
	#say $json;
	my $db = CouchDB->new('127.0.0.1', '5984');
	my $attachment = $db->put("eqod/$reel/", $json);
	say $attachment;
	die;
}


