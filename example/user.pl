#!/usr/bin/env perl
use strict;
use warnings;

use Quartz::Server;
use Quartz::Amethyst;
use Quartz::Sand;
use Quartz::Silica;





my $server = Quartz::Server->new;
$server->route('/.*' => silica_database(file => 'user.db'), silica_session);
$server->route('/user/.*' => amethyst_directory(route => '/user', directory => 'user', suffix => '.am'));
$server->route('/.*(amethyst_compress)?' => \&amethyst_compress);
$server->route('/.*(console_logging_route)?' => console_logging);
$server->start;
