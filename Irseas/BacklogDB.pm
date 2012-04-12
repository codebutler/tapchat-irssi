package Irseas::BacklogDB;

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

    my $m = DBIx::Migration->new({
        dsn => $self->{dsn},
        dir => $migrations_dir
    });
    $m->migrate($SCHEMA_VERSION);

    $self->{db} = DBI->connect($self->{dsn}, "", "",
      { RaiseError => 1 });
}

sub latest_eid {
    my $self = shift;
    return $self->{db}->selectrow_array("SELECT MAX(eid) FROM events", undef);
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
            INSERT INTO connections (name) VALUES (:name)
        ");
        $st->bind_param(":name", $name);
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
            INSERT INTO buffers (cid, name) VALUES (:cid, :name)
        ");
        $st->bind_param(":cid",  $cid);
        $st->bind_param(":name", $name);
        $st->execute;
        
        return $self->{db}->func('last_insert_rowid')
    }
};

sub insert_event {
    my $self = shift;

    my $eid  = shift;
    my $cid  = shift;
    my $bid  = shift;
    my $data = shift;
    my $time = shift;

    my $st = $self->{db}->prepare("
        INSERT INTO events (eid, cid, bid, data, created_at) 
        VALUES (:eid, :cid, :bid, :data, :created_at)
    ");
    $st->bind_param(":eid",        $eid);
    $st->bind_param(":cid",        $cid);
    $st->bind_param(":bid",        $bid);
    $st->bind_param(":data",       $data);
    $st->bind_param(":created_at", $time);
    $st->execute();
};

sub select_events {
    my $self  = shift;
    my $bid   = shift;
    my $limit = shift;

    my @bind = ( $bid, $limit );

    return idb_rows($self->{db}, "
        SELECT eid, cid, bid, data
        FROM events
        WHERE bid = ?
        ORDER BY created_at DESC
        LIMIT ?
    ", @bind);
};

1;
