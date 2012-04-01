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

  my $message = $self->{frame}->new($data);

  $self->{handle}->push_write($message->to_bytes);
};

sub on_message {
  my $self = shift;
  my $handler = shift;
  $self->{on_message} = $handler;
};

package WebSocket::Server;

sub new {
    my $class = shift;

    my $self = { _connections => [] };
    bless($self, $class);
    return $self;
};

sub add_connection {
    my $self = shift;
    my $conn = shift;
    push @{$self->{_connections}}, $conn;
};

sub connections {
  my $self = shift;
  my $conn = shift;
  @{$self->{_connections}};
}

sub on_listen {
  my $self = shift;
  my $handler = shift;
  $self->{on_listen} = $handler;
};

sub on_connection {
    my $self    = shift;
    my $handler = shift;
    $self->{on_connection} = $handler;
};

sub on_close {
    my $self    = shift;
    my $handler = shift;
    $self->{on_close} = $handler;
};

sub broadcast {
    my $self    = shift;
    my $message = shift;
    foreach my $connection ($self->connections) {
        $connection->send($message);
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
            frame  => $frame
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

            # FIXME: $self->{connections}.remove($connection);
            $self->{on_close}($connection)
        });

        $handle->on_read(sub {
            my $handle = shift;

            my $chunk = $handle->{rbuf};
            $handle->{rbuf} = undef;

            if (!$handshake->is_done) {
                $handshake->parse($chunk);
                if ($handshake->is_done) {
                    $handle->push_write($handshake->to_string);
                    
                    $self->add_connection($connection);

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

1;
