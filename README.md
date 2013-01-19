This is a perl script that addresses shortcomings in the noip2 linux client,
specifically that it will never force an update if our IP hasn't changed.
This is an issue on ISPs that have long lease times, as if you do not update
at least once per month no-ip will suspend your account.

This script uses screen scraping and relies heavily on the WWW::Mechanize and
HTML::DOM CPAN modules.  no-ip uses ssl on their site, so your perl will
also need Net::SSL installed, and you'll probably want Mozilla::CA as well.
Make sure you have your ca certificates working properly, otherwise SSL
requests will fail.  perldoc LWP::UserAgent for more details, pay particular
attention to HTTPS_CA_FILE or HTTPS_CA_DIR environments in case you need
to specify a location to a custom CA cert bundle pem file or a CA directory.

Configuration:

put your credentials in a file, either $HOME/no-ip-credentials.conf or pass the path to
the credentials file as the first argument on the command line.

format for the file is:
user:pass:hostname

Config options are at the top of the perl script, namely $nat and $force_update_interval .
