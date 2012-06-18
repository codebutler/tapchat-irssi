# TapChat for Irssi

<p style="font-size: 30px; font-weight: bold; color: red">THIS PROJECT IS DEPRECATED! Use <a href="https://github.com/codebutler/tapchat">this</a> instead!</p>


## Install

1. Install perl dependencies.
  
	Using APT:
	
		$ sudo apt-get install libanyevent-http-perl libnet-ssleay-perl libuuid-tiny-perl liburi-query-perl libauthen-passphrase-perl libdbd-sqlite3-perl libdbix-class-perl libcrypt-generatepassword-perl libcrypt-cbc-perl libcrypt-rijndael-perl libmime-base64-urlsafe-perl liburi-encode-perl
		
	or using [cpanminus](https://github.com/miyagawa/cpanminus#readme):
	
        $ cpanm JSON Protocol::WebSocket AnyEvent::Socket AnyEvent::HTTP AnyEvent::Handle AnyEvent::TLS Net::SSLeay UUID::Tiny URI::Query Authen::Passphrase DBD::SQLite DBIx::Migration Iterator::DBI Crypt::RandPasswd Data::ArrayList Crypt::CBC Crypt::Rijndael MIME::Base64 Data::URIEncode


3. Install TapChat irssi script.

        $ mkdir -p ~/.irssi/scripts/autorun
        $ git clone https://github.com/codebutler/tapchat-irssi.git ~/.irssi/scripts/tapchat
        $ ln -s ~/.irssi/scripts/tapchat/tapchat.pl ~/.irssi/scripts/tapchat.pl
        $ ln -s ~/.irssi/scripts/tapchat.pl ~/.irssi/scripts/autorun/tapchat.pl

4. Restart irssi or load the script.

        /run tapchat

5. Set a password:

        /tapchat configure your_password

	You'll need to open TCP/57623 on your firewall. You can change the port if you'd like:
	
        /set tapchat_port 12345
        /tapchat restart
        
6. Launch the app on your phone and connect!

## Push Notifications

TapChat will send push notifications to your phone when you are mentioned in a channel and when you receive a private message, but only if you're marked "away". Install the [screen_away](http://scripts.irssi.org/html/screen_away.pl.html) plugin for best results.
