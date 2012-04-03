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
use YAML;
use Authen::Passphrase;
use Data::Dumper;
use Irssi;
use Irssi::TextUI;
use threads;

use websocket_server;

# Sometimes, for some unknown reason, perl emits warnings like the following:
#   Can't locate package Irssi::Nick for @Irssi::Irc::Nick::ISA
# This package statement is here to suppress it.
# 
# http://bugs.irssi.org/index.php?do=details&task_id=242
# http://pound-perl.pm.org/code/irssi/autovoice.pl
{ package Irssi::Nick }

my @excluded_from_backlog = (
    "makeserver", "makebuffer", "connection_deleted", "delete_buffer"
);

my $backlog = {};

our $config = YAML::LoadFile($ENV{HOME} . "/.irssi/irseas.yml");

sub add_to_backlog {
    my $message = shift;

    my %excludes = map { $_ => 1 } @excluded_from_backlog;
    if (exists($excludes{$message->{type}})) {
        return;
    }

    my $bid = $message->{bid};
    $backlog->{$bid} ||= [];

    if (scalar(@{$backlog->{$bid}}) >= 500) {
        shift(@{$backlog->{$bid}});
    }

    push (@{$backlog->{$bid}}, $message);
};

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

sub make_console_buffer {
    my $server = shift;
    {
        type        => "makebuffer",
        buffer_type => "console",
        cid         => $server->{_irssi},
        bid         => $server->{_irssi},
        name        => "*"
    }
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

sub make_delete_buffer {
    my $buffer = shift;
    {
        type => "delete_buffer",
        cid  => $buffer->{server}->{_irssi},
        bid  => $buffer->{_irssi}
    };
};

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

    my $bids = [];

    foreach my $server (Irssi::servers) {
        send_message($connection, make_server($server));
        send_message($connection, make_console_buffer($server));
        push(@$bids, $server->{_irssi});
    }

    foreach my $channel (Irssi::channels) {
        send_message($connection, make_channel_buffer($channel));
        send_message($connection, make_channel_init($channel));
        push(@$bids, $channel->{_irssi});
    }

    foreach my $query (Irssi::queries) {
        send_message($connection, make_query_buffer($query));
        push(@$bids, $query->{_irssi});
    }

    foreach my $bid (@$bids) {
        my $messages = $backlog->{$bid};
        foreach my $message (@$messages) {
            send_message($connection, $message);
        }
    }

    foreach my $server (Irssi::servers) {
        send_message($connection, {
            type => "end_of_backlog",
            cid  => $server->{_irssi}
        });
    }

    send_message($connection, {
        "type" => "backlog_complete"
    });
}

sub find_server {
    my $cid = shift;

    foreach my $server (Irssi::servers) {
        if ($server->{_irssi} == $cid) {
            return $server;
        }
    }
    return undef;
};

my $ws_server = new WebSocket::Server;

$ws_server->on_listen(sub {
    my $port = shift;
    Irssi::print("Irseas listening on port $port");
});

$ws_server->on_verify_password(sub {
    my $password = shift;

    my $ppr = Authen::Passphrase->from_rfc2307($config->{password});
    my $matches = $ppr->match($password);

    unless ($matches) {
        Irssi::print("Bad password!");
    }

    return $matches;
});

$ws_server->on_connection(sub {
    my $connection = shift;

    $connection->on_message(sub {
        my $message = shift;

        Irssi::print("on message! $message");

        $message = decode_json($message);

        Irssi::print("message: " . Dumper($message));

        my $server = find_server($message->{cid});

        if ($message->{_method} eq "say") {
            my $target = $message->{to};
            my $text   = $message->{msg};

            $server->command("MSG " . $target . " " . $text);

        } elsif ($message->{_method} eq "join") {
            my $channel = $message->{channel};

            $server->command("JOIN " . $channel);

        } elsif ($message->{_method} eq "part") {
            my $channel = $message->{channel};

            $server->command("PART " . $channel);
        }
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

    unless (exists $message->{eid}) {
        $message->{eid} = $eid; # FIXME
        $eid ++;
    }

    unless (exists $message->{time}) {
        $message->{time} = time;
    }

    unless (exists $message->{highlight}) {
        $message->{highlight} = JSON::false;
    }

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

sub broadcast_all_buffers {
    my $server  = shift;
    my $message = shift;

    # console buffer
    broadcast({
        cid => $server->{_irssi},
        bid => $server->{_irssi},
        %$message
    });
    
    foreach my $channel ($server->channels) {
        broadcast({
            cid => $server->{_irssi},
            bid => $channel->{_irssi},
            %$message
        });
    }

    foreach my $query ($server->queries) {
        broadcast({
            cid => $server->{_irssi},
            bid => $query->{_irssi},
            %$message
        });
    }
};

sub broadcast {
    my $message = shift;

    $message = prepare_message($message);

    $ws_server->broadcast(encode_json($message));

    add_to_backlog($message);
};

Irssi::signal_add_last("chatnet create", sub {
    my $chatnet = shift;

    broadcast(make_server($chatnet));
    broadcast(make_console_buffer($chatnet));
});

Irssi::signal_add_last("chatnet destroyed", sub {
    my $chatnet = shift;
    broadcast({
        type => "connection_deleted",
        cid  => $chatnet->{_irssi}
    });
});

Irssi::signal_add_last("channel created", sub {
    my $channel = shift;

    broadcast(make_channel_buffer($channel));
    broadcast(make_channel_init($channel));
});

Irssi::signal_add_last("channel destroyed", sub {
    my $channel = shift;
    broadcast(make_delete_buffer($channel));
});

Irssi::signal_add_last("query created", sub {
    my $query = shift;

    broadcast(make_query_buffer($query));
});

Irssi::signal_add_last("query destroyed", sub {
    my $query = shift;
    broadcast(make_delete_buffer($query));
});

Irssi::signal_add_last("query nick changed", sub {
    my $query    = shift;
    my $orignick = shift;
    
    # {"bid":19028,"eid":2791,"type":"nickchange","time":1333156403,"highlight":false,"newnick":"fR__","oldnick":"fR_","cid":2283} 
    broadcast({
        type    => "nickchange",
        cid     => $query->{server}->{_irssi},
        bid     => $query->{_irssi},
        newnick => $query->{nick},
        oldnick => $orignick
    });
});

Irssi::signal_add_last("server connecting", sub {
    my $server = shift;
    my $ip     = shift;

    # {"bid":18665,"eid":4134,"type":"connecting","time":1332770242,"highlight":false,"chan":"*","hostname":"irc.seattlewireless.net","port":7000,"cid":2283,"ssl":true,"server_pass":"","nick":"fR"},

    broadcast_all_buffers($server, {
        type     => "connecting",
        hostname =>  $server->{address},
        port     =>  $server->{port},
        ssl      =>  JSON::false, # FIXME
        nick     =>  $server->{nick},
    });
});

Irssi::signal_add_last("server connected", sub {
    my $server = shift;

    # {"bid":18665,"eid":4135,"type":"connected","time":1332770243,"highlight":false,"chan":"*","hostname":"irc.seattlewireless.net","port":7000,"cid":2283,"ssl":true},

    broadcast_all_buffers($server, {
        type => "connected",
        ssl  => JSON::false, # FIXME
    });
});

Irssi::signal_add_last("server connect failed", sub {
    my $server = shift;

    # {"bid":191436,"eid":5,"type":"connecting_failed","time":1333212023,"highlight":false,"chan":"*","hostname":"foooooo","port":6667,"cid":22752} 
    
    broadcast_all_buffers($server, {
        type     => "connecting_failed",
        hostname => $server->{address},
        port     => $server->{port}
    });
});

Irssi::signal_add_last("server disconnected", sub {
    my $server = shift;

    # {"bid":190221,"eid":813,"type":"socket_closed","time":1333212190,"highlight":false,"chan":"#mojo","cid":22620} 

    broadcast_all_buffers($server, {
        type => "socket_closed"
    });
});

Irssi::signal_add_last("server quit", sub {
    my $server = shift;
    my $msg    = shift;

    # {"bid":190221,"eid":812,"type":"quit_server","time":1333212190,"highlight":false,"chan":"#mojo","cid":22620,"msg":""} 

    broadcast_all_buffers($server, {
        type => "quit_server",
        msg  => $msg
    });
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

Irssi::signal_add_last("channel topic changed", sub {
    my $channel = shift;

    # {"bid":187241,"eid":227,"type":"channel_topic","time":1333156705,"highlight":false,"chan":"#testing","author":"fR","time":1333156705,"topic":"foo","cid":2283} 

    broadcast({
        type   => "channel_topic",
        cid    => $channel->{server}->{_irssi},
        bid    => $channel->{_irssi},
        author => $channel->{topic_by},
        topic  => $channel->{topic}
    });
});

Irssi::signal_add_last("server nick changed", sub {
    my $server = shift;

    # {"bid":19815,"eid":2751,"type":"you_nickchange","time":1333157256,"highlight":false,"chan":"swn","newnick":"fR","oldnick":"fR_","cid":2283} 

    broadcast_all_buffers($server, {
        type    => "you_nickchange",
        newnick => $server->{nick}
    });
});

Irssi::signal_add_last("channel mode changed", sub {
    my $channel = shift;
    my $set_by  = shift;

    # {"bid":187241,"eid":246,"type":"channel_mode","time":1333233783,"highlight":false,"channel":"#testing","from":"fR__","cid":2283,"diff":"+n","newmode":"tn","ops":{"add":[{"mode":"n","param":""}],"remove":[]}} 

    broadcast({
        type    => "channel_mode",
        cid     => $channel->{server}->{_irssi},
        bid     => $channel->{_irssi},
        from    => $set_by,
        newmode => $channel->{mode}
    });
});

Irssi::signal_add_last("nick mode changed", sub {
    my $channel = shift;
    my $nick    = shift;
    my $set_by  = shift;
    my $mode    = shift;
    my $type    = shift;

    # {"bid":187241,"eid":242,"type":"user_channel_mode","time":1333233137,"highlight":false,"from":"fR","cid":2283,"newmode":"","diff":"-o","channel":"#testing","nick":"fR__","ops":{"add":[],"remove":[{"mode":"o","param":"fR__"}]}} 
    
    broadcast({
        type => "user_channel_mode",
        cid  => $channel->{server}->{_irssi},
        bid  => $channel->{_irssi},
        from => $set_by,
        nick => $nick,
        diff => $type . $mode
    });
});

Irssi::signal_add_last("user mode changed", sub {
    my $server = shift;
    my $old    = shift;

    # {"bid":83378,"eid":3247,"type":"user_mode","time":1333245689,"highlight":false,"nick":"codebutler","cid":10852,"from":"codebutler","newmode":"Zi","diff":"+Zi","ops":{"add":[{"mode":"i","param":""},{"mode":"Z","param":""}],"remove":[]}} 
    broadcast({
        type     => "user_mode",
        cid      => $server->{_irssi},
        bid      => $server->{_irssi},
        newmode  => $server->{mode}
    });
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

Irssi::signal_add_last("message irc own_action", sub {
    my $server = shift;
    my $msg    = shift;
    my $target = shift;

    my $buffer = $server->window_item_find($target);

    # {"bid":187241,"eid":256,"type":"buffer_me_msg","time":1333251035,"highlight":false,"from":"fR_","msg":"blah","chan":"#testing","cid":2283} 

    broadcast({
        cid  => $server->{_irssi},
        bid  => $buffer->{_irssi},
        type => "buffer_me_msg",
        from => $server->{nick},
        msg  => $msg
    });
});

Irssi::signal_add_last("message irc action", sub {
    my $server  = shift;
    my $msg     = shift;
    my $nick    = shift;
    my $address = shift;
    my $target  = shift;

    my $buffer = $server->window_item_find($target);

    # {"bid":187241,"eid":256,"type":"buffer_me_msg","time":1333251035,"highlight":false,"from":"fR_","msg":"blah","chan":"#testing","cid":2283} 
    
    broadcast({
        cid  => $server->{_irssi},
        bid  => $buffer->{_irssi},
        type => "buffer_me_msg",
        from => $nick,
        msg  => $msg
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
    
    # {""bid"":188831,""eid"":23,""type"":""quit"",""time"":1332805542,""highlight"":false,""nick"":""ders"",""msg"":""Client exited"",""hostmask"":""~ders@202.72.107.133"",""cid"":2283,""chan"":""ders""}

    # FIXME: Only to appropriate buffers!
    broadcast_all_buffers($server, {
        type     => "quit",
        nick     => $nick,
        msg      => $reason,
        hostmask => $address
    });
});

Irssi::signal_add_last("message kick", sub {
    my $server  = shift;
    my $channel = shift;
    my $nick    = shift;
    my $kicker  = shift;
    my $address = shift;
    my $reason  = shift;

    # {"bid":18666,"eid":127370,"type":"kicked_channel","time":1332819750,"highlight":false,"nick":"Kaa","chan":"#swn","kicker":"choong__","msg":"","cid":2283,"hostmask":"~choong@127.0.0.1"}

    broadcast({
        type     => "kicked_channel",
        cid      => $server->{_irssi},
        nick     => $nick,
        kicker   => $kicker,
        msg      => $reason,
        hostmask => $address
    });
});

Irssi::signal_add_last("message nick", sub {
    my $server  = shift;
    my $newnick = shift;
    my $oldnick = shift;
    my $address = shift;

    # {"bid":19028,"eid":2791,"type":"nickchange","time":1333156403,"highlight":false,"newnick":"fR__","oldnick":"fR_","cid":2283} 

    # FIXME: Only to appropriate buffers!
    broadcast_all_buffers($server, {
        type    => "nickchange",
        newnick => $newnick,
        oldnick => $oldnick
    });
});

Irssi::signal_add_last("message own_nick", sub {
    my $server  = shift;
    my $newnick = shift;
    my $oldnick = shift;
    my $address = shift;

    broadcast_all_buffers($server, {
        type    => "own_nickchange",
        newnick => $newnick,
        oldnick => $oldnick
    });
});

Irssi::signal_add_last("message irc notice", sub {
    my $server  = shift;
    my $msg     = shift;
    my $nick    = shift;
    my $address = shift;
    my $target  = shift;

    # {"bid":18665,"eid":4136,"type":"notice","time":1332770243,"highlight":false,"server":"seattlewireless.net","msg":"*** Looking up your hostname...","cid":2283,"target":"Auth"}

    broadcast({
        type   => "notice",
        cid    => $server->{_irssi},
        bid    => $server->{_irssi},
        from   => $nick,
        msg    => $msg,
        target => $target
    });
});

Irssi::signal_add_last("message irc own_notice", sub {
    my $server = shift;
    my $msg    = shift;
    my $target = shift;

    broadcast({
        type   => "notice",
        cid    => $server->{_irssi},
        bid    => $server->{_irssi},
        msg    => $msg,
        target => $target
    });
});

Irssi::signal_add_last("message invite", sub {
    my $server  = shift;
    my $channel = shift;
    my $nick    = shift;
    my $address = shift;

    # {"bid":19028,"eid":2804,"type":"channel_invite","time":1333250153,"highlight":false,"cid":2283,"channel":"#asd","from":"fR_"} 

    broadcast({
        cid     => $server->{_irssi},
        bid     => $server->{_irssi},
        type    => "channel_invite",
        channel => $channel,
        from    => $nick
    });
});

Irssi::signal_add_last("away mode changed", sub {
    my $server = shift;
    if ($server->{usermode_away}) {
        # {"bid":18665,"eid":4156,"type":"self_away","time":1332774095,"highlight":false,"chan":"*","nick":"fR","cid":2283,"msg":"You have been marked as being away","away_msg":"Auto-away"},
        broadcast({
            cid      => $server->{_irssi},
            bid      => $server->{_irssi},
            type     => 'self_away',
            away_msg => $server->{away_reason}
        });
    } else {
        # {"bid":18665,"eid":4157,"type":"self_back","time":1332776604,"highlight":false,"chan":"*","nick":"fR","cid":2283},
        broadcast({
            cid  => $server->{_irssi},
            bid  => $server->{_irssi},
            type => "self_back"
        });
    }
});

$ws_server->listen($config->{port});
