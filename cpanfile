# cpanm --installdeps .
requires 'Data::Dump', '1.25';  # for debugging
requires 'IO::Prompt::Tiny', '0.003';
requires 'Term::ReadPassword::Win32', '0.05';  # works under *NIX too!
requires 'Path::Tiny', '0.150';
requires 'IO::Socket::SSL', '2.085';  # apt list --installed libio-socket-ssl-perl
requires 'Mozilla::PublicSuffix', 'v1.0.7';  # for cookies, see Mechanize docs
requires 'HTTP::CookieJar::LWP', '0.014';
requires 'WWW::Mechanize', '2.20';
requires 'CHI', '0.61';
requires 'WWW::Mechanize::Cached', '1.56';
requires 'URI', '5.34';
requires 'HTML::TableContentParser', '0.305';
requires 'XML::LibXML', '2.0134';  # apt list --installed libxml-libxml-perl
requires 'Util::H2O', '0.24';
requires 'File::Replace', '0.18';
requires 'DateTime', '1.66';
requires 'DateTime::Format::Strptime', '1.80';
# spell: ignore cpanm installdeps libio strptime