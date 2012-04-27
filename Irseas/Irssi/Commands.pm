#
# Commands.pm
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

use Authen::Passphrase;
use Crypt::RandPasswd;

my $BASE_CMD = 'irseas';

sub commands {
    my $engine = shift;
    {
        start => {
            help    => 'Start the Irseas server',
            handler => sub {
                $engine->start;
            }
        },

        stop => {
            help    => 'Start the Irseas server',
            handler => sub {
                $engine->stop;
            }
        },

        restart => {
            help    => 'Restart the Irseas service',
            handler => sub {
                $engine->stop;
                $engine->start;
            }
        },

        configure => {
            help    => 'Configure Irseas',
            usage   => [ 'password' ],
            handler => sub {
                my $password = shift;

                $engine->stop;

                my $ppr = Authen::Passphrase::BlowfishCrypt->new(
                    cost        => 8,
                    salt_random => 1,
                    passphrase  => $password
                );

                Irssi::settings_set_str('irseas_password', $ppr->as_rfc2307);

                Irssi::print "Password updated.";

                unless (Irssi::settings_get_int('irseas_port')) {
                    Irssi::settings_set_int('irseas_port', 57623);
                }

                my $cert_file = $ENV{HOME} . "/.irssi/irseas.pem";
                unless (-e $cert_file) {
                    Irssi::print "Generating SSL certificate (this may take a minute)...";
                    my $result = `openssl req -new -x509 -days 10000 -nodes -out $cert_file -keyout $cert_file -subj '/CN=irseas' 2>&1`;
                    if ($? != 0) {
                        Irssi::print "Failed to generate certificate: $result";
                        return;
                    }

                    my $fingerprint = `openssl x509 -fingerprint -in $cert_file -noout`;
                    Irssi::print "Certificate created! $fingerprint";
                }

                $engine->start;
            }
        }
    };
}

sub bind_commands {
    my $engine = shift;

    my $commands = commands($engine);

    sub show_help {
        Irssi::print "Available commands:";

        for my $name (keys %{$commands}) {
            my $cmd = $commands->{$name};

            my $usage = format_usage($cmd->{usage});
            my $help  = $cmd->{help};

            Irssi::print "/$BASE_CMD $name $usage - $help";
        }

        Irssi::signal_stop();
    };

    Irssi::command_bind($BASE_CMD, sub {
        my ($data, $server, $item) = @_;
        $data =~ s/\s+$//g; # strip trailing whitespace.
        if ($data) {
            Irssi::command_runsub($BASE_CMD, $data, $server, $item);
        } else {
            show_help();
        }
    });

    Irssi::signal_add_first("default command $BASE_CMD", sub {
        show_help();
    });

    for my $name (keys %{$commands}) {
        my $cmd = $commands->{$name};

        Irssi::command_bind("$BASE_CMD $name", sub {
            my @args = split(' ', shift);

            if (scalar(@args) < num_required_args($cmd->{usage})) {
                show_help();
                return;
            }

            $cmd->{handler}(@args);
        });
    }
}

sub format_usage {
    my $usage = shift;

    join(' ', map {
      if ($_ =~ /^\[(.*)\]$/) {
        '[%U' . $1 . '%U]';
      } else {
        '%U' . $_ . '%U';
      }
    } @{$usage});
};

sub num_required_args {
    my $usage = shift;

    scalar(grep(!/^\[.*\]$/, @{$usage}));
}

1;
