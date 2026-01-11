#!/usr/bin/env perl
use warnings;
use 5.014;
use FindBin;
use open qw/:std :utf8/;
use lib $FindBin::Bin;
use PmNode;

die "Usage: $0 NODE_ID\n" unless @ARGV==1;
my $id = shift @ARGV;

my $doctext = PmNode->load_by_id($id)->doctext;
die "No doctext in node $id\n" unless defined $doctext;
print $doctext;
