# Irseas for Irssi

More information here soon.

## Installation

This process will be simplified in the future.

1. Install cpanmin.

        $ wget -O- http://cpanmin.us | perl - -l ~/perl5 App::cpanminus local::lib
        $ eval `perl -I ~/perl5/lib/perl5 -Mlocal::lib`
        $ echo 'eval `perl -I ~/perl5/lib/perl5 -Mlocal::lib`' >> ~/.bashrc

2. Install perl dependencies.

        $ cpanm JSON Protocol::WebSocket AnyEvent::Socket \
            AnyEvent::Handle AnyEvent::TLS Net::SSLeay \
            URI::Query Authen::Passphrase Term::ReadKey DBD::SQLite \
            DBIx::Migration Iterator::DBI Crypt::RandPasswd Data::ArrayList

3. Install irseas irssi script.

        $ mkdir -p ~/.irssi/scripts/autorun
        $ git clone https://github.com/codebutler/irseas-irssi.git ~/.irssi/scripts/irseas
        $ ln -s ~/.irssi/scripts/irseas/irseas.pl ~/.irssi/scripts/irseas.pl
        $ ln -s ~/.irssi/scripts/irseas.pl ~/.irseas/scripts/autorun/irseas.pl

4. Restart irssi or load the script.

        /run irseas

5. Set a password:

        /irseas configure your_password

	You'll need to open TCP/87623 on your firewall. You can change the port if you'd like:
	
        /set irseas_port 12345
        /irseas restart
        
6. Launch the app on your phone and connect!
