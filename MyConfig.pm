package MyConfig;
use warnings;
use 5.014;
use Exporter 'import';
use Path::Tiny qw/path/;
use Hash::Util qw/lock_hash_recurse/;

our @EXPORT_OK = qw/ $BASE_URL $XML_PATH $PATCH_PATH $CACHE_PATH $OUT_PATH $STYLESHEET %ALSO /;

my $base = path(__FILE__)->parent;

our $BASE_URL = 'https://perlmonks.org/';

our $XML_PATH = $base->child('xml');
our $PATCH_PATH = $base->child('patches');
our $CACHE_PATH = $base->child('cache');
our $OUT_PATH = $base->child('output');
our $STYLESHEET = $base->child('style.css');

my @also = map { /^\s*([-+rh](?!0)[0-9]+)\s*(?:#.*)?$/ || die $_; $1 }
	grep { /\S/ && !m/^\s*#/ } $base->child('also.txt')->lines_utf8({chomp=>1});
our %ALSO = (
	add  => { map {(s/^\+//r => 1)} grep {/^\+/} @also },
	skip => { map {(s/^\-//r => 1)} grep {/^\-/} @also },
	rend => { map {(s/^r//r  => 1)} grep {/^r/ } @also },
	html => { map {(s/^h//r  => 1)} grep {/^h/ } @also },
);
lock_hash_recurse(%ALSO);

1;