package Irseas::Engine;

use Irseas::BacklogDB;

use Authen::Passphrase;
use Authen::Passphrase::BlowfishCrypt;

use Data::Dumper;
use Data::ArrayList;
use JSON;

my @EXCULDED_FROM_BACKLOG = (
    "makeserver", "makebuffer", "connection_deleted", "delete_buffer", "channel_init"
);

sub new {
    my $class  = shift;
    my %params = @_;

    my $backlog_file = delete $params{backlog_file};

    my $db = Irseas::BacklogDB->new($backlog_file);
    $db->setup;

    bless {
        db          => $db,
        connections => new Data::ArrayList,
        %params
    }, $class;
}

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

    my $handler = $self->{message_handler};
    
    $self->connections->add($connection);
    $connection->on_message(sub {
        my $message = shift;
        $self->on_message(decode_json($message));
    });

    $self->send($connection, $self->make_header);
    $self->send($connection, $self->make_backlog);
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

    if (ref($message) eq 'ARRAY') {
        foreach my $item (@$message) {
            $self->broadcast($item);
        }
        return;
    }

    $message = $self->prepare_message($message);

    my $eid = $self->add_to_backlog($message);

    if ($eid) {
        $message->{eid} = $eid;
    } else {
        $message->{eid} = -1;
    }

    my $json = encode_json($message);

    unless ($self->connections->isEmpty) {
        my $iter = $self->connections->listIterator();
        while ($iter->hasNext) {
            my $connection = $iter->next;
            $connection->send($json);
        }
    }
}

sub broadcast_all_buffers {
    my $self    = shift;
    my $server  = shift;
    my $message = shift;

    # console buffer
    $self->broadcast({
        cid => $self->get_cid($server),
        bid => $self->get_bid($server),
        %$message
    });
    
    foreach my $channel ($server->channels) {
        $self->broadcast({
            cid => $self->get_cid($server),
            bid => $self->Get_bid($channel)
            %$message
        });
    }

    foreach my $query ($server->queries) {
        $self->broadcast({
            cid => $self->get_cid($server),
            bid => $self->get_bid($query),
            %$message
        });
    }
}

sub send {
    my $self       = shift;
    my $connection = shift;
    my $message    = shift;

    if (ref($message) eq 'ARRAY') {
        foreach my $item (@$message) {
            $self->send($connection, $item);
        }
        return;
    }

    $connection->send(
        encode_json(
            $self->prepare_message($message)
        )
    );
}

sub add_to_backlog {
    my $self    = shift;
    my $message = shift;

    my $cid  = $message->{cid};
    my $bid  = $message->{bid};
    my $type = $message->{type};
    my $time = $message->{time};

    unless ($bid) {
        return;
    }

    my %excludes = map { $_ => 1 } @EXCULDED_FROM_BACKLOG;
    if (exists($excludes{$type})) {
        return;
    }

    my $data = encode_json($message);

    return $self->{db}->insert_event($cid, $bid, $data, $time);
};

sub get_backlog {
    my $self = shift;
    my $bid  = shift;

    my $iter = $self->{db}->select_events($bid, 1000);

    return sub {
        return undef if $iter->is_exhausted();
        $row = $iter->value();
        $message = decode_json($row->{data});
        $message->{is_backlog} = JSON::true;
        $message->{eid} = $row->{eid};

        return $message;
    };
};

sub prepare_message {
    my $self    = shift;
    my $message = shift;

    unless ($message->{eid}) {
        $message->{eid} = -1;
    }

    unless (exists $message->{time}) {
        $message->{time} = time;
    }

    unless (exists $message->{highlight}) {
        $message->{highlight} = JSON::false;
    }

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

1;
