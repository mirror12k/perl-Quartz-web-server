#!/usr/bin/env perl
use strict;
use warnings;

use Quartz::Server;
use Quartz::Sand;

use Sugar::IO::File;
use Sugar::IO::Dir;


my $server = Quartz::Server->new;
$server->route('/.*', sub {
	my ($req, $res) = @_;

	my $path = '.' . $req->{path};
	$path =~ s#/\.?/#/#g;
	$path =~ s#/[^/]+/\.\.## while $path =~ m#/[^/]+/\.\.#;
	$path =~ s#(/|\A)\.\.##g;

	# warn "debug path: $path\n";
	if (-e $path) {
		if (-f _) {
			my $data = Sugar::IO::File->new($path)->read;
			if (defined $data) {
				$res->{code} = 200;
				$res->{body} = $data;
				$res->{headers}{'Content-Type'} = 'text/plain';
			} else {
				$res->{code} = 500;
			}
		} elsif (-d _) {
			$path .= '/' unless $path =~ /\/\Z/;

			my @list = map $_->name, Sugar::IO::Dir->new($path)->list;

			$res->{code} = 200;
			$res->{body} = '<html><body>' .
				(join '', map "<a href='" . (-d "$path$_" ? "$_/" : "$_") . "'>" . (-d _ ? "$_/" : "$_") . "</a><br>", @list) .
				'</body></html>';
		} else {
			$res->{code} = 403;
		}
		return $res
	} else {
		$res->{code} = 404;
	}
	return $res
});


$server->route('/.*(console_logging_route)?' => console_logging);
$server->route('/.*(route_gzip)?' => route_gzip);
$server->start;
