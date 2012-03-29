#
# irseas.pl - Irseas plugin for Irssi
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

use Cwd;
use File::Basename;
use lib dirname(Cwd::abs_path(__FILE__));

use JSON;
use Data::Dumper;
use Irssi;
use Irssi::TextUI;
use Mojo::Server::Morbo;
use threads;

use websocket_server;

sub send_message {
    my $connection = shift;
    my $message = shift;

    my $json = encode_json($message);

    Irssi::print("Sending message: $json");

    $connection->send($json);
}

sub make_server {
    my $server = shift;
    { 
        "type" => "makeserver", 
        "cid"  => $server->{_irssi},
        "name" => $server->{chatnet}
    };
}

sub make_buffer {
    my $type  = shift;
    my $item  = shift;
    my $extra = shift || {};
    {
        "type"        => "makebuffer",
        "buffer_type" => $type,
        "cid"         => $item->{server}->{_irssi},
        "bid"         => $item->{_irssi},
        %$extra
    };
}

sub make_channel_buffer {
    my $channel = shift;
    make_buffer("channel", $channel, {
        "joined" => ($channel->{joined} == 1) ? JSON::true : JSON::false
    });
}

sub make_query_buffer {
    my $query = shift;
    make_buffer("conversation", $query);
}

sub make_channel_init {
    my $channel = shift;

    my $members = [];
    foreach my $nick ($channel->nicks) {
        push(@$members, {
            "nick"      => $nick->{nick},
            "realname"  => $nick->{realname},
            "usermask"  => $nick->{host}
        });
    }

    {
        "type"   => "channel_init",
        "joined" => JSON::true,
        "chan"   => $channel->{name},
        "mode"   => $channel->{mode},
        "topic"  => {
            "topic_text"   => $channel->{topic},
            "topic_time"   => $channel->{topic_time},
            "topic_author" => $channel->{topic_by}
        },
        "members" => $members
    };
}

sub send_lines {
    my $connection = shift;
    my $buffer = shift;

    my $window = $buffer->window();
    my $view   = $window->view();
    my $line   = $view->get_lines();

    while (defined $line) {
        send_message($connection, {
            "cid"  => $buffer->{server}->{_irssi},
            "bid"  => $buffer->{_irssi},
            "type" => "channel_notice",
            "eid"  => $line->{info}->{_irssi},
            "time" => $line->{info}->{time},
            "msg"  => $line->get_text(0)
        });
        $line = $line->next;
    }
}

sub send_backlog {
    my $connection = shift;

    foreach my $server (Irssi::servers) {
        send_message($connection, make_server($server));
    }

    foreach my $channel (Irssi::channels) {
        send_message($connection, make_channel_buffer($channel));
        send_message($connection, make_channel_init($channel));
        send_lines($connection, $channel);
    }

    foreach my $query (Irssi::queries) {
        send_message($connection, make_buffer("conversation", $query));
        send_lines($connection, $query);
    }
}

my $server = new WebSocket::Server;

$server->on_connection(sub {
    my $connection = shift;

    $connection->on_message(sub {
        my $message = shift;
        print("on message! $message");
    });

    print("on connection! $connection");

    send_backlog($connection);
});

$server->on_close(sub {
    my $connection = shift;
    print("on close!");
});

$server->listen(3000);

sub event_message_public {
    my $irssi_server = shift;
    my $msg = shift;
    my $nick = shift;
    my $address = shift;
    my $target = shift;

    Irssi::print("Got message! $msg");
    $server->broadcast(encode_json({ "type"=> "message", "msg" => $msg}));
};

Irssi::signal_add_last("message public", "event_message_public");
