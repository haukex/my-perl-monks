#!/usr/bin/env perl
use warnings;
use 5.014;
use CHI ();
use URI ();
use FindBin;
use List::Util qw/min/;
use Path::Tiny qw/path/;
use Data::Dump qw/dd pp/;
use File::Temp qw/tempdir/;
use XML::LibXML qw/:libxml/;
use HTTP::CookieJar::LWP ();
use WWW::Mechanize::Cached ();
use HTML::TableContentParser ();
use IO::Prompt::Tiny qw/prompt/;
use Term::ReadPassword::Win32 qw/read_password/;  # works under *NIX too!
use lib $FindBin::Bin;
use MyConfig qw/ $BASE_URL $XML_PATH $CACHE_PATH $PATCH_PATH %ALSO /;
use Common qw/ validate_id /;
use PmNode;

my $VERBOSE = 0;

# WWW::Mechanize variables
my $jar = HTTP::CookieJar::LWP->new;
my $CACHE = CHI->new( driver => 'File', root_dir => $CACHE_PATH->stringify );
my $mech = WWW::Mechanize::Cached->new(
	cache => $CACHE,
	autocheck => 1,
	strict_forms => 1,
	protocols_allowed => [ 'https' ],
	agent => 'scraping my own nodes',
	cookie_jar => $jar );

# Helper function to fetch PM nodes
sub mech_get_pm {
	my @query = @_;
	die "need an odd number of args" unless @query%2;
	my $url = URI->new($BASE_URL);
	# `ticker`: Stay out of "Other Users" as per https://perlmonks.org/?node_id=72241
	# Use array ref here for predictable URL for caching!
	$url->query_form([ ticker => 'yes', node_id => @query ], ';');
	# Simple rate limiting: If the server is currently slow, then delay the next request
	# for the same amount of time that the previous request took. This means that cached
	# requests are still fast, while respecting times when the server is under load.
	state $next_sleep = 0;
	print $next_sleep."s  ".$url if $VERBOSE;
	STDOUT->flush;
	sleep $next_sleep if $next_sleep>0;
	my $start = time;
	$mech->get($url);
	$next_sleep = time-$start;
	say "  ".$next_sleep."s" if $VERBOSE;
}

# Log in
my $COOKIE_KEY = 'LWP-Cookies';
if (defined( my $cookie_data = $CACHE->get($COOKIE_KEY) )) {
	say "Using cached cookie data";
	$jar->load_cookies($cookie_data);
} else {
	say "No cookies cached, logging in...";
	mech_get_pm(109);  # Login
	$mech->submit_form(
		form_name => 'login',  # this is actually the login nodelet but whatever
		fields => {
			user => scalar prompt('PerlMonks Username:'),
			passwd => scalar read_password('PerlMonks Password:  '),
			expires => '+10y',  # <input type="checkbox" name="expires" value="+10y" />
		} );
	$CACHE->set($COOKIE_KEY, join "\n", $jar->dump_cookies);
	say "Logged in and cookies cached";
}

# Figure out user's ID
my $user_id;
my $USER_ID_KEY = 'PM-User-ID';
if (defined( $user_id = $CACHE->get($USER_ID_KEY) )) {
	say "Using cached user ID";
} else {
	# There's probably a better way than this to get the user ID, but this works...
	# (could save username from prompt above and visit `?node=$username`?)
	say "Figuring out user ID...";
	mech_get_pm(1072);  # User Settings
	$user_id = validate_id(
		URI->new($mech->find_link(text=>'your homenode')->url)->query_param('node_id') );
	$CACHE->set($USER_ID_KEY, $user_id);
}
validate_id($user_id, 'user');
say "User ID $user_id";

# Retrieve a list of the user's nodes
my $NODE_IDS_KEY = 'PM-Node-IDs';
my @node_ids;
if (defined( my $node_ids = $CACHE->get($NODE_IDS_KEY) )) {
	say "Using cached Node IDs";
	@node_ids = split ',', $node_ids;
} else {
	# As per https://perlmonks.org/?node_id=3557, the only users
	# with >10k nodes are BrowserUk, ikegami, Corion, and LanX
	my $FETCH_LENGTH = 10_000;
	# Note we don't actually need to be logged in for this...
	# (the only difference is the "Rep" column will be missing)
	mech_get_pm( 6364,  # User Search / Nodes You Wrote
			user => $user_id,
			showtype => '',
			orderby => '',
			start => '0',
			length => $FETCH_LENGTH,
		);

	# e.g.: Next <a href="?node_id=6364;showtype=;start=50;orderby=;length=50;user=12345">50</a>
	warn "WARNING: It looks like FETCH_LENGTH=$FETCH_LENGTH wasn't enough"
		if defined $mech->find_link(url_regex=>qr/\bnode_id=6364\b.*\bstart=[0-9]/);

	# e.g.: (showing 1-1230 out of ~1234<a href="?node_id=656697"><sup>?</sup></a>)
	if ( $mech->text =~ /\bshowing\s+\d+-\d+\s+out\s+of\s+~?\d+\b/ ) { say $& }
	else { warn "WARNING: Failed to find node count" }

	my $writeups;
	for my $t (@{ HTML::TableContentParser->new->parse($mech->content(raw=>1)) }) {
		if ( $t->{id} && $t->{id} eq 'writeups' ) {
			die "more than one node table found" if $writeups;
			$writeups = $t;
		}
	}
	die "no node table found" unless $writeups;

	my $r0 = join ',', map {$_->{data}} @{$writeups->{rows}[0]{cells}};
	die "Unexpected row 0: ".pp($r0) unless $r0 eq "Node ID,Writeup,Rep,Created"
		|| $r0 eq 'Node ID,Writeup,Created';

	my $cnt = @{$writeups->{rows}}-1;
	say "Found table with $cnt nodes";

	push @node_ids, validate_id($writeups->{rows}[$_]{cells}[0]{data}) for 1..$cnt;
	$CACHE->set($NODE_IDS_KEY, join ',', @node_ids);
}
die "No node IDs" unless @node_ids;
push @node_ids, sort keys %{$ALSO{add}};
validate_id($_) for @node_ids;
say "Have ".@node_ids." Node IDs";

#TODO Later: Consider extracting links from Personal Nodelet and Free Nodelet?
# Could also consider fetching locked nodes while logged in.
mech_get_pm(366609, displaytype=>'print');  # Personal Nodelet Settings
mech_get_pm(492700, displaytype=>'print');  # Free Nodelet Settings

# FROM HERE ON OUT, access as Anonymous Monk, so that all
# the data we save is only the publicly available stuff.
$jar->clear;

# Helper function to scrape and save the HTML-print version of a node
my $html_file_cnt = 0;
sub save_html {
	die unless @_==1;
	my $id = shift;
	mech_get_pm( $id, displaytype => 'print' );
	my $hf = $XML_PATH->child(substr $id, -1)->child("$id.html");
	$mech->save_content($hf, decoded_by_headers => 1, binmode => ':raw:encoding(UTF-8)' );
	# Yes, I know the following is an ugly hack, see node 11116478.
	# find xml -iname '*.html' -exec grep -Ei '<(link|base)' '{}' +
	$hf->edit_utf8(sub{ s/\h*<link[^>]*\/>\h*\v*//sgi;
		s/<head\s*>\K/\n    <base href="$BASE_URL"\/>/si;
		s/<html\s*>/<html lang="en" style="color-scheme: light dark;">/si });
	$html_file_cnt++;
}

my %patches = map {
		validate_id( $_->basename( qr/\.patch\z/i ) ) => [ $_, 0 ],  # [file, use_cnt]
	} $PATCH_PATH->children( qr/\.patch\z/i );

my %get_node_info = map {($_=>1)} map {keys %$_} values %ALSO;
my %locked_nodes;
my @node_queue = ( $user_id, @node_ids );
my %handled_nodes;
my $xml_file_cnt = 0;
while (my $nid = shift @node_queue) {
	next if $handled_nodes{$nid}++;  # deduplicate
	print "(".@node_queue." left) " if $VERBOSE;

	# `xmlstyle` as per https://perlmonks.org/?node_id=72241
	my $get = sub { mech_get_pm( $nid, displaytype => 'xml', xmlstyle => 'flat' ) };
	eval { $get->(); 1 } or $get->();  # retry once
	my $node = eval { PmNode->new($nid, string=>$mech->content(raw=>1)) }
		or die "Failed to create new node $nid: $@";
	my $is_my_node = ($node->auth_id//-1) == $user_id;
	$node->lenient( $is_my_node ? 0 : 1 );

	$locked_nodes{$nid}++ if $node->type eq 'locked';

	# add the thread info if this node is part of one
	if ($node->threaded) {
		# get thread structure from "XML Node Thread"
		mech_get_pm( 180684, xmlstyle => 'flat',
			id => $node->type eq 'note' ? $node->root_node : $nid );
		$node->add_thread( string=>$mech->content(raw=>1) );
		$get_node_info{$node->root_node}++;
	}

	# apply a patch if it exists for this node
	if ($patches{$nid}) {
		my $patch_file = $patches{$nid}[0];
		my $temp_file = path(tempdir(CLEANUP=>1))->child("$nid.txt");
		$temp_file->spew_utf8($node->doctext);
		system('patch', '-p1', '--quiet', $temp_file, $patch_file) and die "patch failed on $nid";
		$node->set_doctext($temp_file->slurp_utf8);
		$patches{$nid}[1]++;
	}

	# save the file, or remember this node for its info to be fetched later
	if (exists $ALSO{skip}{$nid} || $node->is_bad) { $get_node_info{$nid}++ }
	else {
		eval { $node->save; 1 } or die "Failed to save node $nid: $@";
		$xml_file_cnt++ }

	# Extract links from our nodes and follow those too
	if ( $is_my_node ) {
		die "Our node $nid has no doctext" unless $node->doctext=~/\S/;
		eval { push @node_queue, $node->links; 1 }
			or warn "WARNING: Skipping links in $nid due to: $@";
		# Also archive the parent node and our scratchpad
		push @node_queue, grep {defined} $node->parent_node, $node->user_scratchpad;
	}
	elsif ( defined $node->doctext )  # otherwise, just inform user of failed parses
		{ eval { $node->tokens } or warn "WARNING: Node $nid failed parse: $@" }
	elsif ( ( $node->type eq 'superdoc' || $node->type eq 'tutlist' ) && !$node->is_bad ) {
		# Looking at %PmNode::TYPES, it makes sense to scrape these as HTML in print mode.
		save_html($nid) unless exists $ALSO{skip}{$nid};
	}
}

save_html(validate_id($_)) for sort keys %{$ALSO{html}};

if ( my @bad_patches = grep { $_->[1]!=1 } values %patches )
	{ die "Patch not used exactly once: ".pp(@bad_patches) }

my @get_node_info = sort { $a <=> $b } keys %{{ map {$_=>1}
	# xml files will exist for locked nodes, which is why we treat them separately here:
	grep({!PmNode->file_for_id($_)->exists} keys %get_node_info), keys %locked_nodes }};
my $ni_doc = XML::LibXML->createDocument('1.0', 'UTF-8');
$ni_doc->setDocumentElement( $ni_doc->createElement('info') );
my $NODE_QUERY_BATCH_SIZE = 100;
for (my $i=0; $i<@get_node_info; $i+=$NODE_QUERY_BATCH_SIZE) {
	my $end = min($i+$NODE_QUERY_BATCH_SIZE, $#get_node_info);
	my $want = $end-$i+1;
	# Get node info from the Node query XML Generator
	mech_get_pm( 37150, xmlstyle => 'flat', nodes=>join ',', @get_node_info[ $i .. $end ] );
	my $doc = XML::LibXML->load_xml(string=>$mech->content(raw=>1));
	$doc->setEncoding('UTF-8');
	die $doc->toString(1) unless $doc->documentElement->nodeName eq 'info';
	my $got_nodes = $doc->documentElement->getChildrenByTagName('node')->size;
	warn "Wanted $want node infos but got $got_nodes\n" unless $got_nodes == $want;
	for my $ch ($doc->documentElement->childNodes) {
		next if $ch->nodeType == XML_TEXT_NODE;  # <info ...>Rendered by ...<node
		# NOTE that locked nodes will still show up with `nodetype="note"` here!
		die $ch->toString(1) unless $ch->nodeType == XML_ELEMENT_NODE && $ch->nodeName eq 'node';
		$ch->normalize;
		die $ch->toString(1) unless $ch->childNodes->size==1
			&& $ch->firstChild->nodeType == XML_TEXT_NODE;
		$ni_doc->documentElement->appendChild($ch);
	}
}
XML::LibXML::Schema->new(location=>$XML_PATH->child('node.xsd'), no_network=>1)
	->validate($ni_doc);
$ni_doc->toFile( $XML_PATH->child('node_info.xml'), 1 );

say "Done, wrote $xml_file_cnt XML and $html_file_cnt HTML files.";

# spell: ignore Nodelet writeups xmlstyle displaytype homenode Corion
# spell: ignore showtype ikegami autocheck superdoc tutlist binmode