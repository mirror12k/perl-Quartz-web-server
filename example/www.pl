#!/usr/bin/env perl
use strict;
use warnings;

use Quartz::Server;
use Quartz::Amethyst;




my $server = Quartz::Server->new;
$server->route('/test/.*' => amethyst_directory(route => '/test/', directory => 'www', suffix => '.am'), \&amethyst_compress);

$server->route('/u/(?<name>\w+)/(?<key1>\w)_(?<key2>\w)/' => amethyst_file('www/route_args.am'));
# $server->route('/.*(console_logging_route)?' => console_logging);
$server->start;



