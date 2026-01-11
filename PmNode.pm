package PmNode;
use warnings;
use 5.014;
use URI ();
use Data::Dump qw/dd pp/;
use XML::LibXML qw/:libxml/;
use Carp qw/carp croak confess/;
use PmParser qw/ node_tokenizer /;
use MyConfig qw/ $XML_PATH %ALSO /;
use Common qw/ validate_id %NODE_TYPES /;

my $NODE_REAPER = 52855;

sub new {
	croak "Bad number of arguments to new" unless @_==4;
	my ($class,$id,$x,$y) = @_;  # normally (IO=>$fh), (string=>$str), or (location=>$filename)
	validate_id($id);
	my $doc = XML::LibXML->load_xml($x=>$y);
	$doc->setEncoding('UTF-8');  # switch from Windows-1252
	my $self = bless { id => $id, doc => $doc }, $class;
	if (defined( my $xid = $self->xid )) {  # we'll just have to trust locked nodes' IDs
		croak "Node ID mismatch: XML says $xid but argument is $id"
			unless $xid == $id || $self->is_bad;
	}
	confess "User node ID mismatch" if $self->type eq 'user' && $id != $self->auth_id;
	return $self;
}

sub schema_validate {
	croak "Bad number of arguments to schema_validate" unless @_==1;
	my $self = shift;
	state $node_schema = XML::LibXML::Schema->new(
		location=>$XML_PATH->child('node.xsd'), no_network=>1);
	$node_schema->validate($self->{doc});
	# extra validation the schema can't cover
	for my $f ($self->{doc}->findnodes('//*[@field_name]')) {
		croak "field_name mismatch ".$f->toString
			unless $f->nodeName eq $f->getAttribute('field_name') }
	return $self;
}

sub load_by_id {
	croak "Bad number of arguments to load_by_id" unless @_==2;
	my ($class, $node_id) = @_;
	return $class->new( $node_id, location => file_for_id($node_id) )->schema_validate
}

sub list_nodes {
	# can be called as method or regular function
	croak "Bad number of arguments to list_nodes" unless @_==0 || @_==1;
	return map { validate_id($_->basename( qr/\.xml\z/i )) }
		map { $_->children( qr/\.xml\z/i ) } $XML_PATH->children( qr/\A[0-9]\z/ )
}

sub file_for_id {
	# can be called as method or regular function
	croak "Bad number of arguments to file_for_id" unless @_==1 || @_==2;
	my $node_id = shift;
	$node_id = shift if @_;  # clobber $class/$self
	validate_id($node_id);
	return $XML_PATH->child(substr($node_id,-1))->child("$node_id.xml")
}

sub save {
	croak "Bad number of arguments to save" unless @_==1;
	my $self = shift->schema_validate;
	$self->{doc}->toFile(
		$XML_PATH->child(substr($self->{id},-1))->mkdir->child($self->{id}.'.xml'), 1 );
}

sub lenient {
	croak "Bad number of arguments to lenient" unless @_==1 || @_==2;
	my $self = shift;
	if (@_) {  # setter
		my $v = shift;
		croak "Bad argument to lenient" unless defined $v && ( $v eq '0' || $v eq '1' );
		$self->{doc}->documentElement->setAttribute('_doctext_mode', $v ? 'lenient' : 'strict')
			if $self->type ne 'locked';
	}
	my $m = $self->{doc}->documentElement->getAttribute('_doctext_mode') // 'strict';
	confess "Bad _doctext_mode value ".pp($m) unless $m eq 'strict' || $m eq 'lenient';
	return $m eq 'lenient' ? 1 : 0;
}

sub add_thread {
	croak "Bad number of arguments to add_thread" unless @_==3;
	my ($self,$x,$y) = @_;
	my $doc = XML::LibXML->load_xml($x=>$y);
	$doc->setEncoding('UTF-8');
	my $den = $doc->documentElement->nodeName;
	die "Unexpected documentElement name ".pp($den) unless $den eq 'thread';
	my $node = $self->{doc}->documentElement;
	die "Node already has a <$den>" if $node->getChildrenByTagName($den);
	# The <info> node only has things we don't care about, and esp. gentimeGMT
	# would make it non-static:
	# <info site="http://perlmonks.org/" sitename="PerlMonks" ticker_id="180684"
	# gentimeGMT="2026-01-11 14:18:13" xmlstyle="clean,flat"
	# xmlmaker="XML::Fling 1.002">Rendered by the XML Node Thread</info>
	$_->unbindNode for $doc->documentElement->getChildrenByTagName('info');
	$node->appendChild($doc->documentElement);
}

# helper function to get the text-only content from a node
sub _get_xml_text {
	croak "Bad number of arguments to _get_xml_text" unless @_==2;
	my ($self, $xpath) = @_;
	my $ns = $self->{doc}->findnodes($xpath);
	croak "Didn't find exactly one result for ".pp($xpath) unless $ns->size==1;
	my $n = $ns->[0];
	return $n->value if $n->nodeType==XML_ATTRIBUTE_NODE;
	confess "Can't handle this node type: ".$n->toString unless $n->nodeType==XML_ELEMENT_NODE;
	$n->normalize;
	return '' if $n->childNodes->size==0;
	confess "Unexpected child nodes: ".$n->toString unless $n->childNodes->size==1
		&& $n->childNodes->[0]->nodeType==XML_TEXT_NODE;
	return $n->childNodes->[0]->data;
}

sub xid {  # ID from XML instead of user-specified
	croak "Bad number of arguments to xid" unless @_==1;
	my $self = shift;
	return undef if $self->type eq 'locked';
	return $self->{_xid} if defined $self->{_xid};
	return( $self->{_xid} = validate_id( $self->_get_xml_text('/node/@id') ) )
}

sub is_bad {
	croak "Bad number of arguments to is_bad" unless @_==1;
	my $xid = shift->xid;
	return undef unless defined $xid;
	if ( $xid==2294 ) { return "Permission Denied" }
	elsif ( $xid==3544 ) { return "Not Found" }
	return undef;
}

sub type {
	croak "Bad number of arguments to type" unless @_==1;
	my $self = shift;
	return $self->{_type} if $self->{_type};
	# perl -wM5.014 -0777 -ne '(/<locked\/>$/ xor /<type\s+id=/)||die$ARGV' $(find xml -type f)
	$self->{_type} = $self->{doc}->documentElement->nodeName eq 'locked'
		&& $self->{doc}->documentElement->childNodes->size==0
		? 'locked' : $self->_get_xml_text('/node/type');
	confess "Unknown node type ".pp($self->{_type}) unless exists $NODE_TYPES{$self->{_type}};
	return $self->{_type};
}

sub threaded {  # this node is expected to be part of a thread
	croak "Bad number of arguments to threaded" unless @_==1;
	return $NODE_TYPES{shift->type}->{thread};
}
sub thread {
	croak "Bad number of arguments to thread" unless @_==1;
	my $self = shift;
	return $self->{_thread} if $self->{_thread};
	my $ns = $self->{doc}->findnodes('/node/thread');
	confess pp($ns) if $ns->size>1;
	# just some double-check paranoia
	confess "Have <thread> but not ->threaded?" if $ns->size && !$self->threaded;
	confess "No <thread> but am ->threaded?" if !$ns->size && $self->threaded;
	return undef unless $ns->size;
	# Turn the thread into a data structure
	my $thr; $thr = sub { my $n = shift;
		[ 0+validate_id($n->getAttribute('id')), map {$thr->($_)} $n->nonBlankChildNodes ] };
	$self->{_thread} = $thr->($ns->[0]);
	# Quick self check that our ID is in this thread
	my $seen_self;
	my $find; $find = sub { my $t=shift; $seen_self=1 if $t->[0]==$self->{id};
		$find->($t->[$_]) for 1..$#$t };
	$find->($self->{_thread});
	confess unless $seen_self;
	return $self->{_thread}
}

sub dest {
	croak "Bad number of arguments to dest" unless @_==1;
	my $self = shift;
	return undef if $self->type eq 'locked' || $self->is_bad || !defined $self->doctext
		|| exists $ALSO{rend}{$self->{id}};
	return $self->type eq 'note' ? validate_id($self->root_node).'.html#'.validate_id($self->{id})
		: validate_id($self->{id}).'.html';
}

sub auth_id {
	croak "Bad number of arguments to auth_id" unless @_==1;
	my $self = shift;
	# perl -wM5.014 -0777 -ne '(/<locked\/>$/ xor /<author\s+id="/)||die$ARGV' $(find xml -type f)
	return undef if $self->type eq 'locked';
	return $self->{_auth_id} if defined $self->{_auth_id};
	return( $self->{_auth_id} = validate_id( $self->_get_xml_text('/node/author/@id'), 'author' ) )
}
sub auth_name {
	croak "Bad number of arguments to auth_name" unless @_==1;
	my $self = shift;
	return undef if $self->type eq 'locked';
	return $self->{_auth_name} if defined $self->{_auth_name};
	return( $self->{_auth_name} = $self->_get_xml_text('/node/author') );
}

sub created {
	croak "Bad number of arguments to created" unless @_==1;
	my $self = shift;
	return undef if $self->type eq 'locked';
	return $self->{_created} if defined $self->{_created};
	return( $self->{_created} = $self->_get_xml_text('/node/@created') );
}

sub title {
	croak "Bad number of arguments to title" unless @_==1;
	my $self = shift;
	return undef if $self->type eq 'locked';
	return $self->{_title} if defined $self->{_title};
	return( $self->{_title} = $self->_get_xml_text('/node/@title') );
}

sub root_node {
	croak "Bad number of arguments to root_node" unless @_==1;
	my $self = shift;
	# perl -wM5.014 -0777 -ne '(/<root_node/ xor />note<\/type>/)&&die$ARGV' $(find xml -type f)
	return undef unless $NODE_TYPES{$self->type}->{thread};
	return $self->{id} unless $self->type eq 'note';
	return $self->{_root_node} if defined $self->{_root_node};
	return( $self->{_root_node} = validate_id($self->_get_xml_text('/node/root_node'), 'root') )
}

sub parent_node {
	croak "Bad number of arguments to parent_node" unless @_==1;
	my $self = shift;
	# perl -wM5.014 -0777 -ne '(/<parent_node/ xor />note<\/type>/)&&die$ARGV' $(find xml -type f)
	return undef unless $self->type eq 'note';
	return $self->{_parent_node} if defined $self->{_parent_node};
	return( $self->{_parent_node}
		= validate_id($self->_get_xml_text('/node/parent_node'), 'parent') )
}

sub user_scratchpad {
	croak "Bad number of arguments to user_scratchpad" unless @_==1;
	my $self = shift;
	# I've only scraped a few user nodes so far but this seems to be true:
	return undef unless $self->type eq 'user';
	return $self->{_user_scratchpad} if defined $self->{_user_scratchpad};
	return( $self->{_user_scratchpad}
		= validate_id( $self->_get_xml_text('/node/user_scratchpad'), 'scratchpad' ) )
}

sub doctext {
	croak "Bad number of arguments to doctext" unless @_==1;
	my $self = shift;
	return undef unless $NODE_TYPES{$self->type}->{doctext};  # see %NODE_TYPES for validation info
	return $self->{_doctext} if defined $self->{_doctext};
	$self->{_doctext} = $self->_get_xml_text('/node/doctext');
	croak "Got undef doctext for node ".$self->{id} unless defined $self->{_doctext};
	carp "Empty doctext in node ".$self->{id} unless $self->{_doctext} =~ /\S/
		|| $self->type eq 'scratchpad' || $self->type eq 'user' || $self->auth_id==$NODE_REAPER;
	return $self->{_doctext}
}

sub set_doctext {
	croak "Bad number of arguments to set_doctext" unless @_==2;
	my ($self, $doctext) = @_;
	croak "Can't set doctext on a node without doctext" unless defined $self->doctext;
	# _get_xml_text validated for us that the <doctext> node exists:
	my $node = $self->{doc}->findnodes('/node/doctext')->[0];
	$node->removeChildNodes;
	$node->appendText($doctext);
	$self->{_doctext} = $doctext;
}

sub tokens {  # return the result of the node tokenizer on this node's doctext
	croak "Bad number of arguments to tokens" unless @_==1 || @_==2;
	my ($self, $debug) = @_;
	my $doctext = $self->doctext;
	croak "Can't parse a node without doctext" unless defined $doctext;
	my $lenient = $self->lenient;
	my $key = $lenient ? '_tokens_lenient' : '_tokens_strict';
	return $self->{$key} if $self->{$key};
	return( $self->{$key} = node_tokenizer($doctext, $lenient, $debug) )
}

sub links {  # extract all links by ID from this node's parsed doctext (except <a href>)
	croak "Bad number of arguments to links" unless @_==1;
	my $tokens = shift->tokens;
	my @links = map { $_->target } grep { $_->isa('PmLink') && (
		$_->scheme eq 'id' || $_->scheme eq 'node' && $_->target=~/\A(?!0)[0-9]+\z/ ) } @$tokens;
	validate_id($_, 'link') for @links;
	return @links;
}

sub render {  # turn this node's doctext into XHTML
	croak "Bad number of arguments to render" unless @_==1;
	my $html = join '', @{ shift->tokens };  # Token overloads stringification
	# munge and parse the resulting HTML
	my $doc = XML::LibXML->load_html(
		string => '<html><body>'.$html.'</body></html>',
		recover => 1, suppress_errors => 1 );
	my $bodies = $doc->findnodes('/html/body');
	$bodies->size==1 or confess pp($bodies);
	$doc->setDocumentElement($bodies->[0]);  # don't need the <head> etc.
	# validate against our custom schema
	state $xhtml_schema = XML::LibXML::Schema->new(
		location=>$XML_PATH->child('pm-xhtml.xsd'), no_network=>1);
	$xhtml_schema->validate($doc->documentElement);
	# munge a bit more
	$doc->documentElement->setNodeName('div');
	$doc->documentElement->setAttribute(class=>'node-content');
	for my $anc ($doc->findnodes('//a[@href]')) {
		my $uri = URI->new($anc->getAttribute('href'));
		if ($uri->scheme) { $anc->setAttribute(target=>'_blank') }
		else { $anc->removeAttribute('target') }
	}
	return $doc;
}

# spell: ignore findnodes gentime sitename xmlmaker xmlstyle
1;