#
# tapchat.pl - TapChat plugin for Irssi
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

use strict;
use warnings;
use threads;
use 5.6.1;

use Cwd;
use File::Basename;
use lib dirname(Cwd::abs_path(__FILE__));

use TapChat::Irssi::Engine;

use Carp;
$SIG{__WARN__} = \&carp;
$SIG{__DIE__} = \&confess;

our $engine = new TapChat::Irssi::Engine;

Irssi::settings_add_str('tapchat', 'tapchat_password', '');
Irssi::settings_add_str('tapchat', 'tapchat_push_id', '');
Irssi::settings_add_str('tapchat', 'tapchat_push_key', '');
Irssi::settings_add_int('tapchat', 'tapchat_port',     57623);

use TapChat::Irssi::Commands;
bind_commands($engine);

use TapChat::Irssi::SignalHandlers;
add_signals($engine);

$engine->start;
