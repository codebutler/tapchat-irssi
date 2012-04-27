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

use Carp;
$SIG{__WARN__} = \&carp;
$SIG{__DIE__} = \&confess;

our $engine = new Irseas::Irssi::Engine;

Irssi::settings_add_str('irseas', 'irseas_password', '');
Irssi::settings_add_int('irseas', 'irseas_port',     57623);

use Irseas::Irssi::Commands;
bind_commands($engine);

use Irseas::Irssi::SignalHandlers;
add_signals($engine);

$engine->start;
