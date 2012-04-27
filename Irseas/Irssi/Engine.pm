#
# Irseas::Irssi::Engine - Irseas plugin for Irssi
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

package Irseas::Irssi::Engine;

@ISA = (Irseas::Engine);

use Data::Dumper;
use JSON;

use Irssi;
use Irssi::TextUI;

use Irseas::Engine;

# Sometimes, for some unknown reason, perl emits warnings like the following:
#   Can't locate package Irssi::Nick for @Irssi::Irc::Nick::ISA
# This package statement is here to suppress it.
# 
# http://bugs.irssi.org/index.php?do=details&task_id=242
# http://pound-perl.pm.org/code/irssi/autovoice.pl
{ package Irssi::Nick }

my $BACKLOG_FILE = $ENV{HOME} . "/.irssi/irseas.db";

sub new {
    my $class  = shift;
    my %params = @_;

    $params{id_to_cid}    = {};
    $params{cid_to_id}    = {};
    $params{id_to_bid}    = {};
    $params{bid_to_id}    = {};
    $params{backlog_file} = $BACKLOG_FILE;

    my $self = Irseas::Engine->new(%params);

    return bless($self, $class);
};

sub show_welcome {
    my $self = shift;

    Irssi::print("Thank you for installing Irseas!");
    Irssi::print("");
    Irssi::print("Run the following command to get started:");
    Irssi::print("");
    Irssi::print("    /irseas configure %Upassword%U");
    Irssi::print("");
    Irssi::print("If you have any questions, please visit http://irseas.com/irssi");
    Irssi::print("");
}


sub port {
    my $self = shift;

    return int(Irssi::settings_get_int('irseas_port'));
};

sub password {
    my $self = shift;

    return Irssi::settings_get_str('irseas_password');
};

sub log {
    my $self = shift;
    my $msg  = shift;

    Irssi::print("[IRSEAS] " . $msg);
}

sub get_cid {
    my $self   = shift;
    my $server = shift;
    
    my $id_to_cid = $self->{id_to_cid};
    my $cid_to_id = $self->{cid_to_id};

    my $id = $server->{_irssi};

    if ($id_to_cid->{$id}) {
        return $id_to_cid->{$id};
    }

    my $cid = $self->db->get_cid($server->{address} . ":" . $server->{port});

    $id_to_cid->{$id} = $cid;
    $cid_to_id->{$cid} = $id;

    return $cid;
};

sub get_bid {
    my $self   = shift;
    my $buffer = shift;

    my $id_to_bid = $self->{id_to_bid};
    my $bid_to_id = $self->{bid_to_id};

    my $id = $buffer->{_irssi};

    if ($id_to_bid->{$id}) {
        return $id_to_bid->{$id};
    }

    my $bid;

    if (ref($buffer) eq "Irssi::Irc::Server") {
        # Special case for "console" buffer
        my $cid  = $self->get_cid($buffer);
        my $name = "*";
        $bid = $self->db->get_bid($cid, $name);

    } else {
        my $cid = $self->get_cid($buffer->{server});
        $bid = $self->db->get_bid($cid, $buffer->{name});
    }

    $id_to_bid->{$id} = $bid;
    $bid_to_id->{$bid} = $id;

    return $bid;
};

sub send_header {
    my $self       = shift;
    my $connection = shift;
    $self->send($connection, {
        "type"          => "header",
        "idle_interval" => 29000 # FIXME
    });
}

sub send_backlog {
    my $self       = shift;
    my $connection = shift;

    $self->{sending_backlog} = JSON::true;

    foreach my $server (Irssi::servers) {
        $self->send($connection, $self->make_server($server));

        my $buffer_msg = $self->send($connection, $self->make_console_buffer($server));
        $self->send_buffer_backlog($connection, $buffer_msg->{bid});
    }

    foreach my $channel (Irssi::channels) {
        my $buffer_msg = $self->send($connection, $self->make_channel_buffer($channel));
        $self->send($connection, $self->make_channel_init($channel));
        $self->send_buffer_backlog($connection, $buffer_msg->{bid});
    }

    foreach my $query (Irssi::queries) {
        my $buffer_msg = $self->send($connection, $self->make_query_buffer($query));
        $self->send_buffer_backlog($connection, $buffer_msg->{bid});
    }

    foreach my $server (Irssi::servers) {
        $self->send($connection, {
            type => "end_of_backlog",
            cid  => $self->get_cid($server)
        });
    }

    $self->send($connection, {
        "type" => "backlog_complete"
    });

    $self->{sending_backlog} = JSON::false;
};

sub make_server {
    my $self   = shift;
    my $server = shift;

    # {"bid":-1,"eid":-1,"type":"makeserver","time":-1,"highlight":false,"num_buffers":35,"cid":2283,"name":"SWN","nick":"fR","nickserv_nick":"fR_","nickserv_pass":"","realname":"fR","hostname":"irc.seattlewireless.net","port":7000,"away":"","disconnected":false,"ssl":true,"server_pass":""},

    {
        "type"         => "makeserver", 
        "cid"          => $self->get_cid($server),
        "name"         => $server->{chatnet} || $server->{tag},
        "nick"         => $server->{nick},
        "realname"     => $server->{realname},
        "hostname"     => $server->{address},
        "port"         => $server->{port},
        "disconnected" => ($server->{connected} == 1) ? JSON::false : JSON::true,
        "ssl"          => JSON::false # FIXME
    };
};

sub make_buffer {
    my $self  = shift;
    my $type  = shift;
    my $item  = shift;
    my $extra = shift || {};

    my $message = {
        "type"        => "makebuffer",
        "buffer_type" => $type,
        "cid"         => $self->get_cid($item->{server}),
        "bid"         => $self->get_bid($item),
        "name"        => $item->{name},
        %$extra
    };

    my $eid = $self->{db}->get_buffer_last_seen_eid($message->{bid});
    if ($eid) {
        $message->{last_seen_eid} = $eid;
    }

    return $message;
};

sub make_console_buffer {
    my $self   = shift;
    my $server = shift;
    {
        type        => "makebuffer",
        buffer_type => "console",
        cid         => $self->get_cid($server),
        bid         => $self->get_bid($server),
        name        => "*"
    };
};

sub make_channel_buffer {
    my $self    = shift;
    my $channel = shift;
    $self->make_buffer("channel", $channel, {
        "joined" => ($channel->{joined} == 1) ? JSON::true : JSON::false
    });
}

sub make_query_buffer {
    my $self  = shift;
    my $query = shift;
    $self->make_buffer("conversation", $query);
}

sub make_channel_init {
    my $self    = shift;
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
        "cid"    => $self->get_cid($channel->{server}),
        "bid"    => $self->get_bid($channel),
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
    my $self   = shift;
    my $buffer = shift;

    {
        type => "delete_buffer",
        cid  => $self->get_cid($buffer->{server}),
        bid  => $self->get_bid($buffer)
    };
}

sub find_server {
    my $self = shift;
    my $cid  = shift;

    my $id = $self->{cid_to_id}->{$cid};

    foreach my $server (Irssi::servers) {
        if ($server->{_irssi} == $id) {
            return $server;
        }
    }
    return undef;
};

sub find_buffer {
    my $self   = shift;
    my $server = shift;
    my $bid    = shift;

    my $id = $self->{bid_to_id}->{$bid};

    if ($id == $server->{_irssi}) {
        # This is the fake "console" buffer.
        return undef;
    };

    foreach my $channel (Irssi::channels) {
        if ($channel->{_irssi} == $id) {
            return $channel;
        }
    }

    foreach my $query (Irssi::queries) {
        if ($query->{_irssi} == $id) {
            return $query;
        }
    }

    return undef;
}

sub message_handlers {
    my $self = shift;

    {
        heartbeat => sub {
            my $connection = shift;
            my $message    = shift;

            $self->{selected_buffer} = $message->{selectedBuffer};

            my $seen_eids = decode_json($message->{seenEids});
            foreach my $cid (keys %{$seen_eids}) {
                my $buffers = $seen_eids->{$cid};
                foreach my $bid (keys %{$buffers}) {
                    my $eid = $buffers->{$bid};
                    $self->{db}->set_buffer_last_seen_eid($bid, $eid);
                }
            }

            # FIXME: Only need to send seen_eids that have changed
            my $updated_seen_eids = $self->{db}->get_all_last_seen_eids;

            $self->send($connection, {
                type     => 'heartbeat_echo',
                seenEids => $updated_seen_eids
            });
        },

        say => sub {
            my $connection = shift;
            my $message    = shift;

            my $server = $self->find_server($message->{cid});

            my $to   = $message->{to};
            my $cid  = $message->{cid};
            my $text = $message->{msg};
            
            # FIXME: This won't work for non-IRC protocols.
            my $is_channel = ($to =~ /^#/);

            my $witem = Irssi::window_find_item($to);

            my $cmd = ($is_channel) ? "MSG" : "QUERY";

            if ($text) {
                $server->command("$cmd $to $text");

            } elsif (!$is_channel) {
                # Just open new query window
                $server->command("QUERY $to");
            }

            if ($witem) {
                print "window already open";
                # Window was already open.
                return {};
            }

            return {
                name => $to,
                cid  => $cid,
                type => 'open_buffer'
            };
        },

        join => sub {
            my $connection = shift;
            my $message    = shift;

            my $channel = $message->{channel};
            my $cid     = $message->{cid};

            my $server = $self->find_server($message->{cid});
            $server->command("JOIN " . $channel);

            return {
                name => $channel, 
                cid  => $cid, 
                type => 'open_buffer' 
            };
        },

        part => sub {
            my $connection = shift;
            my $message    = shift;

            my $channel = $message->{channel};

            my $server = $self->find_server($message->{cid});
            $server->command("PART " . $channel);
        },

        'hide-buffer' => sub {
            my $connection = shift;
            my $message    = shift;

            my $server = $self->find_server($message->{cid});
            my $buffer = $self->find_buffer($server, $message->{id});

            $buffer->window->command('window close');
        }
    }
}


1;
