package Quartz::Sand;
use strict;
use warnings;
use base 'Exporter';

use Term::ANSIColor;
use Gzip::Faster;
use List::Util 'any';

our @EXPORT = qw/
route_gzip
console_logging
/;



sub route_gzip {
	return sub {
		my ($req, $res) = @_;
		if (defined $res and exists $res->{body} and not exists $res->{headers}{'Content-Encoding'}) {
			if (any { $_ eq 'gzip' } map s/\A\s*(.*?)\s*\Z/$1/rs, split ',', join ',', @{$req->{headers}{'accept-encoding'}}) {
				$res->{body} = gzip $res->{body};
				$res->{headers}{'Content-Encoding'} = 'gzip';
			}
		}
		return $res
	}
}

sub console_logging {
	my $count = 0;
	return sub {
		my ($req, $res) = @_;
		print color('bold white'), '[', $count++, '] ', color ('bright_green'), $req->{method}, ' ', color ('bright_yellow'), $req->{path}, ' ';
		if (defined $res) {
			if (300 > int ($res->{code} // 200)) {
				print color('bright_blue'), $res->{code} // '200';
			} elsif (400 > int ($res->{code} // 200)) {
				print color('bright_cyan'), $res->{code};
			} else {
				print color('bright_red'), $res->{code};
			}
		} else {
			print color('bright_red'), '404';
		}
		print color ('reset');
		print "\n";
		return $res
	}
}



1;
