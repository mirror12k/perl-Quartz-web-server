#!/usr/bin/env perl
package Quartz::Amethyst;
use strict;
use warnings;
use base 'Exporter';

use feature 'say';

use Quartz::Server;
use Quartz::Sand;
use Sugar::IO::File;

our @EXPORT = qw/
amethyst_file
amethyst_directory
amethyst_compress
/;


our $version_id = 'Amethyst/1.0';

our %compiled_file_cache;

sub compile_code {
	my ($filetext) = @_;
	# say "got file: [$filetext]";
	my $allcode = '
	use subs "echo";
	sub {
		my $request = shift;
		local *echo = shift;
		local *redirect = shift;
	' . "\n";
	while ($filetext =~ /\G<\$(.*?)\$>|(.*?)((?=<\$)|\Z)/sg) {
		my ($code, $text) = ($1, $2);
		if (defined $code) {
			$allcode .= "$code;\n";
		} else {
			$text =~ s/\\/\\\\/g;
			$text =~ s/'/\\'/g;
			$allcode .= "echo ('$text');\n";
		}
	}
	$allcode .= '}';

	local $@;
	my $compiled = eval $allcode; # compile the subroutine and get a reference to it
	return undef, $@ if $@;

	return $compiled
}

sub evaluate {
	my ($compiled, $req, $res) = @_;

	my $output = '';
	open my $echo_handle, '>>', \$output;
	my $echo_ref = sub { $echo_handle->print(@_) };
	my $redirect_ref = sub {
		my ($location, $code) = @_;
		$res->{headers}{Location} = $location;
		$res->{code} = $code // '302';
	};

	$compiled->($req, $echo_ref, $redirect_ref);

	$res->{code} //= '200';
	$res->{body} = $output;

	return $res
}

sub amethyst_eval_file {
	my ($filepath, $req, $res) = @_;
	my $file = Sugar::IO::File->new($filepath);
	if (exists $compiled_file_cache{"$filepath"}) {
		$res = evaluate($compiled_file_cache{"$filepath"}, $req, $res);
	} elsif ($file->exists) {
		my ($code, $error) = compile_code($file->read);
		if (defined $code) {
			$compiled_file_cache{"$filepath"} = $code;
			$res = evaluate($code, $req, $res);
		} else {
			$res->{code} = '500';
			$res->{body} = "Compilation error: $error";
		}
	} else {
		$res->{code} = '404';
	}
	return format_response ($res)
}

sub format_response {
	my $response = shift;
	$response->{headers}{'Content-Type'} //= 'text/html' if defined $response->{body}
		and $response->{body} =~ /\A(<html|<!doctype html)/i;
	$response->{headers}{'Content-Type'} //= 'text/plain';
	$response->{headers}{'Server'} //= $version_id;
	return $response
}



sub amethyst_compress {
	my ($request, $code) = @_;
	if (defined $code and defined $code->{body} and $code->{body} =~ /\A<!doctype html>/i) {
		$code->{body} =~ s/\s+</</gs;
		$code->{body} =~ s/>\s+/>/gs;
	}
	return $code
}

sub amethyst_directory {
	my %args = @_;
	$args{route} //= '/';
	$args{directory} //= '.';
	$args{suffix} //= '';
	return sub {
		my ($req, $res) = @_;
		my $filepath = $req->{path} =~ s/\A$args{route}//sr;
		$filepath = "$filepath/index" if $filepath eq '' or $filepath =~ /\/\Z/;
		$filepath =~ s#/\.?/#/#g;
		$filepath =~ s#/[^/]+/\.\.## while $filepath =~ m#/[^/]+/\.\.#;
		$filepath =~ s#(/|\A)\.\.##g;
		$filepath = "/$filepath" unless $filepath =~ /\A\//;

		return amethyst_eval_file("$args{directory}$filepath$args{suffix}", $req, $res)
	}
}

sub amethyst_file {
	my ($filepath) = @_;
	return sub { amethyst_eval_file ($filepath, @_) }
}



sub main {
	my ($dirpath, $suffix) = @_;
	die "amethyst file directory required" unless defined $dirpath;
	$suffix //= '.am';

	my $server = Quartz::Server->new;
	$server->route('/.*' => amethyst_directory(route => '/', directory => "$dirpath", suffix => "$suffix"), \&amethyst_compress);
	$server->route('/.*(console_logging_route)?' => console_logging);
	$server->start;

}



caller or main(@ARGV);
