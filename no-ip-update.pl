#!/usr/bin/perl -w

# This is a perl script that addresses shortcomings in the noip2 linux client,
# specifically that it will never force an update if our IP hasn't changed.
# This is an issue on ISPs that have long lease times, as if you do not update
# at least once per month no-ip will suspend your account.

# This script uses screen scraping and relies heavily on the WWW::Mechanize and
# HTML::DOM CPAN modules.  no-ip uses ssl on their site, so your perl will
# also need Net::SSL installed, and you'll probably want Mozilla::CA as well.
# Make sure you have your ca certificates working properly, otherwise SSL
# requests will fail.  perldoc LWP::UserAgent for more details, pay particular
# attention to HTTPS_CA_FILE or HTTPS_CA_DIR environments in case you need
# to specify a location to a custom CA cert bundle pem file or a CA directory.

# Configuration:

# put your credentials in a file, either $HOME/no-ip-credentials.conf or pass the path to
# the credentials file as the first argument on the command line.

# format for the file is:
# user:pass:hostname

# Config options are at the top of the perl script, namely $nat and $force_update_interval .

my $nat = 1; # 1 for yes, 0 for direct

my $force_update_interval = 60*60*24*10; # seconds to wait to do a force update even if ip hasn't changed - default 10 days

use strict;
use WWW::Mechanize;
use HTML::DOM;
use Date::Parse;
use Net::SSL;
$Net::HTTPS::SSL_SOCKET_CLASS = "Net::SSL"; # Force use of Net::SSL
use Net::HTTPS;
use POSIX;

my $credentials_file = "";
if(scalar(@ARGV) == 1) {
  # pull config file path off the command line
  $credentials_file = $ARGV[0];
}
elsif  (exists($ENV{'HOME'})) {
  $credentials_file = $ENV{'HOME'}."/no-ip-credentials.conf";
}
else {
  print STDERR "You must create a credentials file!\n";
  exit 1;
}
my $credentials;
open my $infile, "<", $credentials_file || die "could not open config file: $credentials_file";
{
  local $/;
  $credentials = <$infile>;
}
close $infile;

$credentials =~ s/\s*\#.*\n//m; # remove comments
$credentials = mytrim($credentials);
my @args = split(/:/, $credentials);
if (scalar(@args) != 3) {
  print STDERR "config file not in user:pass:domain format\n";
  exit 1;
}

my ($user, $pass, $hostname) = map {mytrim($_)} @args;
my $noip_nat_check_url = "http://ip1.dynupdate.no-ip.com/";
my $current_ip = "";
if ($nat) {
  $current_ip = check_nat_ip($noip_nat_check_url);
}
else {
  $current_ip = check_local_ip();
}


my $mech = WWW::Mechanize->new() ;
my $response = $mech->get("https://www.noip.com/login/");

if ($response->is_success) {
  $mech->submit_form(
                     form_number => 2,
                     fields => {
                                username => $user,
                                password => $pass,
                                Login => 'Sign In',
                                submit_login_page => 1
                                }
                    );
  # check response
  check_errors($mech->content);
  $mech->follow_link( text => 'Manage Hosts' );
  my $domainlist = $mech->content;
  my $tree = HTML::DOM->new();
  $tree->write($domainlist);
  my @domains = $tree->getElementsByClassName('service-entry');
  my $found_it = 0;
  foreach my $domain(@domains) {
    my $domainname = mytrim($domain->cells->[0]->innerHTML);
    if ($domainname eq $hostname) {
      $found_it = 1;
      my $ip = mytrim($domain->cells->[1]->innerHTML);
      my ($modify_link) = $domain->cells->[2]->getElementsByTagName('a');
      my $href = $modify_link->href;
      $mech->follow_link(url => $href);
      if ($ip ne $current_ip || check_elapsed_time($mech->content) > $force_update_interval) {
        $mech->submit_form(fields => { 'host[ip]' => $current_ip });
        check_errors($mech->content);
      }
      else {
        print "skipping update\n";
      }
      last;
    }
  }
  if ($found_it) {
    print "updated successfully\n";
  }
  else {
    print "could not find the host\n";
  }
}
else {
  print STDERR $response->status_line, "\n";
}


sub mytrim {
  my ($instring) = @_;
  $instring =~ s/^\s+//s;
  $instring =~ s/\s+$//s;
  return $instring;
}
sub check_errors {
  my ($content) = @_;
  my $tree = new HTML::DOM;
  $tree->write($content);
  my $errortxt;
  my @errors = $tree->getElementsByClassName('errormessage');
  foreach my $error(@errors) {
    foreach my $insideP($error->getElementsByTagName('p')) {
      $errortxt .= mytrim($insideP->innerHTML);
    }
  }
  if ($errortxt) {
    die $errortxt;
  }
}

sub check_nat_ip {
  my ($url) = @_;
  my $mech = WWW::Mechanize->new();
  my $response = $mech->get($url);
  if ($response->is_success) {
    my $ip = mytrim($mech->content);
    return $ip;
  }
  die "Could not fetch $noip_nat_check_url";
}

sub check_local_ip {
  use IO::Socket::INET;
  my $sock = IO::Socket::INET->new(
                                   PeerAddr=> 'no-ip.com',
                                   PeerPort=> 80,
                                   Proto   => "tcp") or die "cannot connect to test";
  my $localip = $sock->sockhost;
  return $localip;
}

sub check_elapsed_time {
  my ($content) = @_;
  if ($content =~ /Last Update: (.*)/) {
    my $last_update = mytrim($1);
    if (my $last_update_ts = str2time($last_update)) {
      my $current_ts = POSIX::time();
      my $elapsed = $current_ts - $last_update_ts;
      return $elapsed;
    }
    else {
      die "error converting time\n";
    }
  }
  else {
    die "could not parse Last Update time\n";
  }
  return 0;
}
