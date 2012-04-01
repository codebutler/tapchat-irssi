# Irseas for Irssi

More information here soon.

## Installation

1. Install cpanmin.

        $ wget -O- http://cpanmin.us | perl - -l ~/perl5 App::cpanminus local::lib
        $ eval `perl -I ~/perl5/lib/perl5 -Mlocal::lib`
        $ echo 'eval `perl -I ~/perl5/lib/perl5 -Mlocal::lib`' >> ~/.bashrc

2. Install perl dependencies.

        $ cpanm JSON Protocol::WebSocket AnyEvent::Socket AnyEvent::Handle

3. Install irseas irssi script.

        $ mkdir -p ~/.irssi/scripts
        $ cd ~/.irssi/scripts
        $ git clone https://github.com/codebutler/irseas-irssi.git irseas
        $ ln -s ~/.irssi/scripts/irseas/irseas.pl ~/.irssi/scripts/irseas.pl

4. Generate self-signed SSL certificate.

        $ openssl req -new -x509 -days 365 -nodes -out ~/.irssi/irseas.pem -keyout ~/.irssi/irseas.pem

5. Load the script from within irsii:

        /run irseas