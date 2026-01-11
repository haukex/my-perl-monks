package PmParser;
use warnings;
use 5.014;
use Token;
use Common qw/ %ENT /;
use Exporter 'import';
use PmHtml qw/ %TAGS /;
use Data::Dump qw/dd pp/;
use Carp qw/croak confess/;
use PmLink qw/ $PM_LINK_REGEX munge_uri /;

our @EXPORT_OK = qw/ node_tokenizer /;

sub handle_anchor {
	confess pp(\@_) unless @_==1;
	my $anc = shift;
	confess pp($anc) unless $anc =~ m{\A
		(?(DEFINE) (?<TARGET> \s+ target \s* = \s* " (?-i: _blank ) " ) )
		<a (?&TARGET)?
			(?: \s+ href  \s* = \s* (["']) (?<href>  [^"']* ) \g-2 )?
			(?: \s+ name  \s* = \s* (["']) (?<name>  [^"']+ ) \g-2 )?
			(?: \s+ rel   \s* = \s* (["']) (?<rel>   [^"']+ ) \g-2 )?
			(?: \s+ title \s* = \s* (["']) (?<title> [^"']+ ) \g-2 )?
		(?&TARGET)? \s* >
	\z}ix;
	my %m = %+;
	# just to prevent conflicts with the anchors we'll use for our stuff:
	confess $anc if $m{name} && $m{name} =~ /\A[0-9]+\z/;
	return '<a'
		# ignoring target= since that gets reset by our renderer anyway
		.( length $m{href}  ?  ' href="'.munge_uri(URI->new($m{href})).'"' : '' )
		.( length $m{name}  ?  ' name="'.$m{name}.'"' : '' )
		.( length $m{rel}   ?   ' rel="'.$m{rel}.'"' : '' )
		.( length $m{title} ? ' title="'.$m{title}.'"' : '' )
		.'>'
}

sub node_tokenizer {
	croak "Bad number of arguments to node_tokenizer" unless @_==2 || @_==3;
	# REMEMBER this code structure (parser) is very similar to PmLink::_handle_text !
	local $_ = shift;
	return [] unless length;
	my $lenient = shift;
	my $debug = shift;
	my @_out;
	my $out = sub {
		confess "bad args" unless @_==1;
		my $tok = shift;
		say $tok->type.': '.pp($tok->value) if $debug;
		push @_out, $tok;
	};
	use re '/xms';
	my $in_blockquote = 0;  # be lenient in <blockquote>s
	my $in_readmore = 0;  # there are some nodes with unclosed <readmore>s we want to fix
	pos=undef;
	while (1) {
		# ##### Plain Text #####
		if ( m{\G [^<>&\[]+ }gc ) { $out->(Token->new(text=>$&)) }

		# ##### Code (inline and blocks) #####
		# I think inline code vs. code blocks can just be identified based on /\n/
		elsif ( m{\G <(?<tag>c|code)> (?<code> (?: (?!</\g{tag}>) . )* ) </\g{tag}> }gci )
			{ $out->(Token->new(code=>$+{code})) }

		# ##### HTML #####
		# Whitespace is *not* allowed: between < and the tag name,
		# between </ and the tag name, and inside the /> token.
		elsif ( m{\G (?|
			< ( [a-z]+ | h[1-5] )
				(?: \s+ [a-z_]+ (?: \s* = \s* (?: [a-z0-9_]+ | " [^"]* " | ' [^']* ' ) )? )*
			\s* /? >
			| < / ( [a-z]+ | h[1-5] ) \s* >
			| & (?: \#x[0-9a-f]{1,6} | \#[0-9]{1,7} | [a-z]{1,32} ) ;
			| <!-- (?: (?!-->) . )* -->
		) }gci ) {
			my ($html, $tag) = ($&, $1);
			# Note the checks against PerlMonks allowed HTML is a multi-stage
			# process, e.g. attributes are checked later via Schema.
			if (defined $tag && !exists $TAGS{lc $tag}) {
				croak "Bad tag ".pp($html) unless $lenient || $in_blockquote;
				$out->(Token->new(text => $html =~ s/[&<>]/$ENT{$&}/gr ));
			}
			elsif ( $html =~ m{\A<a\b}i )
				{ $out->(Token->new( html => handle_anchor($html) )) }
			else {
				$out->(Token->new(html => $html));
				if ( $html =~ m{\A<blockquote\b}i ) { $in_blockquote++ }
				elsif ( $html =~ m{\A<\/blockquote\b}i )
					{ --$in_blockquote >= 0 or croak "too many </blockquote>s found" }
				elsif ( $html =~ m{\A<readmore\b}i ) { $in_readmore++ && croak "nested <readmore>" }
				elsif ( $html =~ m{\A</readmore\b}i )
					{ --$in_readmore >= 0 or croak "too many </readmore>s found" }
			}
		}
		# also fix some people's borked HTML (mostly "<\p>")
		elsif ( $lenient && m{\G < \\ ( [a-z]+ | h[1-5] ) \s* > }gci )
			{ $out->(Token->new(html=>"</$1>")) }

		# ##### Links #####
		# Note that the text portion of links isn't actually parsed and escaped until rendering.
		elsif ( m{\G $PM_LINK_REGEX }gc ) { $out->(PmLink->new({%+}, $lenient)) }

		# ##### Bad HTML and Links #####
		elsif ( ($lenient || $in_blockquote) && m{\G [<>&] }gc )
			{ $out->(Token->new(html=>$ENT{$&})) }
		elsif ( ($lenient || $in_blockquote) && m{\G \[ }gc )
			{ $out->(Token->new(text=>$&)) }

		else { last }
	}  # ##### Done #####
	my $p = pos//0;
    croak "parse failed at pos $p at ".pp(substr($_,$p,10).'...')." in "
		.pp( ($p>12?'...':'').substr($_,( $p<10 ? 0 : $p-10 ),50).'...' )
		if !defined pos || pos!=length;
	croak "Not enough </blockquote>s found" if $in_blockquote;
	$out->(Token->new(html=>'</readmore>')) if $in_readmore;  # close unclosed <readmore>
	$_->isa('Token') or die $_ for @_out;  # double-check
	return \@_out;
}

# spell: ignore readmore
1;