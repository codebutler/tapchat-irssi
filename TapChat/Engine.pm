#
# TapChat::Engine
#
# Copyright (C) 2012 Eric Butler <eric@codebutler.com>
#
# This file is part of TapChat.
#
# TapChat is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# TapChat is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with TapChat.  If not, see <http://www.gnu.org/licenses/>.

package TapChat::Engine;

use TapChat::BacklogDB;

use MIME::Base64;
use Authen::Passphrase;
use Authen::Passphrase::BlowfishCrypt;
use Data::Dumper;
use Data::ArrayList;
use JSON;
use WebSocket::Server;
use Crypt::CBC;
use AnyEvent::HTTP;
use Data::URIEncode;

our $NOTIFY_URL = "https://tapchat.heroku.com/notify";

my @EXCULDED_FROM_BACKLOG = (
    "makeserver", "makebuffer", "connection_deleted", "delete_buffer", "channel_init"
);

sub new {
    my $class  = shift;
    my %params = @_;

    my $backlog_file = delete $params{backlog_file};

    my $db = TapChat::BacklogDB->new($backlog_file);
    $db->setup;

    bless {
        db          => $db,
        connections => new Data::ArrayList,
        %params
    }, $class;
}

sub start {
    my $self = shift;

    unless ($self->is_configured) {
        $self->show_welcome();
        return;
    }

    if ($self->{ws_server}) {
        return;
    }

    $self->{ws_server} = new WebSocket::Server(
        on_listen => sub {
            my $port = shift;
            $self->log("Listening on: $port");
        },
        on_stop => sub {
            $self->log("Stopped listening");
        },
        on_verify_password => sub {
            my $password = shift;
            return $self->verify_password($password);
        },
        on_connection => sub {
            my $connection = shift;
            $self->add_connection($connection);
        },
        on_close => sub {
            my $connection = shift;
            $self->remove_connection($connection);
        }
    );

    $self->{ws_server}->listen($self->port);
};

sub is_configured {
    my $self = shift;
    $self->port && $self->password;
};

sub is_started {
    my $self = shift;
    !!($self->{ws_server});
};

sub stop {
    my $self = shift;

    unless ($self->{ws_server}) {
        return;
    }

    $self->{ws_server}->stop;
    $self->{ws_server} = undef;
};

sub db {
  my $self = shift;
  return $self->{db};
}

sub connections {
    my $self = shift;
    return $self->{connections};
}

sub verify_password {
    my $self     = shift;
    my $password = shift;

    my $ppr = Authen::Passphrase->from_rfc2307($self->password);
    my $matches = $ppr->match($password);

    return $matches;
}

sub add_connection {
    my $self       = shift;
    my $connection = shift;

    $self->log("Connection added: " . $connection->{host} . ":" . $connection->{port});
    
    $self->connections->add($connection);
    $connection->on_message(sub {
        my $message = shift;
        $self->on_message($connection, decode_json($message));
    });

    $self->send_header($connection);
    $self->send_backlog($connection);
};

sub remove_connection {
    my $self       = shift;
    my $connection = shift;

    $self->log("Connection removed: " . $connection->{host} . ":" . $connection->{port});

    my $idx = $self->connections->indexOf(sub { $_ eq $connection });
    $self->connections->remove($idx);
};

sub broadcast {
    my $self    = shift;
    my $message = shift;

    $message = $self->prepare_message($message);

    unless ($message->{eid}) {
        my $eid = $self->add_to_backlog($message);
        $message->{eid} = $eid;
    }

    my $json = encode_json($message);

    unless ($self->connections->isEmpty) {
        my $iter = $self->connections->listIterator();
        while ($iter->hasNext) {
            my $connection = $iter->next;
            $connection->send($json);
        }
    }

    if ($message->{highlight}) {
        $self->send_push($message);
    }
}

sub send {
    my $self       = shift;
    my $connection = shift;
    my $message    = shift;

    $message = $self->prepare_message($message);

    unless ($message->{eid}) {
        $message->{eid} = -1;
    }

    $connection->send(encode_json($message));

    return $message;
}

sub send_header {
    my $self       = shift;
    my $connection = shift;

    $self->send($connection, {
        "type"          => "header",
        "idle_interval" => 29000, # FIXME
        "push_id"       => $self->push_id,
        "push_key"      => encode_base64url($self->push_key)
    });
}

sub send_buffer_backlog {
    my $self       = shift;
    my $connection = shift;
    my $bid        = shift;

    my $iter = $self->get_backlog($bid);
    while (my $message = $iter->()) {
        $self->send($connection, $message);
    }
}

sub add_to_backlog {
    my $self    = shift;
    my $message = shift;

    $message = { %$message };

    my $cid  = $message->{cid};
    my $bid  = $message->{bid};
    my $type = $message->{type};
    my $time = $message->{time};
    
    unless ($bid) {
        return -1;
    }

    my %excludes = map { $_ => 1 } @EXCULDED_FROM_BACKLOG;
    if (exists($excludes{$type})) {
        return -1;
    }

    delete $message->{is_backlog};
    delete $message->{eid};
    delete $message->{time};

    my $data = encode_json($message);

    my $eid = $self->{db}->insert_event($bid, $data, $time);

    if ($bid eq $self->{selected_buffer}) {
        $self->{db}->set_buffer_last_seen_eid($bid, $eid);
    }

    return $eid;
};

sub get_backlog {
    my $self = shift;
    my $bid  = shift;

    my $iter = $self->{db}->select_events($bid, 50);

    return sub {
        return undef if $iter->is_exhausted();
        $row = $iter->value();
        $message = decode_json($row->{data});
        $message->{is_backlog} = JSON::true;
        $message->{eid}        = $row->{eid};
        $message->{time}       = $row->{created_at};

        return $message;
    };
};

sub prepare_message {
    my $self    = shift;
    my $message = shift;

    unless (exists $message->{time}) {
        $message->{time} = time;
    }

    unless (exists $message->{highlight}) {
        $message->{highlight} = JSON::false;
    }

    # FIXME: is_backlog

    return $message;
};

sub hash_password {
    my $self     = shift;
    my $password = shift;

    my $ppr = Authen::Passphrase::BlowfishCrypt->new(
        cost        => 8,
        salt_random => 1,
        passphrase  => $password
    );
    return $ppr->as_rfc2307;
};

sub nick_match_msg {
    my $self = shift;
    my $msg  = shift;
    my $nick = shift;
    ($msg =~ /$nick/) ? JSON::true : JSON::false;;
};

sub on_message {
    my $self       = shift;
    my $connection = shift;
    my $message    = shift;

    my $reply = {};

    my $handler = $self->message_handlers->{$message->{_method}};

    if ($handler) {
        eval {
            $reply = $handler->($connection, $message);
        };

        if ($@) {
            $self->log("Error in on_message: " . $@);
            $reply->{success} = JSON::false;
        } else {
            $reply->{success} = JSON::true;
        }

    } else {
        $self->log("Unknown message type: " . encode_json($message));
        $reply->{success} = JSON::false;
    }

    $self->send($connection, {
        _reqid => $message->{_reqid},
        msg    => $reply
    });
};

sub send_push {
    my $self    = shift;
    my $message = shift;

    my $bid = $message->{bid};

    # FIXME: This needs to also confirm the client is still connected.
    # if ($bid eq $self->{selected_buffer}) {
    #    return;
    # }

    my $server = $self->find_server($message->{cid});
    my $buffer = $self->find_buffer($server, $message->{bid});

    unless ($server->{usermode_away} == 1) {
        return;
    }

    $self->log('Sending push notification for: ' . encode_json($message));

    my $title = $buffer->{name};

    my $text;
    if ($buffer->{type} eq 'CHANNEL') {
        $text = "<" . $message->{from} . "> " . $message->{msg};
    } else {
        $text = $message->{msg};
    }

    my $info = {
        title => $title,
        text  => $text,
        cid   => $message->{cid},
        bid   => $bid
    };

    my $id  = $self->push_id;
    my $key = $self->push_key;

    # Push notifications go to the TapChat server, then to UrbanAirship,
    # then to Google (C2DM). None of these people need to know what you're
    # saying.
    my ($iv, $ciphertext) = encrypt($key, encode_json($info));

    my $body = Data::URIEncode::complex_to_query({
        id      => $id,
        message => encode_base64url($ciphertext),
        iv      => encode_base64url($iv)
    });

    http_post $NOTIFY_URL, $body, sub {
        my $body    = shift;
        my $headers = shift;

        unless ($headers->{Status} =~ /^2/) {
            $self->log("Error sending push notification: $headers->{Status} $headers->{Reason}");
        }
    };
};

sub encode_base64url {
    my $e = encode_base64(shift, "");
    $e =~ s/=+\z//;
    $e =~ tr[+/][-_];
    return $e;
}

sub encrypt {
    my $key = shift;
    my $msg = shift;
    my $iv  = Crypt::CBC->random_bytes(16);
    my $cbc = Crypt::CBC->new(
        -literal_key => 1,
        -key         => $key,
        -iv          => $iv,
        -cipher      => 'Crypt::Rijndael',
        -header      => 'none'
    );
    my $ciphertext = $cbc->encrypt($msg, '');
    return ($iv, $ciphertext);
}
1;
