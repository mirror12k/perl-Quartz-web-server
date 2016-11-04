#!/usr/bin/env perl
use strict;
use warnings;

use Quartz::Server;
use Quartz::Amethyst;
use Quartz::Sand;




my $server = Quartz::Server->new;
$server->route('/test/.*' => amethyst_directory(route => '/test/', directory => 'www', suffix => '.am'), \&amethyst_compress);

$server->route('/u/(?<name>\w+)/(?<key1>[a-fA-F0-9]+)_(?<key2>[a-fA-F0-9]+)/' => amethyst_file('www/route_args.am'));
$server->route('/.*(console_logging_route)?' => console_logging);
$server->start;



