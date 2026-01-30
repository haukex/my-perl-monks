#!/usr/bin/env perl
use warnings;
use 5.014;
use Graph;
use URI ();
use FindBin;
use XML::LibXML ();
use Data::Dump qw/dd pp/;
use lib $FindBin::Bin;
use MyConfig qw/ $XML_PATH $OUT_PATH /;
use PmNode;

my %files;
my $graph = Graph->new(directed=>1);

# Build list of all files and links
for my $c ($OUT_PATH->children) {
	die $c if !$c->is_file || $c->basename!~/\.(?:html|css)\z/;
	next unless $c->basename =~ /\.html\z/i;
	$files{$c->basename}++;
	# don't need to check links in files that we scraped as HTML, because they use <base href=
	if ( my ($ld) = $c->basename =~ /\A[0-9]*([0-9])\.html\z/i )
		{ next if $XML_PATH->child($ld)->child($c->basename)->exists }
	my $doc = XML::LibXML->load_html(location=>$c, recover => 1, suppress_errors => 1);
	for my $lnk ($doc->findnodes('//a[@href]')) {
		my $u = URI->new($lnk->getAttribute('href'));
		if (!$u->scheme) {
			if ($u->opaque) {
				$graph->add_edge($c->basename, $u->path);
			}
			else { die $u unless $u->fragment }
		}
	}
}

# Check for connectedness in the underlying undirected graph ("undirected-connected") (i.e. orphans)
die pp($graph->weakly_connected_components) unless $graph->is_weakly_connected;

my $warn_count;
local $SIG{__WARN__} = sub { $warn_count++; warn shift };

# check that all nodes that should exist do
for my $id (PmNode->list_nodes) {
	my $node = PmNode->load_by_id($id);
	if (defined $node->dest) {
		my $u = URI->new($node->dest);
		die $u if $u->scheme || !$u->opaque;
		warn "File should exist but doesn't: ".$u->path."\n" unless $files{$u->path};
	}
}

# check links
for my $e ($graph->edges) {
	die pp($e) unless @$e==2;
	my ($from, $dest) = @$e;
	warn "$from links to $dest but that doesn't exist\n" unless $files{$dest};
}

die "There were $warn_count warnings.\n" if $warn_count;

# spell: ignore findnodes