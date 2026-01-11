#!/usr/bin/env perl
use warnings;
use 5.014;
use FindBin;
use List::Util qw/max/;
use Path::Tiny qw/path/;
use Data::Dump qw/dd pp/;
use File::Replace 'replace3';
use HTML::TableContentParser ();
use lib $FindBin::Bin;
use MyConfig qw/ $XML_PATH /;

# This script generates PmHtml.pm

# Node 29281 is Perl Monks Approved HTML tags
my $file = $XML_PATH->child('1')->child('29281.html');

my $tables = HTML::TableContentParser->new->parse($file->slurp);
die "More than one table found\n" unless @$tables==1;
my $table = $tables->[0];

my %tags;
for my $ri (0..$#{ $table->{rows} }) {
	next if !$ri && $table->{rows}[$ri]{headers} && !$table->{rows}[$ri]{cells};
	my @row = map {$_->{data}} @{ $table->{rows}[$ri]{cells} };
	die "Bad row ".pp(@row) unless @row==2;
	my ($tag) = $row[0]=~/\A([a-z]+[1-6]?)(?:<sup>[0-9]<\/sup>)?\z/ or die pp($row[0]);
	my $att;
	if (!length $row[1]) { $att = [] }  # only <summary>, I'm guessing "(none)"
	elsif ($row[1] eq '(none)') { $att = [] }
	elsif ($row[1] eq '/') { $att = undef }
	else {
		die "Bad attrs ".pp($row[1]) unless $row[1]=~/\A[a-z]+(?:, [a-z]+)*\z/;
		$att = [ sort split /,\h*/, $row[1] ];
		my %seen; $seen{$_}++ and die "Dupe $_" for @$att;
	}
	die "Duplicate tag $tag" if $tags{$tag};
	$tags{$tag} = $att;
}

my (undef,$fh,$repl) = replace3(path($FindBin::Bin)->child('PmHtml.pm'));
select($fh);
print <<"EOF";
package PmHtml;
use warnings;
use 5.014;
use Exporter 'import';
use Hash::Util qw/lock_hash_recurse/;

# DO NOT EDIT, this file is overwritten by $FindBin::Script

our \@EXPORT_OK = qw/ \%TAGS /;

# Scraped from https://perlmonks.org/?node_id=29281
our \%TAGS = (
EOF
my $pad = max( map {length} keys %tags );
printf "\t%-*s => %s,\n", $pad, $_, !defined $tags{$_} ? 'undef'
	: @{$tags{$_}} ? '{ '.join(', ',map {"$_=>1"} @{$tags{$_}}).' }' : '{}'
		for sort keys %tags;
print <<"EOF";
);
lock_hash_recurse(\%TAGS);

EOF
print "# spell: ignore bgcolor cellspacing colgroup readmore rowspan
1;";
$repl->finish;
