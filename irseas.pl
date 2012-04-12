#
# Irseas.pl - Irseas plugin for Irssi
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
use threads;
use 5.6.1;

use Cwd;
use File::Basename;
use lib dirname(Cwd::abs_path(__FILE__));

use Irseas::Irssi::Engine;

use WebSocket::Server;

use Carp;
$SIG{__WARN__} = \&carp;
$SIG{__DIE__} = \&confess;

Irssi::settings_add_str('irseas', 'irseas_password', '');
Irssi::settings_add_int('irseas', 'irseas_port', 3000);

sub configure {
  Irssi::print("");
  Irssi::print("Welcome to Irseas!");
  Irssi::print("");
  Irssi::print("Please wait a moment...");

  # FIXME: Generate SSL cert!
  
  ( my $word, my $hyphenated ) = Crypt::RandPasswd::word(16, 16);

  Irssi::print("");
  Irssi::print("Password: " . $word);
  Irssi::print("");

  # start($port, $password);
};

sub start {
    my $port = shift;

    my $engine = new Irseas::Irssi::Engine;

    # FIXME: Move this into Irseas::Irssi::Engine!
    use Irseas::Irssi::SignalHandlers;
    add_signals($engine);

    my $ws_server = new WebSocket::Server(
        on_listen => sub {
            my $port = shift;
            $engine->log("Listening on: $port");
        },
        on_verify_password => sub {
            my $password = shift;
            return $engine->verify_password($password);
        },
        on_connection => sub {
            my $connection = shift;
            $engine->add_connection($connection);
        },
        on_close => sub {
            my $connection = shift;
            $engine->remove_connection($connection);
        }
    );

    $ws_server->listen($port);
};

my $port = Irssi::settings_get_int('irseas_port');
my $pass = Irssi::settings_get_str('irseas_password');
    
# FIXME
#if (!$port || !$pass) {
#unless ($engine->is_configured) {
#    $engine->configure(sub {
#        start($port, $pass);
#    });
#    return;
#}
#sub start {
#    my $self = shift;
#};
#unless ($port && $password) {
#    configure();
#    return;
#}
#start($port, $password);

start($port);
