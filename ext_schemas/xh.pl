#!/usr/bin/env perl
use warnings;
use 5.014;
use FindBin;
use XML::LibXML ();
use Path::Tiny qw/path/;
use lib path($FindBin::Bin)->parent;
use MyConfig qw/ $XML_PATH /;

# Copy the schema we want to base our own on, removing all annotations and reformatting whitespace.

my $doc = XML::LibXML->load_xml(location=>path($FindBin::Bin)->child('xhtml1-transitional.xsd'));
$_->unbindNode for $doc->findnodes('//xs:annotation');
$doc->normalize;
$_->unbindNode for $doc->findnodes('//text()[normalize-space(.)=""]');
$doc->toFile($XML_PATH->child('pm-xhtml.xsd'), 1);

# spell: ignore findnodes