package NodeList;
use warnings;
use 5.014;
use PmNode;
use XML::LibXML ();
use Data::Dump qw/dd pp/;
use MyConfig qw/ $XML_PATH /;
use Carp qw/carp croak confess/;
use DateTime::Format::Strptime ();
use Hash::Util qw/lock_hashref_recurse/;

package NodeInfo {
	use Data::Dump qw/dd pp/;
	use Carp qw/carp croak confess/;
	use Common qw/ validate_id %NODE_TYPES /;

	sub new {
		croak "Bad number of arguments to new" unless @_>1 && @_%2;
		my ($class, %args) = @_;
		croak "Bad arguments to new" unless keys(%args)==7
			&& join("\0", sort keys %args) eq "aid\0auth\0date\0dest\0id\0title\0type";
		validate_id($args{aid}, 'author');
		croak "Empty author" unless $args{auth}=~/\S/;
		if (defined $args{date}) {
			croak "Bad date ".pp($args{date}) unless $args{date}->isa('DateTime');
			$args{date} = $args{date}->clone;
			$args{date}->set_time_zone('UTC');
		}
		validate_id($args{id});
		croak "Empty title" unless $args{title}=~/\S/;
		croak "Bad type ".pp($args{type}) unless exists $NODE_TYPES{$args{type}};
		return bless {%args}, $class;
	}

	for my $p (qw/ aid auth date dest id title type /) {
		my $m = sub { croak "Bad number of arguments to $p" unless @_==1; shift->{$p} };
		no strict 'refs';
		*$p = $m;
	}

	sub type_name {
		croak "Bad number of arguments to type_name" unless @_==1;
		return $NODE_TYPES{shift->{type}}{name};
	}

	sub equals {
		croak "Bad number of arguments to equals" unless @_==2 || @_==3;
		my ($self, $other, $ignore_dest) = @_;
		return !!(
			ref $other && $other->isa(__PACKAGE__)
			&& $other->aid   eq $self->aid
			&& $other->auth  eq $self->auth
			&& (    defined $other->date &&  defined $self->date && $other->date eq $self->date
				|| !defined $other->date && !defined $self->date )
			&& ( $ignore_dest
				||  defined $other->dest &&  defined $self->dest && $other->dest eq $self->dest
				|| !defined $other->dest && !defined $self->dest )
			&& $other->id    eq $self->id
			&& $other->title eq $self->title
			&& $other->type  eq $self->type
		)
	}
}

# This package requires PmNode, which through a dependency chain requires PmLink,
# but PmLink also needs to require this package. So provide this singleton getter
# for PmLink to use as a way to break the circular dependency chain by deferring
# the loading of the NodeList until runtime.
sub inst {
	croak "Bad arguments to inst" unless @_==1;
	state $instance = shift->_load;
	return $instance;
}

sub _load {
	croak "Bad number of arguments to _load" unless @_==1;
	my $class = shift;

	my %by_id;
	my %by_title;

	# Helper function to add new node infos, checking for collisions
	my $add = sub {
		my $n = NodeInfo->new(@_);
		if ( exists $by_id{$n->id} && !$n->equals( my $h = $by_id{$n->id} ) ) {
			# One exception: If the only difference is that the node we have has
			# a dest set, and the one being added doesn't, then ignore the add.
			return if $n->equals($h, 1) && defined $h->dest && !defined $n->dest;
			confess "Duplicate IDs, different objects: have=".pp($h).", new=".pp($n);
		}
		confess "Duplicate titles, different objects: ".pp($n, $by_title{$n->title}{$n->id})
			if exists $by_title{$n->title} && exists $by_title{$n->title}{$n->id}
				&& !$n->equals($by_title{$n->title}{$n->id});
		$by_id{$n->id} = $n;
		$by_title{$n->title}{$n->id} = $n;
	};

	# Load the node infos from the XML files we scraped
	my %locked_nodes;
	my @users;
	my $sp1 = DateTime::Format::Strptime->new(pattern => '%Y-%m-%d %H:%M:%S',
		# It seems dates & times in XML are server time, which is Eastern Standard (I think)
		time_zone=>'America/New_York', on_error=>'croak');
	for my $id (PmNode->list_nodes) {
		my $node = PmNode->load_by_id($id);
		if ($node->type eq 'locked') { $locked_nodes{$id}++ }
		else {
			$add->( id=>$id, type=>$node->type, dest=>$node->dest, title=>$node->title,
				aid=>$node->auth_id, auth=>$node->auth_name,
				date=>$node->type eq 'user' ? undef : $sp1->parse_datetime($node->created) );
			# Delay the adding of users so that we add those (few) which do have a `dest` first.
			push @users, { id=>$node->auth_id, type=>'user', dest=>undef, title=>$node->auth_name,
				aid=>$node->auth_id, auth=>$node->auth_name, date=>undef };
		}
	}
	$add->(%$_) for @users;

	# Load the node infos from the node_info.xml we scraped
	my $sp2 = DateTime::Format::Strptime->new(pattern => '%Y%m%d%H%M%S',
		time_zone=>'America/New_York', on_error=>'croak');
	my $doc = XML::LibXML->load_xml(location=>$XML_PATH->child('node_info.xml'));
	XML::LibXML::Schema->new(location=>$XML_PATH->child('node.xsd'), no_network=>1)->validate($doc);
	for my $n ($doc->documentElement->nonBlankChildNodes) {
		my $id = $n->getAttribute('node_id');
		my $t = $n->getAttribute('nodetype');
		# Locked nodes show up as their original type in this list; override
		croak "locked node that wasn't a note: ".$n->toString
			if $locked_nodes{$id} && $t ne 'note';
		$t = 'locked' if $locked_nodes{$id};
		my $aid = $n->getAttribute('author_user');
		my $auth = $n->getAttribute('author_name');
		$add->( id=>$id, type=>$t, dest=>undef, title=>$n->textContent, aid=>$aid, auth=>$auth,
			date=>$sp2->parse_datetime($n->getAttribute('createtime')) );
		$add->( id=>$aid, type=>'user', dest=>undef, title=>$auth,
			aid=>$aid, auth=>$auth, date=>undef );
	}

	my $self = bless {
		by_id => \%by_id,
		by_title => \%by_title,
	}, $class;
	lock_hashref_recurse($self->{by_id});
	lock_hashref_recurse($self->{by_title});
	return $self;
}

sub by_id {
	croak "Bad number of arguments to by_id" unless @_==2;
	my ($self,$id) = @_;
	return exists $self->{by_id}{$id} ? $self->{by_id}{$id} : undef;
}

sub by_title {
	croak "Bad number of arguments to by_title" unless @_==2;
	my ($self,$title) = @_;
	return exists $self->{by_title}{$title} ? [values %{$self->{by_title}{$title}}] : [];
}

# spell: ignore nodetype hashref createtime strptime
1;