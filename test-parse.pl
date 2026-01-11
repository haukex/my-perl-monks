#!/usr/bin/env perl
use warnings;
use 5.014;
use FindBin;
use Getopt::Std 'getopts';
use open qw/:std :utf8/;
use lib $FindBin::Bin;
use PmNode;

sub usage { die "Usage: $0 [-D] NODE_ID\n" }
getopts('D', \my %opts) or usage;
@ARGV==1 or usage;
my $id = shift @ARGV;

my $node = PmNode->load_by_id($id);
say "########## ########## ########## Tokens ########## ########## ########## ##########"
	unless $opts{D};
my $tokens = $node->tokens(!$opts{D});
say "########## ########## ########## Rendered ########## ########## ########## ##########";
say join '', @$tokens;
say "########## ########## ########## XHTML ########## ########## ########## ##########";
print $node->render->toString(1);

# spell: ignore getopt getopts