package Token;
use warnings;
use 5.014;
use Common qw/ %ENT /;
use Data::Dump qw/dd pp/;
use Carp qw/carp croak confess/;

sub new {
	croak "Bad number of arguments to new" unless @_==3;
	my ($class,$type,$value) = @_;
	# note there isn't really a difference between text and html nodes
	croak "Bad type ".pp($type) unless $type=~/\A(?:text|html|code|link)\z/;
	my $self = bless { type => $type, value => $value }, $class;
	croak "Links must be of type PmLink" if $type eq 'link' && !$self->isa('PmLink');
	return $self;
}

use overload '""' => sub {
	my $self = shift;
	# convert <readmore> and <spoiler> into <details>
	if ( $self->{type} eq 'html' && $self->{value} =~ m{\A <readmore (.*) > \z}xi ) {
		$1 =~ m{ (?: title \s* = \s* " ([^"]+) " )? \s* }xi or die pp($1);
		my $t = ($1//'') =~ s/\A\s+|\s+\z//gr;
		return '<details class="readmore" open="open"><summary>'
			.(length $t ? $t : 'Read more...').'</summary>'
	}
	if ( $self->{type} eq 'html' && $self->{value} =~ m{\A <spoiler \s* > \z}xi )
		{ return '<details class="spoiler"><summary>Spoiler</summary>' }
	if ( $self->{type} eq 'html' && $self->{value} =~ m{\A </ (?:readmore|spoiler) \s* > \z}xi )
		{ return '</details>' }
	elsif ( $self->{type} eq 'text' || $self->{type} eq 'html' ) { return $self->{value} }
	elsif ( $self->{type} eq 'code' ) {
		my $esc = $self->{value} =~ s/[&<>]/$ENT{$&}/gr;
		return $self->{value}=~/\v/ ? "<pre>$esc</pre>" : "<tt>$esc</tt>";
	} else { confess(pp($self->{type})) }
};

sub type  { croak "Bad number of arguments to type"  unless @_==1; shift->{type}  }

sub value { croak "Bad number of arguments to value" unless @_==1; shift->{value} }

# spell: ignore readmore
1;