#!/usr/bin/env perl
use warnings;
use 5.014;
use URI ();
use FindBin;
use XML::LibXML ();
use List::Util qw/min/;
use Data::Dump qw/dd pp/;
use JSON::PP qw/encode_json/;
use Carp qw/carp croak confess/;
use lib $FindBin::Bin;
use Common qw/ validate_id /;
use MyConfig qw/ $XML_PATH $BASE_URL $OUT_PATH $STYLESHEET /;
use NodeList;
use PmNode;

sub lnk {  # helper to make an <a>
	confess pp(\@_) unless @_==2 || @_==3;
	my ($doc, $href, $text) = @_;
	$text //= $href;
	my $anc = $doc->createElement('a');
	$anc->setAttribute(href=>$href);
	$anc->setAttribute(target=>'_blank') if URI->new($href)->scheme;
	$anc->appendText($text);
	return $anc;
}

sub make_page {  # make a basic page
	confess pp(\@_) unless @_==2;
	my ($id, $title) = @_;
	my $doc = XML::LibXML->createDocument('1.0', 'UTF-8');
	$doc->setStandalone;
	$doc->setInternalSubset( $doc->createInternalSubset(
		"html", "-//W3C//DTD HTML 4.0 Transitional//EN",
		"http://www.w3.org/TR/REC-html40/loose.dtd" ) );
	$doc->setDocumentElement( my $html = $doc->createElement('html') );
	$html->setAttribute(lang=>'en');
	$html->setAttribute(style=>'color-scheme: light dark;');
	# head
	$html->appendChild( my $head = $doc->createElement('head') );
	$head->appendChild( my $meta_c = $doc->createElement('meta') );
	$meta_c->setAttribute(charset=>'UTF-8');
	$head->appendChild( my $link_ss = $doc->createElement('link') );
	$link_ss->setAttribute(rel=>'stylesheet');
	$link_ss->setAttribute(href=>$STYLESHEET->basename);
	$head->appendChild( my $title_el = $doc->createElement('title') );
	$title_el->appendText( $title );
	# body
	$html->appendChild( my $body = $doc->createElement('body') );
	$body->appendChild( my $header = $doc->createElement('header') );
	$header->appendChild( my $h1 = $doc->createElement('h1') );
	$h1->appendText( $title );
	$body->appendChild( my $main = $doc->createElement('main') );
	# footer
	$body->appendChild( my $footer = $doc->createElement('footer') );
	$footer->appendChild( lnk($doc, 'index.html', "Hauke's PerlMonks Archive") );
	$footer->appendText(" \N{U+2002}\N{U+2022}\N{U+2002} ");
	$footer->appendChild( my $slk = $doc->createElement('strong') );
	$slk->appendChild( lnk($doc, 'search.html', "\N{U+1F50E} Search") );
	if (length $id) {
		$footer->appendText( " \N{U+2002}\N{U+2022}\N{U+2002} Archived version of " );
		$footer->appendChild( lnk($doc, $BASE_URL.'?node_id='.validate_id($id)) );
	}
	return $doc, $main;
}

sub make_node {  # render a node
	confess pp(\@_) unless @_==3;
	my ($doc, $id, $node) = @_;
	my $div = $doc->createElement('div');
	$div->setAttribute(class=>'node');
	$div->setAttribute(id=>$id);
	my $non_archived = 1;
	if ( my $inf = NodeList->inst->by_id($id) ) {
		$div->appendChild( my $nt = $doc->createElement('div') );
		$nt->setAttribute(class=>'node-title');
		$nt->appendText( $inf->title );
		if ( $inf->type eq 'locked' ) {
			$div->appendChild( my $na = $doc->createElement('div') );
			$na->setAttribute(class=>'non-archived');
			$na->appendText("This node falls below the community's minimum standard of quality.");
			$non_archived = 0;
		}
		else {
			$div->appendChild( my $ni = $doc->createElement('div') );
			$ni->setAttribute(class=>'node-info');
			$ni->appendText( $inf->type_name.' ' );
			$ni->appendChild( lnk($doc, $BASE_URL.'?node_id='.$id, '['.$id.']') );
			if ( $inf->type ne 'user' ) {
				$ni->appendText( ' by ' );
				$ni->appendChild( lnk($doc, $BASE_URL.'?node_id='.$inf->aid, $inf->auth) );
				$ni->appendText( ' on '.$inf->date->strftime('%Y-%m-%d %H:%M:%S %Z') );
			}
			# ->dest will return undef if the node shouldn't be rendered
			if ( $node && $node->dest ) {
				$div->appendChild( $node->render->documentElement );
				$non_archived = 0;
			}
		}
	}
	if ($non_archived) {
		$div->appendChild( my $na = $doc->createElement('div') );
		$na->setAttribute(class=>'non-archived');
		$na->appendChild( lnk($doc, $BASE_URL.'?node_id='.$id, "Non-archived node $id") );
	}
	return $div;
}

# load all nodes and build a list of threads
my %nodes;
my %threads;
for my $id (PmNode->list_nodes) {
	confess $id if $nodes{$id};  # no dupes
	$nodes{$id} = PmNode->load_by_id($id);
	# assume thread structures for all nodes in the same thread are the same:
	my $th = $nodes{$id}->thread // ( $nodes{$id}->dest ? [$id] : undef );
	$threads{encode_json($th)} = $th if defined $th;
}

# double-check to make sure all threads are disjoint
sub flatten { map { ref ? flatten($_) : $_ } @{shift()} }
my %disjoint_check; $disjoint_check{$_}++ && die $_ for map {flatten($_)} values %threads;

# begin generating
$OUT_PATH->mkdir;
$STYLESHEET->copy($OUT_PATH->child($STYLESHEET->basename));

my $html_file_cnt = 0;
my @page_list;  # for page_list.html

# threads
for my $thread ( map {$_->[0]} sort { $a->[1] <=> $b->[1] } map { [$_,min(flatten($_))] }
		values %threads ) {
	my $root = validate_id($thread->[0]);
	my $ni = NodeList->inst->by_id($root) or die $root;
	my $fn = $OUT_PATH->child($root.'.html');
	confess pp($fn,$ni) unless !defined $ni->dest
		|| $ni->dest !~ /\A\Q$fn->basename\E(?:#[0-9]+)?\z/;
	my ($doc, $main) = make_page($root, $ni->type_name.': '.$ni->title);
	# process the thread
	my $proc; $proc = sub {
		my ($parent, $thr, $depth) = @_;
		my $id = validate_id( shift @$thr );
		$parent->appendChild( my $div = make_node($doc, $id, $nodes{$id}) );
		# figure out how many replies, and whether any of them will be rendered
		my ($rs,$rr) = (0,0);
		for (flatten($thr)) { $rs++; $rr++ if NodeList->inst->by_id($_) }
		# if all children won't be rendered, don't descend down the tree
		if (!NodeList->inst->by_id($id) && !$rr)
			{ $div->appendText("(and $rs more non-archived replies hidden)") if $rs }
		else { $proc->($div, $_, $depth+1) for @$thr }
	};
	$proc->($main, $thread, 0);
	$doc->toFile($fn, 1);
	$html_file_cnt++;
	push @page_list, [$fn, $ni];
}

my @html_list;  # for page_list.html
$XML_PATH->visit(sub { push @html_list, $_ if /\.html$/i }, { recurse=>1 });
# based on https://perlmonks.org/?node=print%20displaytype%20stylesheet
my $HTML_PRINT_STYLE = <<'EOF';
#header, #url {
	border: solid 1px CanvasText;
	background-color: ButtonFace;
	padding: 10px;
	margin: 5px;
	font-weight: bold;
}
#header > .title { font-size: larger; }
EOF

{ # page_list.html
	my ($doc, $main) = make_page(undef, "Full List of Archived Threads");
	$main->appendChild( my $ul1 = $doc->createElement('ul') );
	for my $page (reverse @page_list) {
		$ul1->appendChild( my $li = $doc->createElement('li') );
		$li->appendChild( lnk($doc, $page->[0]->basename,
			$page->[1]->type_name.': '.$page->[1]->title) );
	}
	$main->appendChild( my $p1 = $doc->createElement('p') );
	$p1->appendText('Pages scraped as HTML only:');
	$main->appendChild( my $ul2 = $doc->createElement('ul') );
	for my $html (@html_list) {
		my $dest = $OUT_PATH->child($html->basename);
		carp "Overwriting $dest with HTML version"
			if grep { $_->[0]->basename eq $html->basename } @page_list;
		$html->copy($dest);
		$html_file_cnt++;
		my $title;  # Yes another ugly hack, I know, see node 11116478.
		$dest->edit_utf8(sub { s{<head\s*>\K}{\n<style>$HTML_PRINT_STYLE</style>}si;
			($title)=m{<title\s*>([^<>]+)</title\s*>}si or die $html->basename });
		$title =~ s/^\s+|\s+$//g;
		$ul2->appendChild( my $li = $doc->createElement('li') );
		$li->appendChild( lnk($doc, $html->basename, $title) );
	}
	$doc->toFile($OUT_PATH->child('page_list.html'));
	$html_file_cnt++;
}

{ # search.html
	my ($doc, $main) = make_page(undef, "\N{U+1F50E} Search the Archive");

	# https://pagefind.app/docs/
	$main->appendChild( my $link = $doc->createElement('link') );
	$link->setAttribute(href=>'pagefind/pagefind-ui.css');
	$link->setAttribute(rel=>'stylesheet');
	$main->appendChild( my $scr1 = $doc->createElement('script') );
	$scr1->setAttribute(src=>'pagefind/pagefind-ui.js');
	$scr1->appendChild( $doc->createTextNode('') );
	$main->appendChild( my $div = $doc->createElement('div') );
	$div->setAttribute(id=>'search');
	$main->appendChild( my $scr2 = $doc->createElement('script') );
	my $JS = <<'SCRIPT';
		function setTheme () {
			document.getElementById('search').classList.toggle('dark-mode',
				window.matchMedia('(prefers-color-scheme: dark)').matches );
		}
		window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', setTheme);
		window.addEventListener('DOMContentLoaded', (event) => {
			setTheme();
			new PagefindUI({ element: '#search', showSubResults: true, pageSize: 10,
				showImages: false });
		});
SCRIPT
	$scr2->appendText("\n// ");
	$scr2->appendChild($doc->createCDATASection("\n$JS// ") );
	$scr2->appendText("\n");

	$doc->toFile($OUT_PATH->child('search.html'));
	$html_file_cnt++;
}

{ # index.html
	my ($doc, $main) = make_page(undef, "Hauke's PerlMonks Archive");
	my $h1 = $doc->findnodes('//header/h1');
	die unless $h1->size==1;
	$h1->[0]->removeChildNodes;
	$h1->[0]->appendText("Hauke's ");
	$h1->[0]->appendChild( my $h1sp = $doc->createElement('span') );
	$h1sp->setAttribute(class=>'pm-font');
	$h1sp->appendText("PerlMonks");
	$h1->[0]->appendText(" Archive");

	$main->appendChild( my $p1 = $doc->createElement('p') );
	$p1->appendText('Sadly, ');
	$p1->appendChild( lnk($doc, $BASE_URL, 'PerlMonks') );
	$p1->appendText(<<'EOT');
 is being DDoS'ed by AI scrapers, making the site very slow sometimes.
Since I often reference the code I wrote in quite a few nodes as templates
for new code, I needed faster access to them, so this is a backup.
Please excuse that the rendering of some nodes and links here may not be perfect.
EOT

	$main->appendChild( my $p4 = $doc->createElement('p') );
	$p4->setAttribute(style=>'font-size: larger; font-weight: bold;');
	$p4->appendChild( lnk($doc, 'search.html', "\N{U+1F50E} Full-Text Search") );

	$main->appendChild( my $p2 = $doc->createElement('p') );
	$p2->appendChild( lnk($doc, 'page_list.html', 'Full List of Archived Threads') );

	# render my scratchpad ("Nodes of mine that I like to reference")
	$main->appendChild( $nodes{830550}->render->documentElement );

	$main->appendChild( my $p3 = $doc->createElement('p') );
	$p3->appendText( 'Some of my root nodes:' );
	$main->appendChild( my $ul1 = $doc->createElement('ul') );
	for my $page (@page_list) {
		next unless $page->[1]->aid == 830549 && $page->[1]->type
			!~ /\A(?:perlquestion|perlnews|monkdiscuss|user|scratchpad)\z/;
		$ul1->appendChild( my $li = $doc->createElement('li') );
		$li->appendChild( lnk($doc, $page->[0]->basename,
			$page->[1]->type_name.': '.$page->[1]->title) );
	}

	$doc->toFile($OUT_PATH->child('index.html'));
	$html_file_cnt++;
}

say "Done, wrote $html_file_cnt HTML files.";

# spell: ignore strftime monkdiscuss perlnews perlquestion findnodes pagefind