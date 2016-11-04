#!/usr/bin/perl
package Quartz::Server;
use strict;
use warnings;

use feature 'say';

use IO::Socket::INET;
use threads;
# use threads::shared;
use Thread::Queue;
use Thread::Pool;

# use List::Util 'none';

use Data::Dumper;



our $version_id = 'Quartz/1.0';



sub new {
	my ($class, %opts) = @_;
	my $self = bless {}, $class;

	$self->debug($opts{debug} // 0);
	$self->port($opts{port} // 22222);
	$self->worker_count($opts{worker_count} // 10);
	$self->remote_disabled($opts{remote_disabled} // 0);
	$self->routes({});
	$self->routes_list([]);

	return $self
}

sub debug { @_ > 1 ? $_[0]{debug} = $_[1] : $_[0]{debug} }
sub port { @_ > 1 ? $_[0]{port} = $_[1] : $_[0]{port} }
sub sock { @_ > 1 ? $_[0]{sock} = $_[1] : $_[0]{sock} }
sub dispatched_queue { @_ > 1 ? $_[0]{dispatched_queue} = $_[1] : $_[0]{dispatched_queue} }
sub remote_disabled { @_ > 1 ? $_[0]{remote_disabled} = $_[1] : $_[0]{remote_disabled} }
sub worker_count { @_ > 1 ? $_[0]{worker_count} = $_[1] : $_[0]{worker_count} }
sub thread_pool { @_ > 1 ? $_[0]{thread_pool} = $_[1] : $_[0]{thread_pool} }
sub routes { @_ > 1 ? $_[0]{routes} = $_[1] : $_[0]{routes} }
sub routes_list { @_ > 1 ? $_[0]{routes_list} = $_[1] : $_[0]{routes_list} }



sub route {
	my ($self, $route, @operations) = @_;
	push @{$self->routes_list}, $route unless exists $self->routes->{$route};
	push @{$self->routes->{$route}}, @operations;
	return $self
}



sub start {
	my ($self) = @_;

	warn "ERROR: failed to set up listening socket: $!" and return unless defined $self->sock(IO::Socket::INET->new(
		Proto => 'tcp',
		LocalPort => $self->port,
		Listen => SOMAXCONN,
		Reuse => 1,
	));

	$self->dispatched_queue(Thread::Queue->new);
	$self->thread_pool(Thread::Pool->new({
		workers => $self->worker_count,
		do => sub { return $self->serve_connection(@_) },
	}));

	say 'Quartz server started';

	while (my $socket = $self->sock->accept) {
		my $socket_num = fileno $socket;
		my $peer_ip = join '.', map ord, split '', $socket->peeraddr;
		my $peer_port = $socket->peerport;
		# say "got connection fileno #$socket_num [$peer_ip:$peer_port]";
		$self->thread_pool->job($socket_num, $peer_ip, $peer_port);
		$self->dispatched_queue->dequeue;
	}
}

sub serve_connection {
	my ($self, $socket_num, $peer_ip, $peer_port) = @_;
	# say 'client connected';
	warn "foreign connection blocked" and return if $self->remote_disabled and $peer_ip ne '127.0.0.1';

	open my $socket, "+<&=$socket_num";
	$self->dispatched_queue->enqueue($socket_num);

	my $data;
	{ local $/ = "\r\n\r\n"; $data = <$socket>; }
	# say "got: $data";

	my %request;
	@request{qw/ peer_ip peer_port /} = ($peer_ip, $peer_port);
	$request{raw} = $data;
	my @header_lines = split /\r\n/, $data;
	$request{status_line} = shift @header_lines;

	return unless $request{status_line} =~ /\A(GET|POST) (\S+) (HTTP\/1\.[01])\Z/;
	@request{qw/ method path protocol /} = ($1, $2, $3);
	return unless $request{path} =~ m#\A(/.*?)(\?(.*))?\Z#s;
	@request{qw/ path arg_string /} = ($1, $3);

	my %request_args;
	if (defined $request{arg_string}) {
		%request_args = map { my ($k, $v) = split ('='); ($k => $v) } split '&', $request{arg_string};
	}
	$request{get_args} = \%request_args;

	my %headers;
	foreach my $header (@header_lines) {
		next unless $header =~ /\A([^:]+):\s+(.*)\Z/s;
		push @{$headers{lc $1}}, $2;
	}
	$request{headers} = \%headers;

	if (defined $headers{'content-length'}) {
		my $len = $headers{'content-length'}[0];
		read $socket, my ($buffer), $len;
		$request{body} = $buffer;
		$request{raw} .= "\n$buffer";
	}

	if (defined $headers{'content-type'} and $headers{'content-type'}[0] eq 'application/x-www-form-urlencoded'
		and defined $request{body}) {
		my %form = map { my ($k, $v) = split '='; $k => $v } split '&', $request{body};
		$request{post_form} = \%form;
	}

	$request{cookies} = { map split ('='), map split (/;\s*/), @{$request{headers}{cookie}} } if defined $request{headers}{cookie};

	# say Dumper \%request;	
	my $response = $self->process_request(\%request);

	# say "sending response: [$response]";
	$socket->print($response);
	$socket->close;
}


sub process_request {
	my ($self, $request) = @_;

	my $response;
	local $@;
	eval {
		$response = $self->execute_request($request);
	};
	if ($@) {
		$response = { code => '500', body => "Error: $@" };
	}

	$response = { code => '500', body => 'Error: no response generated' } unless defined $response;
	$response = $self->compile_response($response);
	
	return $response
}


our %statuses = (
	'200' => 'OK',
	'301' => 'Moved Permanently',
	'302' => 'Found',
	'303' => 'See Other',
	'400' => 'Bad Request',
	'403' => 'Forbidden',
	'404' => 'Not Found',
	'500' => 'Internal Server Error',
);

sub compile_response {
	my ($self, $response) = @_;

	# if a subroutine wants to return a completely custom response, do that
	return $response->{custom} if defined $response->{custom};

	# default/important values
	$response->{code} //= '200';
	$response->{body} //= $statuses{$response->{code}} // '';
	$response->{headers}{'Content-Length'} //= length ($response->{body});
	$response->{headers}{'Connection'} //= 'close';
	if (defined $response->{headers}{'Server'}) {
		$response->{headers}{'Server'} = "$version_id $response->{headers}{'Server'}";
	} else {
		$response->{headers}{'Server'} = $version_id;
	}
	
	# compile some stuff
	my $headers = '';
	$headers = (join "\r\n", map "$_: $response->{headers}{$_}", keys %{$response->{headers}})."\r\n"
		if 0 < keys %{$response->{headers}};
	my $cookies = '';
	$cookies = (join "\r\n", map "Set-Cookie: $_=$response->{cookies}{$_}; Path=/; HttpOnly", keys %{$response->{cookies}})."\r\n"
		if 0 < keys %{$response->{cookies}};
	# put it all together
	my $msg = $response->{message} // $statuses{$response->{code}} // '';
	return "HTTP/1.1 $response->{code} $msg\r\n$headers$cookies\r\n$response->{body}"
}


sub execute_request {
	my ($self, $request) = @_;

	my $response;

	my @routes = grep $request->{path} =~ /\A$_\Z/s, @{$self->routes_list};
	# say "matches routes: ", join ',', @routes;
	if (@routes) {
		foreach my $route (@routes) {
			$request->{path} =~ /\A$route\Z/s;
			my %route_args = %+;
			$request->{route_args} = \%route_args;
			foreach my $operation (@{$self->routes->{$route}}) {
				$response = $operation->($request, $response);
				$response = { code => '200', body => $response } if defined $response and 'HASH' ne ref $response;
			}
		}
	} else {
		$response = { code => '404', body => 'Error: not found' };
	}

	return $response
}



1;
