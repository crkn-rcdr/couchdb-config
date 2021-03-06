#!/usr/bin/env perl
use strict;
use warnings;
use Carp;

use lib "/opt/c7a-perl/current/cmd/local/lib/perl5";
use FindBin;
use lib "$FindBin::RealBin/../lib";

use Getopt::Long;
use JSON;
use CIHM::TDR::TDRConfig;
use CIHM::TDR::REST::wipmeta;

##
## Modify this structure as new parts of design document authored.
##
my $design= {
    filters => {},
    lists => {},
    shows => {},
    updates => {
        basic => readjs("$FindBin::RealBin/design/updates/basic.js"),
	filesystem => readjs("$FindBin::RealBin/design/updates/filesystem.js"),
    },
    views => {
        buildsips => {
            map => readjs("$FindBin::RealBin/design/views/buildsips.map.js"),
            reduce => "_count",
        },
        configs => {
            map => readjs("$FindBin::RealBin/design/views/configs.map.js"),
            reduce => "_count",
        },
        exportq => {
            map => readjs("$FindBin::RealBin/design/views/exportq.map.js"),
            reduce => "_count",
        },
        exports => {
            map => readjs("$FindBin::RealBin/design/views/exports.map.js"),
            reduce => "_count",
        },
        exporting => {
            map => readjs("$FindBin::RealBin/design/views/exporting.map.js"),
            reduce => "_count",
        },
        hasmets => {
            map => readjs("$FindBin::RealBin/design/views/hasmets.map.js"),
            reduce => "_count",
        },
        hasmetsfs => {
            map => readjs("$FindBin::RealBin/design/views/hasmetsfs.map.js"),
            reduce => "_count",
        },
        ingestq => {
            map => readjs("$FindBin::RealBin/design/views/ingestq.map.js"),
            reduce => "_count",
        },
        ingests => {
            map => readjs("$FindBin::RealBin/design/views/ingests.map.js"),
            reduce => "_count",
        },
        imageconvq => {
            map => readjs("$FindBin::RealBin/design/views/imageconvq.map.js"),
            reduce => "_count",
        },
        imageconvs => {
            map => readjs("$FindBin::RealBin/design/views/imageconvs.map.js"),
            reduce => "_count",
        },
        malletq => {
            map => readjs("$FindBin::RealBin/design/views/malletq.map.js"),
            reduce => "_count",
        },
        manipmds => {
            map => readjs("$FindBin::RealBin/design/views/manipmds.map.js"),
            reduce => "_count",
        },
        olddoc => {
            map => readjs("$FindBin::RealBin/design/views/olddoc.map.js"),
            reduce => "_count",
        },
        processing => {
            map => readjs("$FindBin::RealBin/design/views/processing.map.js"),
            reduce => "_count",
        },
        processs => {
            map => readjs("$FindBin::RealBin/design/views/processs.map.js"),
            reduce => "_count",
        },
        filesystem => {
            map => readjs("$FindBin::RealBin/design/views/filesystem.map.js"),
            reduce => "_count",
        },
        manifestdate => {
            map => readjs("$FindBin::RealBin/design/views/manifestdate.map.js"),
            reduce => "_count",
        },
        repocount => {
            map => readjs("$FindBin::RealBin/design/views/repocount.map.js"),
            reduce => "_count",
        },
        sipvalidateq => {
            map => readjs("$FindBin::RealBin/design/views/sipvalidateq.map.js"),
            reduce => "_count",
        },
        wipmvq => {
            map => readjs("$FindBin::RealBin/design/views/wipmvq.map.js"),
            reduce => "_count",
        }
    }
};

## Everything else should just work without being fiddled with.

my $conf = "/etc/canadiana/tdr/tdr.conf";
my $post;

GetOptions (
    'conf:s' => \$conf,
    'post' => \$post,
    );

my $config = CIHM::TDR::TDRConfig->instance($conf);
croak "Can't parse $conf\n" if (!$config);

my %confighash = %{$config->get_conf};

my $wipmeta;
# Undefined if no <wipmeta> config block
if (exists $confighash{wipmeta}) {
    $wipmeta = new CIHM::TDR::REST::wipmeta (
        server => $confighash{wipmeta}{server},
        database => $confighash{wipmeta}{database},
        type   => 'application/json',
        conf   => $conf,
        clientattrs => {timeout => 3600}
        );
} else {
    croak "Missing <wipmeta> configuration block in config\n";
}



if($post) {
    my $revision;
    my $designdoc = "_design/tdr";
    $design->{"_id"}=$designdoc;

    my $res = $wipmeta->head("/".$wipmeta->database."/$designdoc",
                                    {},{deserializer => 'application/json'});
    if ($res->code == 200) {
        $revision=$res->response->header("etag");
        $revision =~ s/^\"|\"$//g;
        $design->{'_rev'} = $revision;
    }
    elsif ($res->code != 404) {
        croak "HEAD of $designdoc return code: ".$res->code."\n"; 
    }
    $res = $wipmeta->put("/".$wipmeta->database."/$designdoc",
                                $design, {deserializer => 'application/json'});
    if ($res->code != 201) {
        croak "PUT of $designdoc return code: ".$res->code."\n"; 
}
} else {
    print "with --post would post:\n" .
        to_json( $design, { ascii => 1, pretty => 1 } ) . "\n";
}


sub readjs {
    my $filename = shift(@_);
    open FILE, $filename or die "Couldn't open $filename: $!"; 
    my $jsstring = join("", <FILE>); 
    close FILE;
    return $jsstring;
}
