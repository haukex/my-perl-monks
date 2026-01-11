package Common;
use warnings;
use 5.014;
use Exporter 'import';
use Data::Dump qw/dd pp/;
use Carp qw/carp croak confess/;
use Hash::Util qw/lock_hash_recurse lock_hash/;

our @EXPORT_OK = qw/ %ENT validate_id %NODE_TYPES /;

our %ENT = ( '<'=>'&lt;', '>'=>'&gt;', '&'=>'&amp;', '\''=>'&apos;', '"'=>'&quot;' );
lock_hash(%ENT);

sub validate_id {
	croak "Bad number of arguments to validate_id" unless @_==1 || @_==2;
	my $id = shift;
	my $type = @_ ? shift.' ID' : 'ID';
	confess "Bad $type ".pp($id) unless $id=~/\A(?!0)[0-9]+\z/;
	return $id;
}

our %NODE_TYPES = (
	perlquestion   => { thread=>1, doctext=>1, name=>'Perl Question' },
	perlmeditation => { thread=>1, doctext=>1, name=>'Meditation' },
	perlnews       => { thread=>1, doctext=>1, name=>'Perl News' },
	perltutorial   => { thread=>1, doctext=>1, name=>'Tutorial' },
	monkdiscuss    => { thread=>1, doctext=>1, name=>'PerlMonks Discussion' },
	CUFP           => { thread=>1, doctext=>1, name=>'Cool Use For Perl' },
	quest          => { thread=>1, doctext=>1, name=>'PerlMonks Quest' },
	obfuscated     => { thread=>1, doctext=>1, name=>'Obfuscated Code' },
	sourcecode     => { thread=>1, doctext=>1, name=>'Source Code' },
	poll           => { thread=>1, doctext=>1, name=>'PerlMonks Poll' },
	note           => { thread=>1, doctext=>1, name=>'Reply' },
	user           => { thread=>0, doctext=>1, name=>'User' },
	scratchpad     => { thread=>0, doctext=>1, name=>'User Scratchpad' },
	sitefaqlet     => { thread=>0, doctext=>1, name=>'Site FAQ' },
	# perl -wM5.014 -0777 -ne \
	#   '(/<locked\/>$/ xor /<doctext/ xor />(superdoc|tutlist|fullpage|locked_user)</)||die$ARGV' \
	#   $(find xml -type f)
	# NOTE: Some node types like the following, don't render a doctext in displaytype=xml even
	# though they have useful content. The scraper code now scrapes these as HTML files.
	superdoc       => { thread=>0, doctext=>0 },
	tutlist        => { thread=>0, doctext=>0 },
	# the only node of this type we're currently hitting is 30175, the Newest Nodes XML Generator
	fullpage       => { thread=>0, doctext=>0 },
	# "This node falls below the community's minimum standard of quality."
	# Gets special treatment b/c the entire XML document is just "<locked/>".
	locked         => { thread=>0, doctext=>0 },
);
lock_hash_recurse(%NODE_TYPES);

# spell: ignore CUFP displaytype fullpage monkdiscuss perlmeditation perlnews perlquestion
# spell: ignore perltutorial sitefaqlet superdoc tutlist apos
1;