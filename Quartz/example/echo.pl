#!/usr/bin/env perl
use strict;
use warnings;

use Quartz::Server;


my $server = Quartz::Server->new;

$server->route('/.*', sub {
	my ($q, $r) = @_;
	$r->{body} = $q->{raw};
});
$server->start;

