sub add_signals {
    my $engine = shift;

    Irssi::signal_add_last("channel created", sub {
        my $channel = shift;
        $engine->broadcast($engine->make_channel_buffer($channel));
    });

    Irssi::signal_add_last("channel destroyed", sub {
        my $channel = shift;
        $engine->broadcast($engine->make_delete_buffer($channel));
    });

    Irssi::signal_add_last("channel sync", sub {
        my $channel = shift;
        $engine->broadcast($engine->make_channel_init($channel));
    });

    Irssi::signal_add_last("channel joined", sub {
        my $channel = shift;

        # {"bid":189344,"eid":2,"type":"you_joined_channel","time":1332826098,"highlight":false,"nick":"fR","chan":"#bar","hostmask":"~u673@irccloud.com","cid":2283}

        $engine->broadcast({
            type => "you_joined_channel",
            cid  => $engine->get_cid($channel->{server}),
            bid  => $engine->get_bid($channel),
            chan => $channel->{name}
        });
    });

    Irssi::signal_add_last("channel topic changed", sub {
        my $channel = shift;

        return unless $channel->{topic_by};

        # {"bid":187241,"eid":227,"type":"channel_topic","time":1333156705,"highlight":false,"chan":"#testing","author":"fR","time":1333156705,"topic":"foo","cid":2283} 

        $engine->broadcast({
            type   => "channel_topic",
            cid    => $engine->get_cid($channel->{server}),
            bid    => $engine->get_bid($channel),
            author => $channel->{topic_by},
            topic  => $channel->{topic}
        });
    });

    Irssi::signal_add_last("channel mode changed", sub {
        my $channel = shift;
        my $set_by  = shift;

        if ((!$set_by) || ($set_by eq $channel->{server}->{real_address})) {
            # {"bid":193328,"eid":5,"type":"channel_mode_is","time":1333583296,"highlight":false,"channel":"#asdsad","server":"seattlewireless.net","cid":2283,"diff":"+nt","newmode":"nt","ops":{"add":[{"mode":"t","param":""},{"mode":"n","param":""}],"remove":[]}} 
            $engine->broadcast({
                type => "channel_mode_is",
                cid     => $engine->get_cid($channel->{server}),
                bid     => $engine->get_bid($channel),
                newmode => $channel->{mode}
            });
        } else {
            # {"bid":187241,"eid":246,"type":"channel_mode","time":1333233783,"highlight":false,"channel":"#testing","from":"fR__","cid":2283,"diff":"+n","newmode":"tn","ops":{"add":[{"mode":"n","param":""}],"remove":[]}} 
            $engine->broadcast({
                type    => "channel_mode",
                cid     => $engine->get_cid($channel->{server}),
                bid     => $engine->get_bid($channel),
                from    => $set_by,
                newmode => $channel->{mode}
            });
        }
    });

    Irssi::signal_add_last("query created", sub {
        my $query = shift;

        $engine->broadcast($engine->make_query_buffer($query));
    });

    Irssi::signal_add_last("query destroyed", sub {
        my $query = shift;
        $engine->broadcast($engine->make_delete_buffer($query));
    });

    Irssi::signal_add_last("query nick changed", sub {
        my $query    = shift;
        my $orignick = shift;
        
        my $server = $query->{server};

        # {"bid":19028,"eid":2791,"type":"nickchange","time":1333156403,"highlight":false,"newnick":"fR__","oldnick":"fR_","cid":2283} 
        $engine->broadcast({
            type    => ($orignick eq $server->{nick}) ? "you_nickchange" : "nickchange",
            cid     => $engine->get_cid($server),
            bid     => $engine->get_bid($query),
            newnick => $query->{nick},
            oldnick => $orignick
        });
    });

    Irssi::signal_add_last("server connecting", sub {
        my $server = shift;
        my $ip     = shift;

        # {"bid":18665,"eid":4134,"type":"connecting","time":1332770242,"highlight":false,"chan":"*","hostname":"irc.seattlewireless.net","port":7000,"cid":2283,"ssl":true,"server_pass":"","nick":"fR"},

        $engine->broadcast($engine->make_server($server));
        $engine->broadcast($engine->make_console_buffer($server));

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

        $engine->broadcast({
            type => "connection_deleted",
            cid  => $engine->get_cid($server)
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

    Irssi::signal_add_last("nicklist changed", sub {
        my $channel  = shift;
        my $nick     = shift;
        my $old_nick = shift;

        my $server = $channel->{server};

        $engine->broadcast({
            type    => ($nick->{nick} eq $server->{nick}) ? "you_nickchange" : "nickchange",
            cid     => $engine->get_cid($server),
            bid     => $engine->get_bid($channel),
            newnick => $nick->{nick},
            oldnick => $old_nick
        });
    });

    Irssi::signal_add_last("server nick changed", sub {
        my $server = shift;

        # {"bid":19815,"eid":2751,"type":"you_nickchange","time":1333157256,"highlight":false,"chan":"swn","newnick":"fR","oldnick":"fR_","cid":2283} 

        $engine->broadcast({
            cid     => $engine->get_cid($server),
            bid     => $engine->get_cid($server),
            type    => "you_nickchange",
            newnick => $server->{nick}
        });

        foreach my $query (Irssi::queries) {
            $engine->broadcast({
                cid     => $engine->get_cid($server),
                bid     => $engine->get_bid($query),
                type    => "you_nickchange",
                newnick => $server->{nick}
            });
        }
    });

    Irssi::signal_add_last("event connected", sub {
        my $server = shift;

        # {"bid":18665,"eid":4143,"type":"connecting_finished","time":1332770244,"highlight":false,"cid":2283},

        broadcast_all_buffers($server, {
            type => "connecting_finished"
        });
    });

    Irssi::signal_add_last("nick mode changed", sub {
        my $channel = shift;
        my $nick    = shift;
        my $set_by  = shift;
        my $mode    = shift;
        my $type    = shift;

        # {"bid":187241,"eid":242,"type":"user_channel_mode","time":1333233137,"highlight":false,"from":"fR","cid":2283,"newmode":"","diff":"-o","channel":"#testing","nick":"fR__","ops":{"add":[],"remove":[{"mode":"o","param":"fR__"}]}} 
        
        $engine->broadcast({
            type => "user_channel_mode",
            cid  => $engine->get_cid($channel->{server}),
            bid  => $engine->get_bid($channel),
            from => $set_by,
            nick => $nick->{nick},
            diff => $type . $mode
        });
    });

    Irssi::signal_add_last("user mode changed", sub {
        my $server = shift;
        my $old    = shift;

        # {"bid":83378,"eid":3247,"type":"user_mode","time":1333245689,"highlight":false,"nick":"codebutler","cid":10852,"from":"codebutler","newmode":"Zi","diff":"+Zi","ops":{"add":[{"mode":"i","param":""},{"mode":"Z","param":""}],"remove":[]}} 
        $engine->broadcast({
            type     => "user_mode",
            cid      => $engine->get_cid($server),
            bid      => $engine->get_cid($server),
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

        my $highlight = $engine->nick_match_msg($msg, $server->{nick});

        # {"bid":187241,"eid":201,"type":"buffer_msg","time":1333066198,"highlight":false,"from":"fR","msg":"asd","chan":"#testing","cid":2283,"self":false,"reqid":55} 
        $engine->broadcast({
            type      => "buffer_msg",
            cid       => $engine->get_cid($server),
            from      => $nick,
            chan      => $channel->{name},
            bid       => $engine->get_bid($channel),
            msg       => $msg,
            highlight => $highlight,
            self      => JSON::false
        });
    });

    Irssi::signal_add_last("message private", sub {
        my $server  = shift;
        my $msg     = shift;
        my $nick    = shift;
        my $address = shift;

        my $query = $server->window_item_find($nick);

        my $highlight = $engine->nick_match_msg($msg, $server->{nick});

        # "{""bid"":103331,""eid"":2362,""type"":""buffer_msg"",""time"":1332803201,""highlight"":false,""from"":""fR"",""msg"":""hey you there?"",""chan"":""choong"",""cid"":2283,""self"":false},
        $engine->broadcast({
            type      => "buffer_msg",
            cid       => $engine->get_cid($server),
            from      => $nick,
            bid       => $engine->get_bid($query),
            msg       => $msg,
            highlight => $highlight,
            self      => JSON::false
        });
    });

    Irssi::signal_add_last("message own_public", sub {
        my $server = shift;
        my $msg    = shift;
        my $target = shift;

        my $channel = $server->window_item_find($target);

        $engine->broadcast({
            type => "buffer_msg",
            cid  => $engine->get_cid($server),
            from => $server->{nick},
            bid  => $engine->get_bid($channel),
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

        $engine->broadcast({
            type => "buffer_msg",
            cid  => $engine->get_cid($server),
            from => $server->{nick},
            bid  => $engine->get_bid($query),
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

        $engine->broadcast({
            cid  => $engine->get_cid($server),
            bid  => $engine->get_bid($buffer),
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
        
        $engine->broadcast({
            cid  => $engine->get_cid($server),
            bid  => $engine->get_bid($buffer),
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

        return if $nick eq $server->{nick};

        $channel = $server->window_item_find($channel);

        $engine->broadcast({
            cid      => $engine->get_cid($server),
            type     => "joined_channel",
            bid      => $engine->get_bid($channel),
            nick     => $nick,
            hostmask => $address
        });

        my $query = $server->query_find($nick);
        if ($query) {
            $engine->broadcast({
                cid      => $engine->get_cid($server),
                type     => "joined_channel",
                bid      => $engine->get_bid($query),
                nick     => $nick,
                hostmask => $address
            });
        }
    });

    Irssi::signal_add_last("message part", sub {
        my $server  = shift;
        my $channel = shift;
        my $nick    = shift;
        my $address = shift;

        return if $nick eq $server->{nick};

        $channel = $server->window_item_find($channel);

        $engine->broadcast({
            cid      => $engine->get_cid($server),
            type     => "parted_channel",
            bid      => $engine->get_bid($channel),
            nick     => $nick,
            hostmask => $address
        });
    });

    Irssi::signal_add_first("message quit", sub {
        my $server  = shift;
        my $nick    = shift;
        my $address = shift;
        my $reason  = shift;
        
        # {""bid"":188831,""eid"":23,""type"":""quit"",""time"":1332805542,""highlight"":false,""nick"":""ders"",""msg"":""Client exited"",""hostmask"":""~ders@202.72.107.133"",""cid"":2283,""chan"":""ders""}

        foreach my $channel (Irssi::channels) {
            if ($channel->nick_find($nick)) {
                $engine->broadcast({
                    cid      => $engine->get_cid($server),
                    bid      => $engine->get_bid($channel),
                    type     => "quit",
                    nick     => $nick,
                    msg      => $reason,
                    hostmask => $address
                });
            }
        }

        my $query = $server->query_find($nick);
        if ($query) {
            $engine->broadcast({
                cid      => $engine->get_cid($server),
                bid      => $engine->get_bid($query),
                type     => "quit",
                nick     => $nick,
                msg      => $reason,
                hostmask => $address
            });
        }
    });

    Irssi::signal_add_last("message kick", sub {
        my $server  = shift;
        my $channel = shift;
        my $nick    = shift;
        my $kicker  = shift;
        my $address = shift;
        my $reason  = shift;

        # {"bid":18666,"eid":127370,"type":"kicked_channel","time":1332819750,"highlight":false,"nick":"Kaa","chan":"#swn","kicker":"choong__","msg":"","cid":2283,"hostmask":"~choong@127.0.0.1"}

        $engine->broadcast({
            type     => "kicked_channel",
            cid      => $engine->get_cid($server),
            nick     => $nick,
            kicker   => $kicker,
            msg      => $reason,
            hostmask => $address
        });
    });

    Irssi::signal_add_last("message irc notice", sub {
        my $server  = shift;
        my $msg     = shift;
        my $nick    = shift;
        my $address = shift;
        my $target  = shift;

        # {"bid":18665,"eid":4136,"type":"notice","time":1332770243,"highlight":false,"server":"seattlewireless.net","msg":"*** Looking up your hostname...","cid":2283,"target":"Auth"}

        $engine->broadcast({
            type   => "notice",
            cid    => $engine->get_cid($server),
            bid    => $engine->get_cid($server),
            from   => $nick,
            msg    => $msg,
            target => $target
        });
    });

    Irssi::signal_add_last("message irc own_notice", sub {
        my $server = shift;
        my $msg    = shift;
        my $target = shift;

        $engine->broadcast({
            type   => "notice",
            cid    => $engine->get_cid($server),
            bid    => $engine->get_cid($server),
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

        $engine->broadcast({
            cid     => $engine->get_cid($server),
            bid     => $engine->get_cid($server),
            type    => "channel_invite",
            channel => $channel,
            from    => $nick
        });
    });

    Irssi::signal_add_last("away mode changed", sub {
        my $server = shift;
        if ($server->{usermode_away}) {
            # {"bid":18665,"eid":4156,"type":"self_away","time":1332774095,"highlight":false,"chan":"*","nick":"fR","cid":2283,"msg":"You have been marked as being away","away_msg":"Auto-away"},
            $engine->broadcast({
                cid      => $engine->get_cid($server),
                bid      => $engine->get_cid($server),
                type     => 'self_away',
                away_msg => $server->{away_reason}
            });
        } else {
            # {"bid":18665,"eid":4157,"type":"self_back","time":1332776604,"highlight":false,"chan":"*","nick":"fR","cid":2283},
            $engine->broadcast({
                cid  => $engine->get_cid($server),
                bid  => $engine->get_cid($server),
                type => "self_back"
            });
        }
    });

    Irssi::signal_add_last("script destroyed", sub {
        # FIXME
        #if ($ws_server) {
        #  $ws_server->stop();
        #  $ws_server = undef;
        #}
    });

    Irssi::signal_add_last("event 375", sub {
        my $server = shift;
        my $data   = shift;
        my $from   = shift;
        $engine->broadcast({
            cid  => $engine->get_cid($server),
            bid  => $engine->get_cid($server),
            type => "server_motdstart",
            msg  => $data
        });
    });

    Irssi::signal_add_last("event 372", sub {
        my $server = shift;
        my $data = shift;
        my $from = shift;
        $engine->broadcast({
            cid  => $engine->get_cid($server),
            bid  => $engine->get_cid($server),
            type => "server_motd",
            msg  => $data
        });
    });

    Irssi::signal_add_last("event 376", sub {
        my $server = shift;
        my $data   = shift;
        $engine->broadcast({
            cid  => $engine->get_cid($server),
            bid  => $engine->get_cid($server),
            type => "server_endofmotd",
            msg  => $data
        });
    });

    Irssi::signal_add_last("event 422", sub {
        my $server = shift;
        my $data   = shift;
        $engine->broadcast({
            cid  => $engine->get_cid($server),
            bid  => $engine->get_cid($server),
            type => "server_nomotd",
            msg  => $data
        });
    });

    sub broadcast_all_buffers {
        my $server  = shift;
        my $message = shift;

        # console buffer
        $engine->broadcast({
            cid => $engine->get_cid($server),
            bid => $engine->get_cid($server),
            %$message
        });
        
        foreach my $channel ($server->channels) {
            $engine->broadcast({
                cid => $engine->get_cid($server),
                bid => $engine->get_bid($channel),
                %$message
            });
        }

        foreach my $query ($server->queries) {
            $engine->broadcast({
                cid => $engine->get_cid($server),
                bid => $engine->get_bid($query),
                %$message
            });
        }
    };
}


1;
