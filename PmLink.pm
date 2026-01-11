package PmLink;
use warnings;
use 5.014;
use Token;
use URI ();
use NodeList;
use Util::H2O 'h2o';
use Exporter 'import';
use PmHtml qw/ %TAGS /;
use Data::Dump qw/dd pp/;
use MyConfig qw/ $BASE_URL /;
use Hash::Util qw/lock_hash/;
use Carp qw/carp croak confess/;
use Common qw/ %ENT validate_id /;

our @EXPORT_OK = qw/ munge_uri $PM_LINK_REGEX /;

sub munge_uri {
	confess pp(\@_) unless @_==1 && $_[0]->isa('URI');
	my $u = shift;
	# fragment-only URI:
	if ( !$u->scheme && !$u->opaque ) { croak $u unless length $u->fragment; return $u }
	# detect links to PM
	if ( !$u->scheme || $u->scheme && ($u->scheme eq 'http' || $u->scheme eq 'https')
			&& $u->host =~/\A(?:www\.)?perlmonks\.(?:com|net|org)\z/i ) {
		# ->_port instead of ->port is the doc'd way to ignore default
		if ($u->scheme) { confess "$u" if $u->_port }  # don't expect there to be a port in URI
		else { confess "$u" if $u->authority }  # no scheme means there shouldn't be an authority
		confess "$u" unless $u->path eq '' || $u->path eq '/' || $u->path eq '/index.pl';
		my %q = $u->query_form;
		# check if we have this node
		if ( exists $q{node} ) {
			confess "$u" if exists $q{node_id};
			if ( $q{node}=~/\A(?!0)[0-9]+\z/ && ( my $n = NodeList->inst->by_id($q{node}) ) )
				{ return URI->new($n->dest) if $n->dest }
			my $ns = NodeList->inst->by_title($q{node});
			# link to local node if possible
			return URI->new($ns->[0]->dest) if @$ns==1 && $ns->[0]->dest;
		}
		elsif ( exists $q{node_id} ) {
			my $n = NodeList->inst->by_id($q{node_id});
			return URI->new($n->dest) if $n && $n->dest;
		}
		else { confess "$u" if $u->query }
		# normalize PM links
		my $n = URI->new($BASE_URL);
		$n->query( $u->query );
		$n->fragment( $u->fragment );
		return $n;
	}
	return $u;
}

# ##### ##### ##### A subset of https://perlmonks.org/?node_id=43037 ##### ##### #####

sub _u_q { my $u = URI->new(shift); $u->query_form(@_); $u }
my $NO_LINK = {};  # just a marker object

# Scheme handlers take one argument, the part after ://, and return two values:
# 1. the suggested link text (overridden by "|...]") and 2. the href of the resulting link.
my %SCHEMES = (
	node => sub { my $t = shift;
		return $BASE_URL, URI->new($BASE_URL) unless $t=~/\S/;
		return $t, munge_uri(_u_q($BASE_URL, node=>$t)) },

	# [id://123]
	id => sub { my $t = validate_id(shift);
		my $n = NodeList->inst->by_id($t);
		return $n ? $n->title : "[Node $t]", munge_uri(_u_q($BASE_URL, node_id=>$t)) },

	# [href://#anc], [href://?node_id=123#anc], [href://?node_id=123;x=y]
	href => sub { my $t = shift;
		my $u = URI->new($t);
		return $t, munge_uri($u) if $u->scheme && ( $u->scheme eq 'http' || $u->scheme eq 'https' );
		confess "Can't (yet) handle href://".pp($t) if $u->scheme || $u->authority || $u->path;
		my $n = URI->new($BASE_URL);
		$n->query( $u->query );
		$n->fragment( $u->fragment );
		return $t, munge_uri($n) },

	# http, https (ftp currently unused)
	http  => sub { my $t = 'http://' .shift; return $t, munge_uri(URI->new($t)) },
	https => sub { my $t = 'https://'.shift; return $t, munge_uri(URI->new($t)) },

	# [doc://-X], [doc://perlfaq2], [doc://perlfaq2#Perl-Books]
	doc => sub { my $t = shift;
		return 'Perl documentation', URI->new('https://perldoc.perl.org/') unless $t=~/\S/;
		#TODO Later: perldoc's search function doesn't work with anchors; this needs improvement
		return $t=~/\A.+#(.+)\z/ ? $1=~s/-/ /gr : $t,
			_u_q('https://perldoc.perl.org/search', q=>$t) },

	# Module docs: [mod://XML::Parser]
	mod => sub { my $t = shift;
		# Empty case not listed on https://perlmonks.org/?node_id=567724 so this is my take
		return 'CPAN search', URI->new('https://metacpan.org/') unless $t=~/\S/;
		return $t, _u_q('https://metacpan.org/search', q=>$t) },

	# A distribution on CPAN: [dist://XML-Parser]
	dist => sub { my $t = shift;
		return 'MetaCPAN', URI->new('https://metacpan.org/') unless $t=~/\S/;
		return $t, _u_q('https://metacpan.org/search', q=>$t) },

	# General search for modules by name: [cpan://XML::Parser]
	cpan => sub { my $t = shift;
		return 'CPAN', URI->new('https://www.cpan.org/') unless $t=~/\S/;
		return $t, _u_q('https://metacpan.org/search', q=>$t) },

	# https://everything2.com/ By title: [e2://perl], By ID: [e2://13372]
	e2 => sub { my $t = shift;
		return 'Everything2', URI->new('https://everything2.com/') unless $t=~/\S/;
		return 'E2 '.$t, _u_q('https://everything2.com/', node_id=>$t) if $t=~/\A(?!0)[0-9]+\z/;
		return $t, _u_q('https://everything2.com/', node=>$t) },

	# [google://search terms]
	google => sub { my $t = shift;
		return 'Google', URI->new('https://www.google.com/') unless $t=~/\S/;
		return $t, _u_q('https://www.google.com/search', q=>$t) },

	# Wikipedia
	wp => sub { my $t = shift;
		return 'Wikipedia', URI->new('https://en.wikipedia.org/') unless $t=~/\S/;
		return $t, _u_q('https://wikipedia.org/wiki/Special:Search', search=>$t) },

	# [xkcd://208], [xkcd://Bobby Tables]
	xkcd => sub { my $t = shift;
		return 'XKCD', URI->new('https://xkcd.com/') unless $t=~/\S/;
		return 'XKCD '.$t, URI->new('https://xkcd.com/'.$t) if $t=~/\A(?!0)[0-9]+\z/;
		return $t, _u_q('https://www.google.com/search', q=>'site:xkcd.com '.$t, btnI=>undef) },

	# [rfc://822]
	rfc => sub { my $t = shift;
		return 'RFC Archives', URI->new('http://www.faqs.org/rfcs/') unless $t=~/\S/;  # my take
		confess "Bad RFC ".pp($t) unless $t=~/\A(?!0)[0-9]+\z/;
		return 'RFC '.$t, URI->new("http://www.faqs.org/rfcs/rfc$t.html") },

	# [rt://8138], [rt://XML-Parser], [rt://search terms]
	rt => sub { my $t = shift;
		return 'RT.CPAN', URI->new('https://rt.cpan.org/') unless $t=~/\S/;
		confess "Can't handle this RT.CPAN link (yet) ".pp($t) unless $t=~/\A(?!0)[0-9]+\z/;
		return 'RT#'.$t, _u_q('https://rt.cpan.org/Public/Bug/Display.html', id=>$t) },

	# search on acronymfinder.com
	acronym => sub { my $t = shift;
		return 'Acronym Finder', URI->new('https://www.acronymfinder.com/') unless $t=~/\S/;
		return $t, _u_q('https://www.acronymfinder.com/af-query.asp', String=>'exact',
			Find=>'Find', Acronym=>$t) },

	# [isbn://0596000278]
	isbn => sub { my $t = shift;
		return 'ISBN', URI->new('https://isbn.nu/') unless $t=~/\S/;
		confess "Bad ISBN? ".pp($t) unless $t=~/\A(?!0)[0-9]+X?\z/;
		return 'ISBN '.$t, URI->new('https://isbn.nu/'.$t) },

	# https://wiki.c2.com/
	c2 => sub { my $t = shift;
		return 'Wiki Wiki Web', URI->new('https://wiki.c2.com/') unless $t=~/\S/;
		return $t, _u_q('https://www.google.com/search', q=>'site:wiki.c2.com '.$t) },

	# [man://time], [man://time;3]
	man => sub { my $t = shift;
		my @p = split /;/, $t, -1;
		if (@p==1) {
			return $t, _u_q('https://www.google.com/search', q=>$t,
				sitesearch=>'man7.org/linux/man-pages') }
		elsif (@p==2 && $p[1]=~/\A[1-8]\z/) {
			return $p[0].'('.$p[1].')', _u_q('https://www.google.com/search', q=>$p[0],
				sitesearch=>'man7.org/linux/man-pages/man'.$p[1]) }
		else { confess "Can't handle this man:// link (yet): ".pp($t) } },

	# [pad://username], [pad://] (own scratchpad)
	# But we can't get the scratchpad ID by username, so can't handle
	# (but only one tutorial uses this link anyway)
	pad => sub { return '[scratchpad]', $NO_LINK },

	# we can't link to this interactive function
	# (but only one node uses this link anyway)
	msg => sub { return '[msg://'.shift.']', $NO_LINK },

	# not a standard link it seems
	# (but only three sitefaqlets use this link anyway)
	pmdev => sub { return '[pmdev://'.shift.']', $NO_LINK },

	# I don't currently feel like rendering these; they're only used by NodeReaper anyway
	# (note all of these that I have in my nodes currently don't use a "UTC"
	# suffix, which means they'd be interpreted as being in server time...)
	localtime => sub { return '[localtime://'.shift.']', $NO_LINK },

	abbr => sub { confess "I shouldn't be called because abbr:// should get special handling" },
);
$SCHEMES{wikipedia} = $SCHEMES{wp};
$SCHEMES{perldoc} = $SCHEMES{doc};
$SCHEMES{searchcpan} = $SCHEMES{cpan};
$SCHEMES{module} = $SCHEMES{mod};
$SCHEMES{metamod} = $SCHEMES{mod};
#$SCHEMES{metadist} = $SCHEMES{dist};  # currently unused
$SCHEMES{metacpan} = $SCHEMES{cpan};
lock_hash(%SCHEMES);

my ($SCHEMES_RE) = map { qr/$_/i } join '|', map {quotemeta}
	sort { length $b <=> length $a or $a cmp $b } keys %SCHEMES;

# ##### ##### ##### ##### ##### Link Parser ##### ##### ##### ##### #####

use parent 'Token';

# note this needs to handle [doc://$OLD_PERL_VERSION|<c>$]</c>] too
our $PM_LINK_REGEX = qr{
	(?<orig> \[
		\h* (?<left> [^\|\]\v]+? ) \h*
		(?: \| (?<right> <c> (?: (?!</c>) \V )+ </c> | [^\]\v]+ ) )?
	\] )
}msx;

# to be called as PmLink->new({%+}, $lenient) after matching with $PM_LINK_REGEX
sub new {
	croak "Bad number of arguments to new" unless @_==3;
	my ($class, $match, $lenient) = @_;
	$$match{right} = $$match{right};  # force hash key to exist
	croak "Bad keys in match hash ".pp($match) unless
		keys(%$match)==3 && join("\0", sort keys %$match) eq "left\0orig\0right";
	h2o -ro, $match;

	use re '/xms';
	my ($scheme,$target);

	# ##### Various URI-like Links #####
	if ( $match->left =~ m{\A ($SCHEMES_RE) :// (.*) \z}i )
		{ ($scheme, $target) = (lc $1, $2) }

	# ##### Incorrect [Module::Name] Links #####
	elsif ( $lenient && $match->left =~ m{\A [a-z][a-z0-9]+ (?: :: [a-z][a-z0-9]+ )+ \z}i )
		{ $scheme='mod'; $target = $match->left }

	# ##### Links by Node Name from My Nodes #####
	elsif ( $match->left =~ m{\A (?: [a-z0-9\_\ \.\-]+
		| math&ing001 | sm\@sh | \$h4X4_&\#124;=73\}\{ | tye&nbsp;  # fancy usernames
	) \z}i ) { $scheme='node'; $target = $match->left }

	# ##### Lenient Links by Node Name #####
	# (except URI-style links that should have been handled above)
	elsif ( $lenient && $match->left !~ m{\A [a-z0-9\s\_\-\.]+ :/ }i )
		{ $scheme='node'; $target = $match->left }

	# ##### Done #####
	else { croak "Failed to parse link target ".pp($match->left)." in ".pp($match->orig) }

	my $self = $class->SUPER::new(link=>$match->orig);
	$self->{scheme} = $scheme;
	$self->{target} = $target;
	$self->{text} = $match->right;
	return $self;
}

# ##### ##### ##### ##### ##### Link Renderer ##### ##### ##### ##### #####

sub _handle_text {
	croak "Bad number of arguments to _handle_text" unless @_==1;
	# REMEMBER this code structure (parser) is very similar to PmParser::node_tokenizer !
	local $_ = shift;
	return [] unless length;
	my @out;
	use re '/xms';
	pos=undef;
	while (1) {
		if ( m{\G [^<>&]+ }gc ) { push @out, $& }
		elsif ( m{\G <(?<tag>c|code)> (?<code> (?: (?!</\g{tag}>) . )* ) </\g{tag}> }gci )
			{ push @out, '<tt>'.( $+{code} =~ s/[&<>]/$ENT{$&}/gr ).'</tt>' }
		elsif ( m{\G & (?: \#x[0-9a-f]{1,6} | \#[0-9]{1,7} | [a-z]{1,32} ) ; }gci )
			{ push @out, $& }
		elsif ( m{\G (?|
			< ( [a-z]+ | h[1-5] )
				(?: \s+ [a-z_]+ (?: \s* = \s* (?: [a-z0-9_]+ | " [^"]* " | ' [^']* ' ) )? )*
			\s* /? >
			| < / ( [a-z]+ | h[1-5] ) \s* >
		) }gci ) {
			croak "Unknown tag ".pp($&) unless exists $TAGS{lc $1};
			croak "Can't handle in link: ".pp($&) if lc $1 eq 'a';
			push @out, $& }
		elsif ( m{\G [<>&] }gc ) { push @out, $ENT{$&} }
		else { last }
	}
	my $p = pos//0;
    croak "Link parse failed at pos $p at ".pp(substr($_,$p,30).'...')
		if !defined pos || pos!=length;
	#dd $_, \@out if @out>1;  #Debug
	return join '', @out;
}

sub render {
	croak "Bad number of arguments to render" unless @_==1;
	my $self = shift;
	# Special case that's not an <a> and not text-only:
	# [abbr://balloon|text] => <abbr title="balloon">text</abbr>
	if ($self->{scheme} eq 'abbr') {
		confess "abbr without text" unless $self->{text} =~ /\S/;
		return '<abbr title="'.( $self->{target} =~ s/[&<>'"]/$ENT{$&}/gr ).'">'
			._handle_text($self->{text}).'</abbr>';
	}
	my ($sug_text, $href) = $SCHEMES{$self->{scheme}}->($self->{target});
	confess 'Bad scheme handler return value on '.$self->{scheme}.'://'.pp($self->{target})
		.' with '.pp($sug_text, $href)
		unless $sug_text=~/\S/ && ref $href && ( $href == $NO_LINK || $href->isa('URI') );
	my $text = ( defined $self->{text} && $self->{text} =~ /\S/ ) ? _handle_text($self->{text})
		: ( $sug_text =~ s/[&<>'"]/$ENT{$&}/gr );
	my $title = $self->value =~ s/[&<>'"]/$ENT{$&}/gr;
	return $href == $NO_LINK ? '<span title="'.$title.'">'.$text.'</span>'
		: '<a href="'.( $href =~ s/[&<>'"]/$ENT{$&}/gr ).'" target="_blank" '
			.'title="'.$title.'">'.$text.'</a>'
}

# ##### ##### ##### ##### #####

use overload '""' => sub { shift->render };

sub scheme { croak "Bad number of arguments to scheme" unless @_==1; shift->{scheme} }

sub target { croak "Bad number of arguments to target" unless @_==1; shift->{target} }

sub text   { croak "Bad number of arguments to text"   unless @_==1; shift->{text}   }

# spell: ignore CPAN xkcd quotemeta localtime nbsp sitesearch sitefaqlets
# spell: ignore acronymfinder metacpan metadist metamod perldoc perlfaq pmdev searchcpan
1;