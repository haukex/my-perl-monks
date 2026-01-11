package PmHtml;
use warnings;
use 5.014;
use Exporter 'import';
use Hash::Util qw/lock_hash_recurse/;

# DO NOT EDIT, this file is overwritten by allowed-html.pl

our @EXPORT_OK = qw/ %TAGS /;

# Scraped from https://perlmonks.org/?node_id=29281
our %TAGS = (
	a          => { class=>1, href=>1, name=>1, rel=>1, target=>1, title=>1 },
	abbr       => { title=>1 },
	b          => {},
	big        => {},
	blockquote => { cite=>1, class=>1, dir=>1, lang=>1 },
	br         => undef,
	c          => {},
	caption    => { class=>1 },
	center     => {},
	code       => {},
	col        => { align=>1, class=>1, col=>1, span=>1, width=>1 },
	colgroup   => { align=>1, class=>1, col=>1, span=>1, width=>1 },
	dd         => {},
	del        => { cite=>1, class=>1, datetime=>1 },
	details    => { open=>1 },
	div        => { class=>1 },
	dl         => {},
	dt         => {},
	em         => {},
	font       => { class=>1, color=>1, size=>1 },
	h1         => { align=>1, class=>1 },
	h2         => { align=>1, class=>1 },
	h3         => { align=>1, class=>1 },
	h4         => { align=>1, class=>1 },
	h5         => { align=>1, class=>1 },
	h6         => { align=>1, class=>1 },
	hr         => undef,
	i          => {},
	ins        => { cite=>1, class=>1, datetime=>1 },
	li         => { value=>1 },
	ol         => { start=>1, type=>1 },
	p          => { align=>1, class=>1 },
	pre        => { class=>1 },
	readmore   => { title=>1 },
	small      => {},
	span       => { class=>1, title=>1 },
	spoiler    => {},
	strike     => {},
	strong     => {},
	sub        => {},
	summary    => {},
	sup        => {},
	table      => { bgcolor=>1, border=>1, cellpadding=>1, cellspacing=>1, class=>1, width=>1 },
	tbody      => { align=>1, bgcolor=>1, class=>1, colspan=>1, height=>1, rowspan=>1, valign=>1, width=>1 },
	td         => { align=>1, bgcolor=>1, class=>1, colspan=>1, height=>1, rowspan=>1, valign=>1, width=>1 },
	tfoot      => { align=>1, bgcolor=>1, class=>1, colspan=>1, height=>1, rowspan=>1, valign=>1, width=>1 },
	th         => { align=>1, bgcolor=>1, class=>1, colspan=>1, height=>1, rowspan=>1, valign=>1, width=>1 },
	thead      => { align=>1, bgcolor=>1, class=>1, colspan=>1, height=>1, rowspan=>1, valign=>1, width=>1 },
	tr         => { align=>1, bgcolor=>1, class=>1, colspan=>1, height=>1, valign=>1, width=>1 },
	tt         => { class=>1 },
	u          => {},
	ul         => { type=>1 },
	wbr        => undef,
);
lock_hash_recurse(%TAGS);

# spell: ignore bgcolor cellspacing colgroup readmore rowspan
1;