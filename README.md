# TapChat for Irssi

More information here soon.

## Installation

This process will be simplified in the future.

1. Install cpanmin.

        $ wget -O- http://cpanmin.us | perl - -l ~/perl5 App::cpanminus local::lib
        $ eval `perl -I ~/perl5/lib/perl5 -Mlocal::lib`
        $ echo 'eval `perl -I ~/perl5/lib/perl5 -Mlocal::lib`' >> ~/.bashrc

2. Install perl dependencies.

        $ cpanm JSON Protocol::WebSocket AnyEvent::Socket AnyEvent::HTTP \
            AnyEvent::Handle AnyEvent::TLS Net::SSLeay UUID::Tiny \
            URI::Query Authen::Passphrase Term::ReadKey DBD::SQLite \
            DBIx::Migration Iterator::DBI Crypt::RandPasswd Data::ArrayList \
            Crypt::CBC Crypt::Rijndael MIME::Base64 Data::URIEncode MIME::Base64

3. Install TapChat irssi script.

        $ mkdir -p ~/.irssi/scripts/autorun
        $ git clone https://github.com/codebutler/tapchat-irssi.git ~/.irssi/scripts/tapchat
        $ ln -s ~/.irssi/scripts/tapchat/tapchat.pl ~/.irssi/scripts/tapchat.pl
        $ ln -s ~/.irssi/scripts/tapchat.pl ~/.tapchat/scripts/autorun/tapchat.pl

4. Restart irssi or load the script.

        /run tapchat

5. Set a password:

        /tapchat configure your_password

	You'll need to open TCP/87623 on your firewall. You can change the port if you'd like:
	
        /set tapchat_port 12345
        /tapchat restart
        
6. Launch the app on your phone and connect!
