package Quartz::Silica;
use strict;
use warnings;
use base 'Exporter';

use DBM::Deep;
use Math::Random::Secure qw/ irand /;

our @EXPORT = qw/
silica_database
silica_session
/;



sub generate_session_id {
	return join '', map unpack ('H*', chr), map rand(256), 1 .. 16;
}



sub silica_database {
	my %args = @_;
	$args{file} //= 'silica.db';
	$args{db} //= DBM::Deep->new(
	      file => $args{file},
	      locking => 1,
	      autoflush => 1,
      );
	return sub {
		my ($req, $res) = @_;
		$req->{db} = $args{db};
		return $res
	}
}

sub silica_session {
	return sub {
		my ($req, $res) = @_;
		die 'Error: database not loaded!' unless defined $req->{db};
		my $session_id = $req->{cookies}{Si_session};
		if (not defined $session_id) {
			$session_id = generate_session_id;
			$res->{cookies}{Si_session} = $session_id;
			$req->{db}{silica_sessions}{$session_id} = {};
			warn "loaded session";
		}
		$req->{session} = $req->{db}{silica_sessions}{$session_id};
		return $res
	}
}



1;
