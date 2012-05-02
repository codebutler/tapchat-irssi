package TapChat::BacklogDB;

my $SCHEMA_VERSION = 1;

use DBI;
use DBIx::Migration;
use Iterator::DBI;
use Data::Dumper;
use File::Basename;

sub new {
    my $class = shift;
    my $file  = shift;

    bless {
        dsn => "dbi:SQLite:$file"
    }, $class;
};

sub setup {
    my $self = shift;

    my $migrations_dir = dirname(__FILE__) . "/../db";
    unless (-d $migrations_dir) {
        die "DB migrations directory not found: $migrations_dir"
    }

    my $m = DBIx::Migration->new({
        dsn => $self->{dsn},
        dir => $migrations_dir
    });
    $m->migrate($SCHEMA_VERSION);

    $self->{db} = DBI->connect($self->{dsn}, "", "",
      { RaiseError => 1 });
}

sub get_cid {
    my $self = shift;
    my $name = shift;

    my $st = $self->{db}->prepare("
        SELECT cid FROM connections
        WHERE name = :name
    ");
    $st->bind_param(":name", $name);
    $result = $self->{db}->selectrow_hashref($st);

    if ($result) {
        return $result->{cid};

    } else {
        $st = $self->{db}->prepare("
            INSERT INTO connections (name, created_at) VALUES (:name, :created_at)
        ");
        $st->bind_param(":name", $name);
        $st->bind_param(":created_at", time);
        $st->execute;
        
        return $self->{db}->func('last_insert_rowid')
    }
}

sub get_bid {
    my $self = shift;
    my $cid  = shift;
    my $name = shift;

    my $st = $self->{db}->prepare("
        SELECT bid FROM buffers
        WHERE name = :name
        AND   cid  = :cid
    ");
    $st->bind_param(":cid",  $cid);
    $st->bind_param(":name", $name);
    $result = $self->{db}->selectrow_hashref($st);

    if ($result) {
        return $result->{bid};

    } else {
        $st = $self->{db}->prepare("
            INSERT INTO buffers (cid, name, created_at) VALUES (:cid, :name, :created_at)
        ");
        $st->bind_param(":cid",  $cid);
        $st->bind_param(":name", $name);
        $st->bind_param(":created_at", time);
        $st->execute;

        return $self->{db}->func('last_insert_rowid');
    }
};

sub get_buffer_last_seen_eid {
    my $self = shift;
    my $bid  = shift;

    my $st = $self->{db}->prepare("
        SELECT last_seen_eid FROM buffers
        WHERE bid = :bid
    ");
    $st->bind_param(":bid", $bid);

    my $row = $self->{db}->selectrow_hashref($st);

    return $row->{last_seen_eid};
};

sub set_buffer_last_seen_eid {
    my $self = shift;
    my $bid  = shift;
    my $eid  = shift;

    my $st = $self->{db}->prepare("
        UPDATE buffers
        SET last_seen_eid = :eid,
        updated_at = :time
        WHERE bid = :bid
    ");
    $st->bind_param(":eid", $eid);
    $st->bind_param(":bid", $bid);
    $st->bind_param(":time", time);
    
    $st->execute();
};

sub get_all_last_seen_eids {
    my $self = shift;

    my $result = $self->{db}->selectall_hashref("SELECT cid, bid, last_seen_eid FROM buffers WHERE last_seen_eid IS NOT NULL", [ 'cid', 'bid' ]);

    for my $cid (keys %{$result}) {
        for my $bid (keys %{$result->{$cid}}) {
            $result->{$cid}->{$bid} = $result->{$cid}->{$bid}->{last_seen_eid};
        }
    };

    return $result;
};

sub insert_event {
    my $self = shift;

    my $bid  = shift;
    my $data = shift;
    my $time = shift;

    my $st = $self->{db}->prepare("
        INSERT INTO events (bid, data, created_at) 
        VALUES (:bid, :data, :created_at)
    ");
    $st->bind_param(":bid",        $bid);
    $st->bind_param(":data",       $data);
    $st->bind_param(":created_at", $time);
    $st->execute();

    return $self->{db}->func('last_insert_rowid')
};

sub select_events {
    my $self  = shift;
    my $bid   = shift;
    my $limit = shift;

    my @bind = ( $bid, $limit );

    return idb_rows($self->{db}, "
        SELECT eid, bid, data, created_at
        FROM events
        WHERE eid IN (
            SELECT eid
            FROM EVENTS
            WHERE bid = ?
            ORDER BY eid DESC
            LIMIT ?
        )
        ORDER BY eid ASC
    ", @bind);
};

1;
