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


sub make_server {
    my $server = shift;

    # {"bid":-1,"eid":-1,"type":"makeserver","time":-1,"highlight":false,"num_buffers":35,"cid":2283,"name":"SWN","nick":"fR","nickserv_nick":"fR_","nickserv_pass":"","realname":"fR","hostname":"irc.seattlewireless.net","port":7000,"away":"","disconnected":false,"ssl":true,"server_pass":""},

    { 
        "type"         => "makeserver", 
        "cid"          => $server->{_irssi},
        "name"         => $server->{chatnet},
        "nick"         => $server->{nick},
        "realname"     => $server->{realname},
        "hostname"     => $server->{address},
        "port"         => $server->{port},
        "disconnected" => ($server->{connected} == 1) ? JSON::false : JSON::true,
        "ssl"          => JSON::false # FIXME
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
        "name"        => $item->{name},
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
        "cid"    => $channel->{server}->{_irssi},
        "bid"    => $channel->{_irssi},
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

sub send_header {
    my $connection = shift;
    send_message($connection, {
        "type"          => "header",
        "time"          => time,
        "highlight"     => JSON::false,
        "idle_interval" => 29000 # FIXME
    });
}

sub send_backlog {
    my $connection = shift;

    foreach my $server (Irssi::servers) {
        send_message($connection, make_server($server));
    }

    foreach my $channel (Irssi::channels) {
        send_message($connection, make_channel_buffer($channel));
        send_message($connection, make_channel_init($channel));
        # send_lines($connection, $channel);
    }

    foreach my $query (Irssi::queries) {
        send_message($connection, make_query_buffer($query));
        # send_lines($connection, $query);
    }

    send_message($connection, {
        "type" => "backlog_complete"
    });
}

my $ws_server = new WebSocket::Server;

$ws_server->on_connection(sub {
    my $connection = shift;

    $connection->on_message(sub {
        my $message = shift;
        Irssi::print("on message! $message");
    });

    Irssi::print("on connection! $connection");

    send_header($connection);
    send_backlog($connection);
});

$ws_server->on_close(sub {
    my $connection = shift;
    Irssi::print("on close!");
});

my $eid = 0;

sub prepare_message {
    my $message = shift;

    $message->{eid} = $eid; # FIXME
    $message->{time} = time;
    $message->{highlight} = JSON::false;

    $eid ++;

    return $message;
}

sub send_message {
    my $connection = shift;
    my $message    = shift;

    $connection->send(
        encode_json(
            prepare_message($message)
        )
    );
}

sub broadcast {
    my $message = shift;

    $ws_server->broadcast(
        encode_json(
            prepare_message($message)
        )
    );

    # FIXME add_to_backlong
};

Irssi::signal_add_last("chatnet create", sub {
    my $chatnet = shift;

    broadcast(make_server($chatnet));
});

Irssi::signal_add_last("chatnet destroyed", sub {
    # FIXME
});

Irssi::signal_add_last("channel created", sub {
    my $channel = shift;

    broadcast(make_channel_buffer($channel));
    broadcast(make_channel_init($channel));
});

Irssi::signal_add_last("channel destroyed", sub {
    my $channel = shift;

    broadcast({
        type => "delete_buffer",
        cid  => $channel->{server}->{_irssi},
        bid  => $channel->{_irssi}
    });
});

Irssi::signal_add_last("query created", sub {
    my $query = shift;

    broadcast(make_query_buffer($query));
});

Irssi::signal_add_last("query destroyed", sub {
    # FIXME
});

Irssi::signal_add_last("query nick changed", sub {
    # FIXME
});

Irssi::signal_add_last("server connecting", sub {
    # FIXME
    # {"bid":18665,"eid":4134,"type":"connecting","time":1332770242,"highlight":false,"chan":"*","hostname":"irc.seattlewireless.net","port":7000,"cid":2283,"ssl":true,"server_pass":"","nick":"fR"},
    # $server = shift;
});

Irssi::signal_add_last("server connected", sub {
    # FIXME
    # {"bid":18665,"eid":4135,"type":"connected","time":1332770243,"highlight":false,"chan":"*","hostname":"irc.seattlewireless.net","port":7000,"cid":2283,"ssl":true},
});

Irssi::signal_add_last("server connect failed", sub {
    #FIXME: connecting_failed
});

Irssi::signal_add_last("server disconnected", sub {
    # FIXME: socket_closed
});

Irssi::signal_add_last("server quit", sub {
    # FIXME: quit_server
});

Irssi::signal_add_last("channel joined", sub {
    my $channel = shift;

    # {"bid":189344,"eid":2,"type":"you_joined_channel","time":1332826098,"highlight":false,"nick":"fR","chan":"#bar","hostmask":"~u673@irccloud.com","cid":2283}
    broadcast({
        type => "you_joined_channel",
        cid  => $channel->{server}->{_irssi},
        bid  => $channel->{_irssi},
        chan => $channel->{name}
    });
});

Irssi::signal_add_last("channel wholist", sub {
    # FIXME: Fire you_joined_channel here instead?
});

Irssi::signal_add_last("channel sync", sub {
    # FIXME: Or here?
});

Irssi::signal_add_last("server nick changed", sub {
    # FIXME:
});

Irssi::signal_add_last("channel mode changed", sub {
    # FIXME: channel_mode
});

Irssi::signal_add_last("nick mode changed", sub {
    # FIXME: channel_mode
});

Irssi::signal_add_last("user mode changed", sub {
    # FIXME: user_mode
});

Irssi::signal_add_last("message public", sub {
    my $server  = shift;
    my $msg     = shift;
    my $nick    = shift;
    my $address = shift;
    my $target  = shift;

    my $channel = $server->window_item_find($target);

    # {"bid":187241,"eid":201,"type":"buffer_msg","time":1333066198,"highlight":false,"from":"fR","msg":"asd","chan":"#testing","cid":2283,"self":false,"reqid":55} 
    broadcast({
        type => "buffer_msg",
        cid  => $server->{_irssi},
        from => $nick,
        chan => $channel->{name},
        bid  => $channel->{_irssi},
        msg  => $msg,
        self => JSON::false
    });
});

Irssi::signal_add_last("message private", sub {
    my $server  = shift;
    my $msg     = shift;
    my $nick    = shift;
    my $address = shift;

    my $query = $server->window_item_find($nick);

    # "{""bid"":103331,""eid"":2362,""type"":""buffer_msg"",""time"":1332803201,""highlight"":false,""from"":""fR"",""msg"":""hey you there?"",""chan"":""choong"",""cid"":2283,""self"":false},
    broadcast({
        type => "buffer_msg",
        cid  => $server->{_irssi},
        from => $nick,
        bid  => $query->{_irssi},
        msg  => $msg,
        self => JSON::false
    });
});

Irssi::signal_add_last("message own_public", sub {
    my $server = shift;
    my $msg    = shift;
    my $target = shift;

    my $channel = $server->window_item_find($target);

    broadcast({
        type => "buffer_msg",
        cid  => $server->{_irssi},
        from => $server->{nick},
        bid  => $channel->{_irssi},
        msg  => $msg,
        self => JSON::true
    });
});

Irssi::signal_add_last("message own_private", sub {
    my $server      = shift;
    my $msg         = shift;
    my $target      = shift;
    my $orig_target = shift;

    my $query = $server->window_item_find($target);

    broadcast({
        type => "buffer_msg",
        cid  => $server->{_irssi},
        from => $server->{nick},
        bid  => $query->{_irssi},
        msg  => $msg,
        self => JSON::true
    });
});

Irssi::signal_add_last("message join", sub {
    my $server  = shift;
    my $channel = shift;
    my $nick    = shift;
    my $address = shift;

    # "{""bid"":18666,""eid"":127253,""type"":""joined_channel"",""time"":1332789632,""highlight"":false,""nick"":""Jetzee"",""chan"":""#swn"",""hostmask"":""~olo@c-67-171-27-133.hsd1.wa.comcast.net"",""cid"":2283}

    $channel = $server->window_item_find($channel);

    broadcast({
        cid      => $server->{_irssi},
        type     => "joined_channel",
        bid      => $channel->{_irssi},
        nick     => $nick,
        hostmask => $address
    });
});

Irssi::signal_add_last("message part", sub {
    my $server  = shift;
    my $channel = shift;
    my $nick    = shift;
    my $address = shift;

    $channel = $server->window_item_find($channel);

    broadcast({
        cid      => $server->{_irssi},
        type     => "parted_channel",
        bid      => $channel->{_irssi},
        nick     => $nick,
        hostmask => $address
    });
});

Irssi::signal_add_last("message quit", sub {
    my $server  = shift;
    my $nick    = shift;
    my $address = shift;
    my $reason  = shift;
    
    # FIXME
    # {""bid"":188831,""eid"":23,""type"":""quit"",""time"":1332805542,""highlight"":false,""nick"":""ders"",""msg"":""Client exited"",""hostmask"":""~ders@202.72.107.133"",""cid"":2283,""chan"":""ders""}
});

Irssi::signal_add_last("message kick", sub {
    my $server  = shift;
    my $channel = shift;
    my $nick    = shift;
    my $kicker  = shift;
    my $address = shift;
    my $reason  = shift;

    # FIXME
    # {"bid":18666,"eid":127370,"type":"kicked_channel","time":1332819750,"highlight":false,"nick":"Kaa","chan":"#swn","kicker":"choong__","msg":"","cid":2283,"hostmask":"~choong@127.0.0.1"}
});

Irssi::signal_add_last("message topic", sub {
    # FIXME channel_topic
});

$ws_server->listen(3000);
