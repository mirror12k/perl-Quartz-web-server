#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';

use Quartz::Server;



my $srv = Quartz::Server->new;

$srv->start;

