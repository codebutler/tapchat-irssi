#!/usr/bin/perl

use strict;
use warnings;

use Term::ReadKey;
use Authen::Passphrase;
use Authen::Passphrase::BlowfishCrypt;
use YAML;

print "\nirseas-irssi configurator\n\n";

print "Port [3000]: ";
chomp(my $port = ReadLine(0));
if (!$port) {
  $port = 3000;
}

my $password;
do {
    print "Password: ";
    ReadMode('noecho');
    chomp($password = ReadLine(0));
    ReadMode('restore');
    print "\n";

} while (!$password);

my $ppr = Authen::Passphrase::BlowfishCrypt->new(
    cost        => 8,
    salt_random => 1,
    passphrase  => $password
);

my $config = {
  password => $ppr->as_rfc2307,
  port     => $port
};

my $config_file = $ENV{HOME} . "/.irssi/irseas.yml";

YAML::DumpFile($config_file, $config);

print "\nWrote $config_file\n\n";
