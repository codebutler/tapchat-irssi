#
# websocket_server.pm - Simple websocket server.
#
# Copyright (C) 2012 Eric Butler <eric@codebutler.com>
#
# This file is part of Irseas.
#
# Irseas is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Irseas is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Irseas.  If not, see <http://www.gnu.org/licenses/>.

use strict;
use warnings;
use 5.6.1;

use AnyEvent::Socket;
use AnyEvent::Handle;
use AE;

use Protocol::WebSocket::Handshake::Server;
use Protocol::WebSocket::Frame;

use Data::ArrayList;

package WebSocket::Server::Connection;

sub new {
    my $class  = shift;
    my %params = @_;

    bless {
        %params
    }, $class;
};

sub send {
  my $self = shift;
  my $data = shift;

  my $message = $self->{frame}->new(
      max_payload_size => 99999999999,
      buffer           => $data
  );

  $self->{handle}->push_write($message->to_bytes);
};

sub on_message {
  my $self = shift;
  my $handler = shift;
  $self->{on_message} = $handler;
};

package WebSocket::Server;

use URI::Query;

sub new {
    my $class = shift;
    my %params = @_;

    bless {
        connections => new Data::ArrayList,
        %params
    }, $class;
};

sub connections {
    my $self = shift;
    return $self->{connections};
}

sub broadcast {
    my $self    = shift;
    my $message = shift;

    unless ($self->connections->isEmpty) {
        my $iter = $self->connections->listIterator();
        while ($iter->hasNext) {
            my $connection = $iter->next;
            $connection->send($message);
        }
    }
};

my $handles = [];

sub listen {
    my $self = shift;
    my $port = shift;

    my $tcp_server = AnyEvent::Socket::tcp_server undef, $port, sub {
        my $fh   = shift;
        my $host = shift;
        my $port = shift;

        my $handshake = Protocol::WebSocket::Handshake::Server->new;
        my $frame     = Protocol::WebSocket::Frame->new;

        my $cert_file = $ENV{HOME} . "/.irssi/irseas.pem";

        my $handle = new AnyEvent::Handle
            fh      => $fh,
            tls     => "accept",
            tls_ctx => { cert_file => $cert_file };

        my $connection = WebSocket::Server::Connection->new(
            handle => $handle,
            frame  => $frame,
            host   => $host,
            port   => $port
        );

        push(@$handles, $handle);

        $handle->on_error(sub {
            my $handle = shift;
            my $fatal  = shift;
            my $msg    = shift;

            # FIXME:
            Irssi::print("Error!!! $fatal $msg");

            $handle->destroy;
        });

        $handle->on_eof(sub {
            my $handle = shift;
            my $fatal  = shift;
            my $msg    = shift;

            $handle->destroy;

            my $idx = $self->connections->indexOf(sub { $_ eq $connection });
            if ($idx >= 0) {
                $self->connections->remove($idx);
                $self->{on_close}($connection)
            }
        });

        $handle->on_read(sub {
            my $handle = shift;

            my $chunk = $handle->{rbuf};
            $handle->{rbuf} = undef;

            if (!$handshake->is_done) {
                $handshake->parse($chunk);
                if ($handshake->is_done) {

                    my $resource  = $handshake->res->resource_name;
                    my $query_str = substr($resource, index($resource, '?') + 1);
                    my $query     = URI::Query->new($query_str);
                    my $password  = $query->hash->{password};

                    if (!$self->{on_verify_password}($password)) {
                        my $response = "HTTP/1.1 403 NOPE\x0d\x0a\x0d\x0a";
                        $handle->push_write($response);
                        $handle->push_shutdown;
                        return;
                    }

                    $handle->push_write($handshake->to_string);
                    
                    $self->connections->add($connection);

                    $self->{on_connection}($connection);
                    return;
                }
            }

            $frame->append($chunk);

            while (my $message = $frame->next) {
              $connection->{on_message}($message);
            }

        });
    },
    sub {
      my ($fh, $host, $port) = @_;
      $self->{on_listen}($port);
    };

    $self->{tcp_server} = $tcp_server;
};

sub stop {
    my $self = shift;

    $handles = [];
    $self->{tcp_server} = undef;
};

1;
