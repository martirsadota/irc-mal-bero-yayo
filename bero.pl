#!/system/xbin/perl -w
#-----------------------------------------------------
# Berochoro-v3/Perl:Frame
# A rewrite of Bero
# (which ended up exactly the same
#   as the old one D:)
#-----------------------------------------------------
# IRC MAL Parser bot
# Standalone version
# uses the "official" MAL API for searches
# uses the "unofficial" MAL API at http://mal-api.com
# NOW uses the JSON module
#-----------------------------------------------------
# Searches anime and manga
#  .mal -- usage help
#  .mal -a <searchterm> -- search anime
#      .mal -a <search term> /<result_number>
#           -- detailed info about a result
#  .mal -m <searchterm> -- search anime
#      .mal -m <search term> /<result_number>
#           -- detailed info about a result
#  .mal -u <username>   -- quick overview of a user
# (.mal <searchterm> works the same as
#         .mal -a <searchterm>)
#-----------------------------------------------------
# TODO: -- Some refinements
#       -- "View All Results"
#-----------------------------------------------------

my $waifu = 'Takatsuki Yayoi'; # Perl is so lulz

my $test = (defined($ARGV[0]) and lc($ARGV[0]) eq '--test') ? 1 : 0;
#$SIG{__WARN__} = sub {} if not $test;

use strict;
use warnings;

use Carp; # the thinking cap
use Data::Dumper;
use Time::HiRes qw( gettimeofday alarm nanosleep );
use IO::Socket;
my  $sock;
#use utf8;
use Encode qw(encode decode);
use feature 'unicode_strings';
use JSON;
use HTTP::Tiny;
use HTML::Entities;
use URI::Escape;
use Time::Piece;
use Time::Seconds;


# **----- CONFIG SECTION -----** #

# Network info
 # Server address
 my $server = "irc.rizon.net";
 # Server port
 my $port   = 6667;
 # Server password; leave empty if the server doesn't use one
 my $pass   = "";

# Bot Info
 # Primary nick
 my $pnick = "";
 # Alternate nick, used when the primary nick is not available
 my $anick = "";
 # Ident
 my $ident = "";
 # Real name
 my $rname = "";
 # NickServ password; leave empty if not using one
 my $nspwd = "";

# Channels to join
 my @channels = (
  );
 
# Other Bot Info
 # Bot version
 my $botver = "2.5.16";
 # CTCP VERSION reply string
 my $versionReply = "Berochoro-v3/Perl $botver | MAL Parser 1.9.14";
 # QUIT message
 my $quitmsg = "";
 
# Admin & HL Options
 # Hosts of bot admins
 my @admin_hosts = (
 );
 
 my @hardban_nicks = (
 );
 
 my @hardban_hosts = (
 );
 
 # Time to wait for a server response before declaring a ping timeout (in seconds)
 my $pingTimeout = 240;
 # Interval between reconnect attempts (in seconds)
 my $reconInterval = 10;
 # Maximum reconnect retries
 my $maxReconRetries = 25;
 # Maximum rejoin retries when kicked
 my $maxKickRetries = 20;

# **----- END OF CONFIG SECTION -----** #

##################################
## CODE MEAT, don't touch unless
##  you know what you are doing.
## ;)
##################################

# Internal vars

my $rejoinRetries = 0;
my $reconRetries = 0;

my $iQuit = 0;

my $nick = $pnick;

# Bero-specific vars
my $floodprot;
my $interval;

my %opts = (
    timeout         => 30,
    agent           => "",
    default_headers => {
                         Authorization => "",
                         'Cache-Control' => 'no-cache',
                       }
);

my %optsna = (
    timeout         => 5,
    agent           => "Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_6_3; en-us) AppleWebKit/533.16 (KHTML, like Gecko) Version/5.0 Safari/533.16",
);

my %optssc = (
    timeout         => 30,
    agent           => "",
    default_headers => {
                         'Cache-Control' => 'no-cache',
                       }
);

# Open filehandles
open (my $runlog,">>","$ENV{HOME}/yayoi/bero/berolog.log") or warn "Cannot open log file: $!\n";

MAINLOOP:
eval {

local $SIG{ALRM} = sub {
  die "Possible ping timeout: disconnecting.\n";
 };
 
while (1) {
 
# Connect to the IRC server.
$sock = new IO::Socket::INET(PeerAddr => $server,
                                  PeerPort => $port,
                                    Proto => 'tcp')
                                      or die "[(" . &timestamp . ")|*ERROR] Can\'t connect to the server: $!."; 
 
# Log on to the server.
&sendRaw("NICK $nick");
&sendRaw("USER $ident blah blah :$rname");
&sendRaw("PASS $pass") if ($pass ne "");
alarm($pingTimeout);

# Read lines from the server.
while (my $input = <$sock>) {
 $input =~ s/\r\n?$//;
   # print "$input\n";
    # Keep oueselves alive
    if ($input =~ /^PING :?(.*)$/i) {
     print $sock "PONG $1\r\n";
     &resetTimeout;
    }
    # Check for joins
    elsif ($input =~ m/^:(.*?)!(.*?)@(.*?) JOIN :(\#.*)$/) {
      &handle_join($1,$2,$3,$4);
    }
    # Check for CTCPs
    elsif ($input =~ m/^:(.*?)!(.*?)@(.*?) PRIVMSG $nick :\x01(.*)\x01$/) {
      &handle_ctcp($1,$2,$3,$4);
    }
    # Check for PMs
    elsif ($input =~ m/^:(.*?)!(.*?)@(.*?) PRIVMSG $nick :(.*)$/) {
      &handle_pm($1,$2,$3,$4);
    }
    # Check for notices
    elsif ($input =~ m/^:(.*?)!(.*?)@(.*?) NOTICE $nick :(.*)$/) {
      &handle_notice($1,$2,$3,$4);
    }
    # Check for channel actions
    elsif ($input =~ m/^:(.*?)!(.*?)@(.*?) PRIVMSG (\#.*?) :\x01ACTION (.*)\x01$/) {
      &handle_chanaction($1,$2,$3,$4,$5);
    }
    # Check for channel messages
    elsif ($input =~ m/^:(.*?)!(.*?)@(.*?) PRIVMSG (\#.*?) :(.*)$/) {
      &handle_chanmsg($1,$2,$3,$4,$5);
    }
    # Check for kicks
    elsif ($input =~ m/^:(.*?)!(.*?)@(.*?) KICK (\#.*?) (.*?) :(.*)$/) {
      &handle_kick($1,$2,$3,$4,$5,$6);
    }
    # Check for raw server messages
    elsif ($input =~ m/^:(.*?) (\d\d\d) $nick (.*)/) {
      &handle_srvmsg($1,$2,$3);
    }
    elsif ($input =~ /^ERROR :Closing Link: .*? \((.*)\)/) {
    if ($1 =~ /^Quit: (.*)/) {
      exit;
      } else {
          if ($iQuit) {
            exit;
           } else {
            }
         }
       } 
  }

  $sock -> close if defined ($sock);
  nanosleep(&nss(10));
  alarm(0);

 }
};

my $deko = $@; # DEATH!
alarm(0);

if ($deko =~ /Possible ping timeout: disconnecting./) {
  $sock -> close if defined ($sock);
  $reconRetries++;
  if ($reconRetries > $maxReconRetries) {
    exit(5);
  } else {
    nanosleep(&nss(10));
    goto MAINLOOP;
  }
 } elsif ($deko =~ /ERROR. Can.t connect to the server: (.*?)\n?/) {
    $reconRetries++;
    if ($reconRetries > $maxReconRetries) {
      exit(5);
    } else {
      nanosleep(&nss(10));
      goto MAINLOOP;
    } 
   } else {
     my $st = localtime();
     print $runlog "[",$st->strftime(),"|*ERROR] Eval block died; bot disconnected: $deko\n";
	 print STDERR "$deko\n" if $test;
     nanosleep(&nss(10));
     goto MAINLOOP;
     #confess($@);
     #exit(3);
    }


# **----- SUBROUTINES -----** #
# Event handler subs
sub handle_chanmsg {
 my ($snick,$sident,$shost,$tchan,$msg) = @_;
 if ($msg =~ /^(\.mal.*)$/i and not(grep {$_ eq $snick} (@hardban_nicks) or grep {$_ eq $shost} (@hardban_hosts))) { &trigger($snick,$1,$tchan); &resetTimeout;}
 elsif ($msg =~ /^$nick(,|:) introduce yourself|^!yayointro$/i and grep { $_ eq &stripcode($shost) } (@admin_hosts) ) { &detailed_info(56807,'character',$tchan); &resetTimeout; }
 elsif ($msg =~ /^!whodid (.*)$/i and not(grep {$_ eq $snick} (@hardban_nicks) or grep {$_ eq $shost} (@hardban_hosts))) { &whodid($tchan,$snick,$1); &resetTimeout; }
 elsif ($msg =~ /^$nick(,|:) do you know ((of )?me|who (am I|I am))+\?$/i) { &mal_search ($snick, $tchan, &spaceit($snick), 'character', 'search', 'whoami'); }
 elsif ($msg =~ /^.vndb (.*?) \/(\d+)$/i) { &mal_search ($snick, $tchan, $1, 'vndb', 'info', ($2-1)); }
 elsif ($msg =~ m{(?:http://)?myanimelist\.net/(anime|manga|character|people)/(\d+)}i) { &detailed_info ($2, $1, $tchan, 1,1); }
 elsif ($msg =~ /^.vndb (.*)$/i) { &mal_search ($snick, $tchan, $1, 'vndb', 'search', ''); }
}

sub handle_chanaction {
 my ($snick,$sident,$shost,$tchan,$msg) = @_;
}

sub handle_pm {
 my ($snick,$sident,$shost,$msg) = @_;
 if (grep { $_ eq &stripcode($shost) } @admin_hosts) {
    &puppet($msg,$snick);
    &resetTimeout;
  }
}

sub handle_notice {
 my ($snick,$sident,$shost,$msg) = @_;
}
 
sub handle_ctcp {
  my ($snick,$sident,$shost,$type) = @_;
  if (uc($type) eq "VERSION") {
    &sendNotice($snick,"\x01VERSION $versionReply\x01");
  }
  elsif ($type =~ /^PING (.*)$/i) {
    &sendNotice($snick,"\x01PING $1\x01");
  }
 }

sub handle_srvmsg {
 my ($host,$numeric,$msg) = @_;
 if ($numeric eq "433") {
   # Nick already in use
   ($nick, $anick) = ($anick, $nick);
   &sendRaw("NICK $nick");
   &sendRaw("USER $ident blah blah :$rname");
 }
 elsif ($numeric eq "004") {
   # Login completed
   &sendRaw("AWAY :MAL searchbot, developed and maintained by <devname here>");
   &resetTimeout;
 }
 elsif ($numeric eq "376") {
   # End MOTD
    # NickServ auth
     if ($nspwd ne "") {
       &sendSay ("NickServ","IDENTIFY $nspwd ");
      }
    # Join channels
     if ($test) {
       &sendRaw ("JOIN #pongangpulubi");
     } else {
       foreach my $i (@channels) {
         &sendRaw ("JOIN $i");
        }
      }
    # Reset ping timeout timer
     &resetTimeout;
    # GHOST the primary nick
     if ($nick ne $pnick) {
       ($nick,$anick) = ($anick,$nick);
       &sendSay("NickServ","GHOST $pnick");
       &sendRaw("NICK $nick");
      }
 }
 elsif ($numeric eq "474" && $msg =~ /(\#.*) :Cannot join/i) {
   # Banned
   
 }
 elsif ($numeric eq "366" and $msg =~ /(\#.*?) :End/) {
   # /NAMES list end
 }
}

sub handle_join {
 my ($snick,$sident,$host,$tchan) = @_;
 if ($snick eq $nick) {
 
if (not defined($floodprot->{$tchan})) {
 $floodprot->{$tchan} = {
   mal    => 0
  };
}

if (not defined($interval->{$tchan})) {
  $interval->{$tchan} = {
   mal    => 7
 };
}

 }
} # sub handle_join END
 
sub handle_kick {
 my ($snick,$sident,$host,$tchan,$tnick,$reason) = @_;
 if ($tnick eq $nick) {
   nanosleep(nss(3));
   &sendRaw("JOIN $tchan");
 }
}

# Trigger subroutines
sub whodid {
my ($chan,$snick,$term) = @_;

my ($title,$id,$res) = &Meruru($term);
my $sep = "\x02\x0313::\x0F";
my $line;
my $max;
my $err;

$title = &cleanup($title);

if (not defined($res)) {
  $err = 1;
  $line = "\x02\x0304::\x0F \x02うっうぅ~！\x02 \x02\x0304::\x0F I can't find a show matching that keyword. \x02\x0304::\x0F";
  #$line = "\x02\x0304::\x0F \x02うっうぅ~！\x02 \x02\x0304::\x0F My info servers be a-derpin'; please don't use this command until the problem has been fixed. \x02\x0304::\x0F";
} elsif (scalar(@$res) == 0) {
  $err = 1;
  $line = "\x02\x0304::\x0F \x02うっうぅ~！\x02 \x02\x0304::\x0F I can't find fansubbers for that show! \x02\x0304::\x0F";
} else {
# real meat
  $line = "$sep Fansub groups for \x02$title\x02 $sep";
  $max = (scalar(@$res) > 5) ? 4 : (scalar(@$res) - 1);
  foreach my $i (@{$res}[0..$max]) {
    $line .= " \x02$i->{name}\x02 $i->{sname} [\x0303+$i->{appr}\x03 / \x0304-$i->{disap}\x03 \x0315($i->{rating}/10)\x03] $sep";
  }
}

$max+=1;
my $ss = ($max == 1) ? '' : 's';

&sendSay($chan,$line);
&sendNotice($snick,"Showing $max result$ss; for more info, visit this show's MAL page at http://myanimelist.net/anime/$id \x02::\x02 Not the show you're looking for? Search MAL at http://myanimelist.net/anime.php or use \x02.mal <search term>\x02.") if not $err;
}

sub Meruru {
my $searchterm = shift;
my $searchtermwf = uri_escape($searchterm);

my @mess;

my @results;
my $title;
my $info_id;

my $response = HTTP::Tiny->new(%opts)->get("http://myanimelist.net/api/anime/search.xml?q=$searchtermwf");

if ($response->{success}) {
  @results = @{&Rorona($response->{content})};
  if (scalar(@results) > 0) {
    @results = sort { &weight($b,'whodid') <=> &weight($a,'whodid') } @results;
    $info_id = $results[0]->{id};
    $title = $results[0]->{title};
    $response = HTTP::Tiny->new(%optssc)->get("http://myanimelist.net/anime/$info_id");
    if ($response->{success}) {
      while ($response->{content} =~
                        m{\s+<a.href=./fansub-groups.php.*?>(.*?)</a>\s*?<small>(\[.*?\])</small>.*
                        class=.lightLink.><small>(\d+)\sof\s(\d+)\susers\sapprove</small></a>}ixgc) {
                            push (@mess,{ name => $1, sname => $2,
                                          appr => $3, disap => $4 - $3,
                                          rating => sprintf('%.2f',($3/$4) * 10 )}
                                 );
                         }
    } else {
      return [];
    }
  } else {
    # Insert Wilbell code here
    return [];
  }
} else {
  return undef;
}
                   
return ($title,$info_id,\@mess);
}

sub trigger {
 my ($tnick,$msg,$chan) = @_;
  if (!defined($floodprot->{$chan}->{mal}) || (&now - $floodprot->{$chan}->{mal}) > $interval->{$chan}->{mal}) {
   if     ($msg =~ /^\.mal$/)                      { &mal_help ($tnick); }
   elsif  ($msg =~ /^\.mal -m (.*?) \/(\d+)$/i)    { &mal_search ($tnick, $chan, $1, 'manga', 'info', ($2-1)); }
   elsif  ($msg =~ /^\.mal -m (.*)$/i)             { &mal_search ($tnick, $chan, $1, 'manga', 'search', ''); }
   elsif  ($msg =~ /^\.mal -p (.*?) \/(\d+)$/i)    { &mal_search ($tnick, $chan, $1, 'people', 'info', ($2-1)); }
   elsif  ($msg =~ /^\.mal -p (.*)$/i)             { &mal_search ($tnick, $chan, $1, 'people', 'search', ''); }
   elsif  ($msg =~ /^\.mal -c (.*?) \/(\d+)$/i)    { &mal_search ($tnick, $chan, $1, 'character', 'info', ($2-1)); }
   elsif  ($msg =~ /^\.mal -c (.*)$/i)             { &mal_search ($tnick, $chan, $1, 'character', 'search', ''); }
   elsif  ($msg =~ /^\.mal -um (.*)$/i)            { &detailed_info ($1, 'profile-manga', $chan); }
   elsif  ($msg =~ /^\.mal -u (.*)$/i)             { &detailed_info ($1, 'profile', $chan); }
   elsif  ($msg =~ /^\.mal (-a )?(.*?) \/(\d+)$/i) { &mal_search ($tnick, $chan, $2, 'anime', 'info', ($3-1)); }
   elsif  ($msg =~ /^\.mal (-a )?(.*)$/i)          { &mal_search ($tnick, $chan, $2, 'anime', 'search', ''); }
  }
 }
 
sub mal_search {
my ($tnick, $chan, $searchterm, $searchtype, $flag, $num) = @_;

#if ($searchterm =~ /^-i (\d+)$/i and $searchtype ne 'profile') {
#   &detailed_info ($1, $searchtype, $chan);
#   return undef;
#}

my $searchtermwf;
eval { $searchtermwf = uri_escape($searchterm); };
if ($@) { $searchtermwf = uri_escape_utf8($searchterm); }
my $response;
my $results;

if ($searchtype eq 'vndb') {
$searchtermwf =~ s/%20/+/g;
$response = HTTP::Tiny->new()->get("http://vndb.org/v/all?sq=$searchtermwf");
$results = &Escha($response -> {content});
} elsif (grep { $_ eq $searchtype } ('anime','manga')) {
$response = HTTP::Tiny->new(%opts)->get("http://myanimelist.net/api/$searchtype/search.xml?q=$searchtermwf");
$results = &Rorona($response -> {content});
} else {
  $response = HTTP::Tiny->new(%optssc)->get("http://myanimelist.net/$searchtype\.php?q=$searchtermwf");
  $results = &Totori($response->{content}, $searchtype);
 }

my $ct = 0;
my $bit = ($searchtype eq 'manga') ? '-m ' : ($searchtype eq 'people') ? '-p ' : ($searchtype eq 'character') ? '-c ' : '';
my $trig = ($searchtype eq 'vndb') ? 'vndb' : 'mal';
my $spage = ($searchtype eq 'vndb') ? "http://vndb.org/v/all?sq=$searchtermwf" : "http://myanimelist.net/$searchtype.php?q=$searchtermwf";

# print $response->{content};
  if (scalar(@$results) == 0) {
   # nothing found
   if ($searchtype ne 'vndb' and defined(my $g_id = &Wilbell($searchterm,$searchtype))) {
     &detailed_info($g_id,$searchtype,$chan);
   } else {
     &sendSay($chan,"\x02\x0304::\x0F \x02うっうぅ~！\x02 \x02\x0304::\x0F I can't find anything matching that keyword. \x02\x0304::\x0F");
   }
   $floodprot->{$chan}->{mal} = &now;
  } else {
  foreach my $i (@$results) {

    my $data = &Ayesha ($i, $searchtype, $ct, scalar(@$results));
                    
     if ($flag eq "search" or ($flag eq "info" and scalar(@$results) == 1)) {
       # Xchat:prnt("\x0303*DEBUG\x0F\t\$ct is: $ct");
       if (scalar(@$results) == 1) {
         # 1 show found; print complete details
            if (grep { $_ eq $searchtype } ('anime','manga','character')) {
              &detailed_info ($i->{id}, $searchtype, $chan);
            } else {              
              &sendSay($chan,"$data->{info_line_1}");
              &sendSay($chan,"$data->{info_line_2}") if defined($data->{info_line_2});
            }
          } elsif (scalar(@$results) > 1 && scalar(@$results) <= 3) {
              # 2-3 shows found; print summaries for them all
              &sendSay($chan,"$data->{result_line}");
              if ($ct == (scalar(@$results) - 1)) { &sendNotice($tnick,scalar(@$results) . " results found; to view detailed info about a particular result, use \x02.$trig $bit$searchterm /<result_number>\x02."); }
             } else {
                # more than 3 shows found; print summaries of first 3
                if ($ct < 2) { &sendSay($chan,"$data->{result_line}"); }
                if ($ct == 2) { &sendSay($chan,"$data->{result_line}"); &sendNotice($tnick,"Showing first 3 of ". scalar(@$results) . " results found; to view detailed info about a particular result, use \x02.$trig $bit$searchterm /<result_number>\x02. You can also visit the search page at $spage"); }
               }
           } elsif ($flag eq "info") {
             # Xchat:prnt("\x0303*DEBUG\x0F\t\$ct is: $ct");
               if ($num >= 0 and $num <= scalar(@$results)){
                  if ($ct == $num) {
                    # 1 show found; print complete details
                      &detailed_info ($i->{id}, $searchtype, $chan);
		              }
                } else {
                  if    ($num < 0 && $ct == 0) { &sendNotice($tnick,"\x02\x0304Error:\x02\x03 It starts with 1, heh heh."); }
                  elsif ($num > scalar(@$results) && $ct == 0) { &sendNotice($tnick,"\x02\x0304Error:\x02\x03 Only " . scalar(@$results) . "results found."); }
                 }
             }
            $ct++;
          }
       $floodprot->{$chan}->{mal} = &now;
     }
   }

sub detailed_info {
my ($info_id, $searchtype, $chan, $parse) = @_;
local $, = ' ';
print @_,"\n" if $test;
my $data;
my $response;
my $err = 0;

if (grep { $_ eq $searchtype } ('anime','manga','profile','profile-manga')) {
  #$response = HTTP::Tiny->new(%optsna)->get("http://mal-api.com/$searchtype/$info_id");
  #eval { local $@; $data = &Ayesha(decode_json ($response -> {content}), $searchtype, $info_id, 1); };
  #if ($@) {
   #local $@;
   #print "DEBUG: Grabbing info via API failed; trying via scrape...\n" if ($test);
   my $searchkey = ($searchtype eq 'profile-manga') ? 'profile' : $searchtype;
   eval { $data = &Ayesha(&Totori (HTTP::Tiny->new(%optssc)->get("http://myanimelist.net/$searchkey/$info_id")->{content}, $searchtype), $searchtype, $info_id, 1); };
   if ($@) { 
     $err = 1;
     print "$@\n" if $test;
     &sendSay($chan,"\x02\x0304::\x0F \x02うっうぅ~！\x02 \x02\x0304::\x0F My info servers be a-derpin'; please don't use this command until the problem has been fixed. \x02\x0304::\x0F") unless ($parse);
   }
  #}
} elsif ($searchtype eq 'vndb') {
  $data = &Ayesha(&Escha(HTTP::Tiny->new->get("http://vndb.org/$info_id")->{content})->[0], $searchtype, $info_id, 1);
  
} else {
  $response = HTTP::Tiny->new(%optssc)->get("http://myanimelist.net/$searchtype/$info_id");
  $data = &Ayesha(&Totori($response->{content}, $searchtype)->[0], $searchtype, $info_id, 1);
}

    if (defined($data)) {
	 if ($parse) {
	  &sendSay($chan,"$data->{parse_line}");
	 } else {
      &sendSay($chan,"$data->{info_line_1}");
      &sendSay($chan,"$data->{info_line_2}") if (defined($data->{info_line_2}));
	 }
    } else {
     &sendSay($chan,"\x02\x0304::\x0F \x02うっうぅ~！\x02 \x02\x0304::\x0F I can't find a profile with that username. \x02\x0304::\x0F") if ($searchtype eq 'profile' or $searchtype eq 'profile-manga' and !$err);
    }
    
  $floodprot->{$chan}->{mal} = &now;
}

# **** --- HELP SUBROUTINE --- **** #

sub mal_help {
my $tnick = shift;
&sendNotice($tnick,"Search MyAnimeList.net");
&sendNotice($tnick,"\x02.mal <anime title>\x02 or \x02.mal -a <anime title>\x02 - Search anime");
&sendNotice($tnick,"\x02.mal -m <manga title>\x02 - Search manga");
nanosleep(&nss(0.75));
&sendNotice($tnick,"\x02.mal -u <username>\x02 - View quick info about a user");
&sendNotice($tnick,"\x02.mal -um <username>\x02 - View quick info about a user (displaying manga stats instead)");
&sendNotice($tnick,"\x02.mal -p <name>\x02 - Search for people in the anime industry (like seiyuu)");
&sendNotice($tnick,"\x02.mal -c <name>\x02 - Search for info about an anime/manga character");
}

# **** --- INTERNAL SUBROUTINES --- **** #
# *** The Atelier Alchemists synthesize data into "prettified" forms *** #

sub Ayesha {
 # ** Ayesha-chan, the Alchemist of Dusk
 # ** The Grand Data Formatter
 
 my ($data, $type, $ct, $total) = @_;
 print Dumper($data) if $test;

 my @months = ("","January","February","March","April","May","June","July","August","September","October","November","December");
 my $sep = "\x02\x0303::\x0F";
 my $mal = "\x02\x0300,12 MyAnimeList \x0F";
 
# -------------- ANIME -------------------#
 if ($type eq 'anime') {
    # Set dates
    if (defined($data->{start_date}) and $data->{start_date} =~ /(\d\d\d\d)-(\d\d)-(\d\d).*/) { $data->{start_date} = "$months[$2] $3, $1"; }
    if (defined($data->{end_date}) and $data->{end_date} =~ /(\d\d\d\d)-(\d\d)-(\d\d).*/) { $data->{end_date} = "$months[$2] $3, $1"; }
    
    if    (!defined($data->{start_date}) and !defined($data->{end_date})) { $data->{air_dates} = "\x02Airing\x02 ?"; }
    elsif (lc($data->{status}) eq 'not yet aired' and defined($data->{start_date})) { $data->{air_dates} = "\x02Airing\x02 $data->{start_date}"; }
    elsif ($data->{status} =~ /^(currently )?airing/i and defined($data->{end_date})) { $data->{air_dates} = "\x02Airing\x02 $data->{start_date} to $data->{end_date}"; }
    elsif (!defined($data->{end_date})) { $data->{air_dates} = "\x02Started Airing\x02 $data->{start_date}"; }
    elsif ($data->{start_date} eq $data->{end_date}) { $data->{air_dates} = "\x02Aired\x02 $data->{end_date}"; }
    else  { $data->{air_dates} = "\x02Aired\x02 $data->{start_date} to $data->{end_date}"; }
    
    $data->{episodes} = "?" if (!defined ($data->{episodes}) or $data->{episodes} == 0);
    $data->{rank} = (defined ($data->{rank})) ? " (Ranked #$data->{rank})" : '';
	$data->{producers} = (defined ($data->{producers})) ? $data->{producers}->[0] : 'Unknown';
    
    # clean up
    $data->{title} = &cleanup($data->{title});
    $data->{synopsis} = &cleanup($data->{synopsis});
                
    # trim the synopsis
    # Xchat:prnt("\x0303*DEBUG\x0F\tLength of \$data->{synopsis} is: " . length($data->{synopsis}));
    if (length ($data->{synopsis}) > 325) {
     $data->{synopsis} =~ s/ ...$//;
     $data->{synopsis} =~ s/(.{325}).*/$1/;
     $data->{synopsis} = "$data->{synopsis}...";
    }
     
    $data->{status} =~ s/\b(\w)/\u$1/g if (defined($data->{status})) or $data->{status} = "N/A";
    
    # Xchat:prnt("\x0303*DEBUG\x0F\t\$data->{genres} is: $data->{genres}");
    if (ref $data->{genres} eq 'ARRAY' && scalar (@{$data->{genres}}) > 0) { $data->{genres} = join (', ',@{$data->{genres}}); }
    else { $data->{genres} = "--"; }
     
    if (defined($data->{other_titles} -> {japanese} -> [0])) { $data->{jp_title} = " (" . $data->{other_titles} -> {japanese} -> [0] . ")"; }
    else { $data->{jp_title} = ""; }
    
    $data = {
      info_line_1 => "$sep [Anime] \x02$data->{title}\x02$data->{jp_title} $sep \x02Type\x02 $data->{type} $sep \x02Status\x02 $data->{status} $sep \x02Episodes\x02 $data->{episodes} $sep $data->{air_dates} $sep \x02Members' Score\x02 $data->{members_score}/10$data->{rank} $sep \x02Genres\x02 $data->{genres} $sep \x02Classification\x02 $data->{classification} $sep",
      info_line_2 => "$sep \x02Synopsis\x02 $data->{synopsis} $sep \x02Link\x02 http://myanimelist.net/anime/$data->{id} $sep",
      result_line => "$sep [" . ($ct + 1) . "/" . $total . "][Anime] \x02$data->{title}\x02 $sep \x02Type\x02 $data->{type} $sep \x02Members' Score\x02 $data->{members_score}/10 $sep \x02Episodes\x02 $data->{episodes} $sep \x02Link\x02 http://myanimelist.net/anime/$data->{id} $sep",
	  parse_line  => "$mal $sep [Anime] \x02$data->{title}\x02$data->{jp_title} $sep \x02Type\x02 $data->{type} $sep \x02Status\x02 $data->{status} $sep \x02Episodes\x02 $data->{episodes} $sep \x02Genres\x02 $data->{genres} $sep \x02Members' Score\x02 $data->{members_score}/10$data->{rank} $sep"
     };

    return $data;
    }
# -------------- MANGA -------------------#
   elsif ($type eq 'manga') {
    $sep = "\x02\x0302::\x0F";
     
    # clean up
    $data->{title} = &cleanup($data->{title});
    $data->{synopsis} = &cleanup($data->{synopsis});
    
    # trim the synopsis
    # Xchat:prnt("\x0303*DEBUG\x0F\tLength of \$data->{synopsis} is: " . length($data->{synopsis}));
    if (length ($data->{synopsis}) > 325) {
     $data->{synopsis} =~ s/ ...$//;
     $data->{synopsis} =~ s/(.{325}).*/$1/;
     $data->{synopsis} = "$data->{synopsis}...";
    }

    $data->{rank} = (defined ($data->{rank})) ? " (Ranked #$data->{rank})" : '';
    
    # set some stats
    $data->{volumes} = "?" if (!defined ($data->{volumes}) or $data->{volumes} == 0);
    $data->{chapters} = "?" if (!defined ($data->{chapters}) or $data->{chapters} == 0);
    
    # Xchat:prnt("\x0303*DEBUG\x0F\t\$data->{genres} is: $data->{genres}");
    if (ref $data->{genres} eq 'ARRAY' && scalar (@{$data->{genres}}) > 0) { $data->{genres} = join (', ',@{$data->{genres}}); }
    else { $data->{genres} = "--"; }
    
    if (defined($data->{other_titles} -> {japanese} -> [0])) { $data->{jp_title} = " (" . $data->{other_titles} -> {japanese} -> [0] . ")"; }
    else { $data->{jp_title} = ""; }
    
    $data->{status} =~ s/\b(\w)/\u$1/g if (defined($data->{status})) or $data->{status} = "N/A";
     
     $data = {
      info_line_1 => "$sep [Manga] \x02$data->{title}\x02$data->{jp_title} $sep \x02Type\x02 $data->{type} $sep \x02Status\x02 $data->{status} $sep \x02Volumes\x02 $data->{volumes} $sep \x02Chapters\x02 $data->{chapters} $sep \x02Members' Score\x02 $data->{members_score}/10$data->{rank} $sep \x02Genres\x02 $data->{genres} $sep",
      info_line_2 => "$sep \x02Synopsis\x02 $data->{synopsis} $sep \x02Link\x02 http://myanimelist.net/$type/$data->{id} $sep",
      result_line => "$sep [" . ($ct + 1) . "/" . $total . "][Manga] \x02$data->{title}\x02 $sep \x02Type\x02 $data->{type} $sep \x02Members' Score\x02 $data->{members_score}/10 $sep \x02Volumes\x02 $data->{volumes} $sep \x02Chapters\x02 $data->{chapters} $sep \x02Link\x02 http://myanimelist.net/$type/$data->{id} $sep",
	  parse_line  => "$mal $sep [Manga] \x02$data->{title}\x02$data->{jp_title} $sep \x02Type\x02 $data->{type} $sep \x02Status\x02 $data->{status} $sep \x02Genres\x02 $data->{genres} $sep \x02Members' Score\x02 $data->{members_score}/10$data->{rank} $sep"
     };
     
    return $data;
    }
# -------------- USERS -------------------#
   elsif ($type eq 'profile') {
     $sep = "\x02\x0306::\x0F";
     my $now = localtime;
     
     # grab some extra data
     my $recent = HTTP::Tiny->new(%optssc)->get("http://myanimelist.net/rss.php?type=rwe&u=$ct")->{content};
	 # print $recent,"\n" if $test;
     # GAWD I HATE DOING THIS
     # XML MODULE Y U NO WERK
     if ($recent =~ /
          \s+<item>\n
          \s+<title>(?<title>.*)<\/title>\n
		  \s+<link>.*\n
		  \s+.*\n
		  \s+<description><!\[CDATA\[(?<description>.*)\]\]><\/description>\n
		  \s+<pubDate>(?<date>.*)<\/pubDate>\n
		  \s+<\/item>
		  /x) {
		     $data->{recent}->{title} = $+{title};
		     $data->{recent}->{description} = $+{description};
		     $data->{recent}->{date} = ($now - Time::Piece->strptime($+{date}, '%a, %d %b %Y %T %z'))->pretty;
		     undef $recent;
		    }

     if (!defined($data->{recent}->{title})) { 
         $data->{recent} = "$sep";
     } else {
       # clean the title
       $data->{recent}->{title} = &cleanup($data->{recent}->{title});
       # format eps
       if ($data->{recent}->{description} !~ /Plan to watch/i) { $data->{recent}->{description} =~ s/(.*?) - (\d+|\?) of (\d+|\?)( episodes)?/\[$1 \($2\/$3\)\]/i; }
       else { $data->{recent}->{description} = "[Plan to Watch]"; }
       # format the entire thing
       $data->{recent} = "$sep \x02Recent Anime\x02 $data->{recent}->{title} $data->{recent}->{description} ($data->{recent}->{date} ago) $sep";
      }
	  
     # pre-format
     if (!defined ($data->{anime_stats})) {
       return undef;
     } else {
     $data->{anime_stats} = join ('',
        "\x02Anime List Entries\x02 ",
        $data->{anime_stats}->{total_entries}, ' [',
        join ('/',
          $data->{anime_stats}->{watching},
          $data->{anime_stats}->{completed},
          $data->{anime_stats}->{plan_to_watch},
          $data->{anime_stats}->{on_hold},
          $data->{anime_stats}->{dropped}
         ), ']',
        " $sep \x02Time Spent Watching\x02 ",
        $data->{anime_stats}->{time_days},
        " days"
       );
	  }
      
      $data = {
        info_line_1 => "$sep [MAL] \x02$ct\x02 $sep \x02Profile Link\x02 http://myanimelist.net/profile/$ct $sep \x02Anime List Link\x02 http://myanimelist.net/animelist/$ct $sep $data->{anime_stats} $data->{recent}",
        info_line_2 => ""
       };
       
      return $data;
    }
# ------------- USERS - MANGA ----------------#
   elsif ($type eq 'profile-manga') {
	 $sep = "\x02\x0305::\x0F";
     my $now = localtime;
     
     # grab some extra data
     my $recent = HTTP::Tiny->new(%optssc)->get("http://myanimelist.net/rss.php?type=rrm&u=$ct")->{content};
	 # print $recent,"\n" if $test;
     # GAWD I HATE DOING THIS
     # XML MODULE Y U NO WERK
     if ($recent =~ /
          \s+<item>\n
          \s+<title>(?<title>.*)<\/title>\n
		  \s+<link>.*\n
		  \s+.*\n
		  \s+<description><!\[CDATA\[(?<description>.*)\]\]><\/description>\n
		  \s+<pubDate>(?<date>.*)<\/pubDate>\n
		  \s+<\/item>
		  /x) {
		     $data->{recent_manga}->{title} = $+{title};
		     $data->{recent_manga}->{description} = $+{description};
		     $data->{recent_manga}->{date} = ($now - Time::Piece->strptime($+{date}, '%a, %d %b %Y %T %z'))->pretty;
		     undef $recent;
		    }

     if (!defined($data->{recent_manga}->{title})) { 
         $data->{recent_manga} = "$sep";
     } else {
       # clean the title
       $data->{recent_manga}->{title} = &cleanup($data->{recent_manga}->{title});
       # format chaps
       if ($data->{recent_manga}->{description} !~ /Plan to read/i) { $data->{recent_manga}->{description} =~ s/(.*?) - (\d+|\?) of (\d+|\?)( chapters)?/\[$1 \($2\/$3\)\]/i; }
       else { $data->{recent_manga}->{description} = "[Plan to Read]"; }
       # format the entire thing
       $data->{recent_manga} = "$sep \x02Recent Manga\x02 $data->{recent_manga}->{title} $data->{recent_manga}->{description} ($data->{recent_manga}->{date} ago) $sep";
      }
     
     # pre-format
     if (!defined ($data->{manga_stats})) {
       return undef;
     } else {
     $data->{manga_stats} = join ('',
        "\x02Manga List Entries\x02 ",
        $data->{manga_stats}->{total_entries}, ' [',
        join ('/',
          $data->{manga_stats}->{reading},
          $data->{manga_stats}->{completed},
          $data->{manga_stats}->{plan_to_read},
          $data->{manga_stats}->{on_hold},
          $data->{manga_stats}->{dropped}
         ), ']',
        " $sep \x02Time Spent Reading\x02 ",
        $data->{manga_stats}->{time_days},
        " days"
       );
      }
      
	  $data = {
        info_line_1 => "$sep [MAL] \x02$ct\x02 $sep \x02Profile Link\x02 http://myanimelist.net/profile/$ct $sep \x02Manga List Link\x02 http://myanimelist.net/mangalist/$ct $sep $data->{manga_stats} $data->{recent_manga}",
        info_line_2 => ""
       };
       
      return $data;
    }
# -------------- PEOPLE ------------------#
   elsif ($type eq 'people') {
     $sep = "\x02\x0309::\x0F";
     $data->{jp_name} = (!defined($data->{jp_name})) ? $sep : "($data->{jp_name}) $sep";
     $data->{www} = (!defined($data->{www})||$data->{www} eq '') ? '' : "\x02Website\x02 $data->{www} $sep ";
     if (!defined($data->{chars})) {
       $data = {
          info_line_1 => "$sep [People] \x02$data->{name}\x02 $sep \x02Link\x02 $data->{url} $sep",
          result_line => $sep." [".($ct+1)."/".$total."][People] \x02$data->{name}\x02 $sep \x02Link\x02 $data->{url} $sep"
         };
     } else {
       my @roles;
       my $c_t = 0;
       my @tmp;
       my $roles = (scalar(@{$data->{chars}}) == 1) ? "role" : "roles";
	   my $smp_i = &eggroll((scalar(@{$data->{chars}}) - 1));
	   $data->{smp_r} = $data->{chars}->[$smp_i]->{name} . " (" . $data->{chars}->[$smp_i]->{anime} . ")";
       
       if (scalar(@{$data->{chars}}) <= 3) {
         foreach my $i (@{$data->{chars}}) {
           push(@tmp,"$i->{name} ($i->{anime})");
          }
       #pre-format
        $data->{chars} = join('',
                          "\x02Example Roles\x02 ",
                          join(' | ',@tmp),
                          " $sep (",scalar(@{$data->{chars}})," $roles in total)"
                         );
       } else {
       # grab random roles
        while ($c_t != 3) {
        my $tmp = 0;
         do {
          $tmp = &eggroll((scalar(@{$data->{chars}}) - 1));
          } while (grep { $_ == $tmp } @roles);
          $roles[$c_t] = $tmp;
          $c_t++;
         }      
       #pre-format
        $data->{chars} = join('',
                          "\x02Example Roles\x02 ",
                          $data->{chars}->[$roles[0]]->{name}," (",$data->{chars}->[$roles[0]]->{anime},") | ",
                          $data->{chars}->[$roles[1]]->{name}," (",$data->{chars}->[$roles[1]]->{anime},") | ",
                          $data->{chars}->[$roles[2]]->{name}," (",$data->{chars}->[$roles[2]]->{anime},") ",
                          "$sep (",scalar(@{$data->{chars}})," roles in total)"
                         );
        }
       #format
        $data = {
            info_line_1 => "$sep [People] \x02$data->{name}\x02 $data->{jp_name} $data->{www}\x02MAL Page Link\x02 $data->{url} $sep",
            info_line_2 => "$sep $data->{chars} $sep",
			parse_line  => "$mal $sep [People] \x02$data->{name}\x02 $data->{jp_name} \x02Example Role\x02 $data->{smp_r} $sep"
          };
     }
     return $data;
    }
# -------------- CHARACTERS --------------#
   elsif ($type eq 'character') {
    $sep = "\x02\x0307::\x0F";
    if (!defined($data->{info})) {
      $data = {
          info_line_1 => "$sep [Character] \x02$data->{name}\x02 $sep \x02Appears in\x02 $data->{shows}->[0] $sep \x02Link\x02 $data->{url} $sep",
          result_line => $sep." [".($ct+1)."/".$total."][Character] \x02$data->{name}\x02 $sep \x02Example Appearance\x02 $data->{shows}->[0] $sep \x02Link\x02 $data->{url} $sep"
         };
    } else {
     $data->{jp_name} = (!defined($data->{jp_name})) ? $sep : "($data->{jp_name}) $sep";
	 # TODO: Fix "Eucliwood Overflow" issue (too many seiyuu)
     $data->{seiyuu} = (!defined($data->{seiyuu})) ? '' : " \x02Voiced by\x02 ".join(', ',@{$data->{seiyuu}})." $sep";
     # clean up the info
     $data->{info} = &cleanup($data->{info});
    
     # trim the info
     if (length ($data->{info}) > 200) {
      $data->{info} =~ s/ ...$//;
      $data->{info} =~ s/(.{200}).*/$1/;
      $data->{info} = "$data->{info}...";
     }
     
     # grab appearances
     my @roles;
     my $c_t = 0;
     my $sss = (scalar(@{$data->{shows}}) == 1) ? '' : 's';
       
     if (scalar(@{$data->{shows}}) <= 2) {
     #pre-format
      $data->{shows} = join('',
                        "\x02Anime/Manga Appearances\x02 ",
                        join(' | ',@{$data->{shows}}),
                        " $sep (",scalar(@{$data->{shows}})," appearance$sss in total)"
                        );
     } else {
     # grab random roles
      while ($c_t != 3) {
      my $tmp = 0;
       do {
        $tmp = &eggroll((scalar(@{$data->{shows}}) - 1));
        } while (grep { $_ == $tmp } @roles);
        $roles[$c_t] = $tmp;
        $c_t++;
       }      
     #pre-format
      $data->{shows} = join('',
                        "\x02Anime/Manga Appearances\x02 ",
                        $data->{shows}->[$roles[0]]," | ",
                        $data->{shows}->[$roles[1]]," ",
                        "$sep (",scalar(@{$data->{shows}})," appearances in total)"
                       );
      }
     # format
      $data = {
          info_line_1 => "$sep [Character] \x02$data->{name}\x02 $data->{jp_name}$data->{seiyuu} $data->{shows} $sep",
          info_line_2 => "$sep \x02Quick Info\x02 $data->{info} $sep \x02MAL Page Link\x02 $data->{url} $sep",
		  parse_line  => "$mal $sep [Character] \x02$data->{name}\x02 $data->{jp_name}$data->{seiyuu} $data->{shows} $sep"
        };
    }
    return $data;
   }
# -------------- VNDB --------------#
   elsif ($type eq 'vndb') {
   $sep = $sep = "\x02\x0310::\x0F";
   if (!defined $data->{nsfw}) {
     $data = {
         info_line_1 => "$sep [VNDB] \x02$data->{title}\x0F $sep \x02Rating\x02 $data->{rating}/10 $sep \x02Link\x02 http://vndb.org/$data->{id} $sep",
         result_line => "$sep [VNDB] \x02$data->{title}\x0F $sep \x02Rating\x02 $data->{rating}/10 $sep \x02Link\x02 http://vndb.org/$data->{id} $sep"
       };
   } else {
     #cleanup
     $data->{title} = &cleanup($data->{title});
     $data->{desc} = &cleanup($data->{desc});
     
     $data->{desc} = ($data->{desc} eq '-') ? 'None' : $data->{desc};
     $data->{japanese} = (!defined $data->{japanese}) ? "" : "($data->{japanese}) ";
     $data->{pub} = (!defined $data->{pub}) ? "" : "$sep \x02Publisher\x02 $data->{pub} ";
     $data->{nsfw} = ($data->{nsfw}) ? "\x02\x0304[NSFW]\x0F $sep" : "$sep";
     
     #trim the description
     if (length ($data->{desc}) > 325) {
     $data->{desc} =~ s/ ...$//;
     $data->{desc} =~ s/(.{325}).*/$1/;
     $data->{desc} = "$data->{desc}...";
     }
     
     #prettify platforms line
     if (defined($data->{rels})) {
       if (scalar(@{$data->{rels}}) > 3) {
         $data->{rels} = join (', ', @{$data->{rels}}[0 .. 2]) . " (and " . (scalar(@{$data->{rels}}) - 3) . " other platforms)";
       } else {
         $data->{rels} = join (', ', @{$data->{rels}});
       }
     } else {
       $data->{rels} = ["Unknown"];
     }
     
     #final output
     $data = {
         info_line_1 => "$sep [VNDB] \x02$data->{title}\x02 $data->{japanese}$data->{pub}$sep \x02Released for\x02 $data->{rels} $sep \x02Rating\x02 $data->{score}/10 (Ranked \#$data->{rank}) $data->{nsfw}",
         info_line_2 => "$sep \x02Synopsis\x02 $data->{desc} $sep \x02Link\x02 http://vndb.org/$data->{id} $sep",
       };
   }
   return $data;
   }
}

sub Rorona {
# ** Rorona, the Alchemist of Arland
# ** Data parser for the official API

# Regexes
# From Yayoi with love

# So fugly, but werks :D

my $blah = shift;
my $res = [ ];
my $ct = 0;

#utf8::encode($blah);

print $blah,"\n" if $test;

# Anime regex
while ($blah =~ m/
  \s*<entry>\n
    \s*<id>(\d+)<\/id>\n
    \s*<title>(.*?)<\/title>\n
    \s*<english>.*?<\/english>\n
    \s*<synonyms>.*?<\/synonyms>\n
    \s*<episodes>(.*?)<\/episodes>\n
    \s*<score>(.*?)<\/score>\n
    \s*<type>(.*?)<\/type>\n
    \s*<status>(.*?)<\/status>\n
    \s*<start_date>.*?<\/start_date>\n
    \s*<end_date>.*?<\/end_date>\n
    \s*<synopsis>(.*?)<\/synopsis>\n
    \s*<image>.*?<\/image>\n
  \s*<\/entry>
   /sixgc) {
     $res->[$ct] = {
       DEBUG_ct => $ct,
       id => $1,
       title => $2,
       episodes => $3,
       members_score => $4,
       type => $5,
       synopsis => $7,
	   status => $6
      };
     $ct++;
    }

# Manga regex
while ($blah =~ m/
  \s*<entry>\n
    \s*<id>(\d+)<\/id>\n
    \s*<title>(.*?)<\/title>\n
    \s*<english>.*?<\/english>\n
    \s*<synonyms>.*?<\/synonyms>\n
    \s*<chapters>(.*?)<\/chapters>\n
    \s*<volumes>(.*?)<\/volumes>\n
    \s*<score>(.*?)<\/score>\n
    \s*<type>(.*?)<\/type>\n
    \s*<status>.*?<\/status>\n
    \s*<start_date>.*?<\/start_date>\n
    \s*<end_date>.*?<\/end_date>\n
    \s*<synopsis>(.*?)<\/synopsis>\n
    \s*<image>.*?<\/image>\n
  \s*<\/entry>
   /sixgc) {
     $res->[$ct] = {
       DEBUG_ct => $ct,
       id => $1,
       title => $2,
       chapters => $3,
       volumes => $4,
       members_score => $5,
       type => $6,
       synopsis => $7
      };
     $ct++;
    }

my @tmp = @{$res};
@tmp = sort { &weight($b,'search') <=> &weight($a,'search') } @tmp;
return \@tmp;
}

sub Totori {
# ** Totori, the Adventurer of Arland
# ** Data parser/pre-formatter for web scrape

my ($blah,$searchtype) = @_;
my $mess;
my $ct = 0;
my $stahp = 0;

#print $blah,"\n\n" if $test;

#$blah = decode_entities($blah);

#Common factor
if ($blah =~ m/\s*<h1>(.*?)<\/h1>/si) {
  $mess->{name} = $1;
  $mess->{name} =~ s/\s+/ /g;
  $mess->{name} =~ s/^\s+|\s+$//g;
  
}

return [] if ($mess->{name} =~ /404 Error/i);

#---------------- PEOPLE --------------------#
if ($searchtype eq 'people') {
if ($mess->{name} eq 'Search People') {
$mess = [];
  while ($blah =~ m{\s*<td class="borderClass"><a href="(/people/(\d+)/.*?)">(.*?)</a></td>\n}igc) {
    $mess->[$ct] = {
       name => $3,
       url => "http://myanimelist.net$1",
       id => $2
     };
    
    if ($mess->[$ct]->{name} =~ /^(.*), (.*)$/) {
       $mess->[$ct]->{name} = "$2 $1";
     }
     
    $ct++;
  }
} else {
  if ($blah =~ m{<li><a.href="(/people/(\d+)/.*?)".class="horiznav_active">Details</a></li>}i) {
    $mess->{url} = "http://myanimelist.net$1";
    $mess->{id} = $2;
  }

  if ($blah =~ m/\s*.div.class..spaceit_pad...span.class..dark_text..Given.*?:..span.\s*(.*?)..div.\n
                 (\s*.span.class..dark_text..Family.*?:..span.\s*(.*).div.class..spaceit_pad...span.class..dark_text..Birthday:..span.\s*(.*?)..div.)?
               /ix) {
               $mess->{jp_name} = "$3$1";
               $mess->{dob} = $4;
               
              if ($mess->{name} =~ m/^(.*), (.*)$/) {
              $mess->{name} = "$2 $1";
              }

              }
  if ($blah =~ m{.span.class..dark_text..Website...span...a.href..(.*?).>}i) {
      $mess->{www} = $1;
    }
              
  if ($blah =~ m{
                 \s*<.div><div.class..normal_header.><.*Add.Voice.Actor.Role</a></div>Voice.Acting.Roles</div><table.*?>\n
                 (.*?)\n
  		          \s*</table>
  		          }six) {
  		           $blah = $1;
  		          } elsif ($blah =~ m{
                                    \s*<div.class..normal_header.><.*Add.Position</a></span>Anime.Staff.Positions</div><table.*?>\n
                                    (.*?)\n
  		                             \s*</table>
  		                             }six) {
  		                             $blah = $1;
  		                             } else {
  		                               $stahp = 1;
  		                             }
  if (!$stahp) {		           
    while ($blah =~ m{
                    \s*<td.valign="top".class="borderClass"><a.href.*?>(.*?)</a>.*?\n
                    .*?\n
                    \s*<td.valign="top".class="borderClass".align="right".nowrap><a.href.*?>(.*?)</a>......<div.class="spaceit_pad">(.*?)......</div></td>\n
                   }ixgc) {
                     $mess->{chars}->[$ct] = {
                      anime => $1,
                      name => $2,
                      role => $3
                     };

                    if ($mess->{chars}->[$ct]->{name} =~ m/^(.*), (.*)$/) {
                      $mess->{chars}->[$ct]->{name} = "$2 $1";
                    }

                    $ct++;
    }
    $ct = 0;
    while ($blah =~ m{
                     \s*<td.valign.*?class.*?><a.href.*>(.*?)</a>.*?\n
                     \s*<a.href.*<small>(.*?)</small>
                     }ixgc) {
                     $mess->{chars}->[$ct] = {
                      anime => $1,
                      name => $2,
                      role => ''
                     };
                     

                    if ($mess->{chars}->[$ct]->{name} =~ m/^(.*), (.*)$/) {
                      $mess->{chars}->[$ct]->{name} = "$2 $1";
                    }

                    $ct++;
    }
  }
  $mess = [$mess];
}
}
#---------------- CHARACTERS --------------------#
elsif ($searchtype eq 'character') {
$ct = 0;
if ($mess->{name} eq 'Search Characters') {
$mess = [];
  while ($blah =~ m{
                    \s*<td.class..borderClass.bgColor.*?\n
                    \s*<a.href="(/character/(\d+)/.*?)">(.*?)</a>.*?\n
                    \s*</td>\n
                    \s*<td.class..borderClass.bgColor.*?\n
                    (?|\s*Anime..<a.href="/anime.*?">(.*?)</a>.*?\n
                    (\s*<div>Manga..<a.href="/manga.*?">.*?</a>.*?\n)?|
                    \s*<div>Manga..<a.href="/manga.*">(.*?)</a>.*?\n?)
                    \s*</tr>
                   }ixgc) {
                    $mess->[$ct] = {
                     name => $3,
                     url => "http://myanimelist.net$1",
                     id => $2,
                     shows => [$4]
                    };
                    $mess->[$ct]->{name} =~ s/\s+/ /g;

    if ($mess->[$ct]->{name} =~ m/^(.*), (.*)$/) {
       $mess->[$ct]->{name} = "$2 $1";
    }
     
    $ct++;
  }
 } else {
  if ($blah =~ m{<li><a.href="(/character/(\d+)/.*?)".class="horiznav_active">Details</a></li>}i) {
    $mess->{url} = "http://myanimelist.net$1";
    $mess->{id} = $2;
  }
  
  if ($blah =~ m{
                \s*<div.class..normal_header..style="height:.15px;">.*?<span.style="font-weight:.normal;"><small>\((.*?)\)</small></span></div>
               }six) {
                 $mess->{jp_name} = $1;
                }
				
  if ($blah =~ m{
                \s*<div.class..normal_header..style="height:.15px;">.*?</div>
                (.*?)
                 <div.class="normal_header">Voice.Actors</div>
               }six) {
                 $mess->{info} = cleanup($1);
                }
				
  my $ind = 0;
  while ($blah =~ m{
                   \s*<table.border.*?>\n
                   \s*<tr>\n
                   \s*<td.class="borderClass".valign="top".width="25"><div.class="picSurround">.*?\n
                   \s*<td.class="borderClass".valign="top"><a.href="/people.*?">(.*)</a>\n
                   \s*<div.style="margin-top:.2px;"><small>Japanese</small></div></td>\n
                  }ixgc) {
                    $mess->{seiyuu}->[$ind] = $1;
                    if ($mess->{seiyuu}->[$ind] =~ /^(.*), (.*)$/) {
                       $mess->{seiyuu}->[$ind] = "$2 $1";
                    }
                    $ind++;
                  }
  if ($blah =~ m{
               (?|
               <div.class="normal_header">Animeography</div>\n
               \s*<table.*?>\n
               (.*?)\n
               \s*</table>
               |
               <div.class="normal_header">Mangaography</div>\n
               \s*<table.*?>\n
               (.*?)\n
               \s*</table>
               )
              }six) {
                $blah = $1;
              } else {
                $stahp = 1;
              }
  $ct = 0;
  while ($blah =~ m{<td.*?borderClass.><a.href="/(anime|manga).*?">(.*?)</a>}igc) {
    $mess->{shows}->[$ct] = $2;
    $ct++;
  }

  $mess = [ $mess ];
 }
}
#---------------- FANSUBBERS --------------------#
elsif ($searchtype eq 'fansub-groups') {
$ct = 0;
 if ($mess->{name} =~ /Fansub Group Search/) {
 $mess = [];
   while ($blah =~ m{
                    \s*<td.class="borderClass".width="300"><a.href="\?id=(\d+)">(.*?)</td>\n
                    \s*<td.class="borderClass">(.*)</td>
                   }ixgc) {
                     $mess->[$ct] = {
                       id => int($1),
                       name => $2,
                       s_name => $3
                      };
                     $ct++;
                   }
    $mess = [ sort { length($a->{name}) <=> length($b->{name}) } @{$mess} ];
 } else {
 $mess = [ $mess ];
 }
}

# *** ------- SCRAPER FALLBACK --------- *** #

#---------------- ANIME --------------------#
elsif ($searchtype eq 'anime') {
  if ($blah =~ m{\s+<h1><div.style.*>Ranked.\#(.*)</div>(.*?)</h1>\n}) {
    $mess->{rank} = $1;
    $mess->{title} = $2;
  } else {
    die "Data seems to be malformed";
  }
  
  if ($blah =~ m{\s*?<h2>Alternative.Titles</h2>.*<span.class=.dark_text.>Japanese:</span>\s?(.*)</div><br.?/>\n}i) {
                     $mess->{other_titles} = { japanese => [ $1 ] };
  }
  if ($blah =~ m{\s+<h2>Information</h2>\n
                 \s+<div><span.class..dark_text.>Type:</span>\s?(.*)</div>\n
				 \s+.*<span.class..dark_text.>Episodes:</span>\s?(.*)\n
				 \s+</div>\n
				 \s+<div><span.class..dark_text.>Status:</span>\s?(.*)</div>
				 \n.*
				 \n.*
				 \n.*
				 \n.*Rating:</span>\n
				 \s+(.*)</div>}ix) {
                   $mess->{type} = $1;
                   $mess->{episodes} = $2;
                   $mess->{status} = $3;
                   $mess->{classification} = $4;
                   undef $mess->{episodes} if lc($2) eq 'unknown';
                 }
                 
  if ($blah =~ m{.*Genres:</span>\n
                 \s+(.*?)</div>}ix) {
                     my $crap = $1;
                     $crap =~ s{<a.href=./anime.*?genre.*?>(.*?)</a>}{$1}g;
                     my @tmp = split(', ',$crap);
                     $mess->{genres} = \@tmp;
                   }
                   
  if ($blah =~ m{<h2>Statistics</h2><div><span.class=.dark_text.>Score:</span>\s?(.*)<sup>}) {
    $mess->{members_score} = $1;
  }
  
  if ($blah =~ m{<div>.*?<span.class..dark_text.>Producers:</span>\s(.*?)</div>}ix) {
    my $prods = $1;
	print $prods,"\n" if $test;
	my @prods;
	while ($prods =~ m{<a.href...anime.php.*?>(.*?)</a>}igc) {
	  push @prods, $1;
	}
	
	$mess->{producers} = \@prods;
  }
  
  if ($blah =~ m{\s+<li><a.href=.http://myanimelist.net/anime/(\d+)/.*/.*?Details</a>}) {
    $mess->{id} = $1;
  }
  
  if ($blah =~ m{.*<h2>Synopsis</h2>(.*?)</td>}s) {
    $mess->{synopsis} = $1;
  }
  
  if ($blah =~ m{.*<span.class=.dark_text.>Aired:</span>\s?(.*)</div>\n}) {
    my %mon = ( Jan => 1, Feb => 2, Mar => 3, Apr => 4, May => 5, Jun => 6,
                Jul => 7, Aug => 8, Sep => 9, Oct => 10, Nov => 11, Dec => 12 );
                
    my $crap = $1;
    if ($crap =~ /^(...)\s+(\d+),\s(\d{4}) to (...)\s+(\d+),\s(\d{4})/) {
      $mess->{start_date} = "$3-".sprintf('%02d-%02d',$mon{$1},$2);
      $mess->{end_date}   = "$6-".sprintf('%02d-%02d',$mon{$4},$5);
    }
    elsif ($crap =~ /^(...)\s+(\d+),\s(\d{4}) to \?/) {
      $mess->{start_date} = "$3-".sprintf('%02d-%02d',$mon{$1},$2);
      $mess->{end_date}   = undef;
    }
    elsif ($crap =~ /^(...)\s+(\d+),\s(\d{4})/) {
      $mess->{start_date} = "$3-".sprintf('%02d-%02d',$mon{$1},$2);
      $mess->{end_date}   = (lc($mess->{status}) eq 'not yet aired') ? undef : "$3-".sprintf('%02d-%02d',$mon{$1},$2);
    }
    elsif ($crap =~ /^Not available/i) {
      $mess->{start_date} = undef;
      $mess->{end_date}   = undef;
    }
  }

  $mess->{name} = undef;
  #$mess = [ $mess ];
}
#---------------- MANGA --------------------#
elsif ($searchtype eq 'manga') {
  if ($blah =~ m{\s+<h1><div.style.*>Ranked.\#(.*)</div>(.*?)</h1>\n}) {
    $mess->{rank} = $1;
    $mess->{title} = $2;
    $mess->{title} =~ s/\s+<span.*//;
  } else {
    die "Data seems to be malformed";
  }
  
  if ($blah =~ m{\s*?<h2>Alternative.Titles</h2>.*<span.class=.dark_text.>Japanese:</span>\s?(.*)</div><br.?/>\n}i) {
    $mess->{other_titles} = { japanese => [ $1 ] };
  }
  if ($blah =~ m{\s*?\n
                 \s+<h2>Information</h2>\n
                 .*\n
                 \s+.*<span.class=.dark_text.>Type:</span>\s?(.*)</div>\n
                 \s+.*<span.class=.dark_text.>Volumes:</span>\s?(.*)\n
                 .*\n
                 \s+.*<span.class=.dark_text.>Chapters:</span>\s?(.*)\n
                 \s+</div>\n
                 \s+.*<span.class=.dark_text.>Status:</span>\s?(.*)</div>\n
                 }ix) {
                   $mess->{type} = $1;
                   $mess->{volumes} = $2;
                   $mess->{chapters} = $3;
                   $mess->{status} = $4;
                   undef $mess->{volumes} if lc($2) eq 'unknown';
                   undef $mess->{chapters} if lc($3) eq 'unknown';
                 }
                 
  if ($blah =~ m{.*Genres:</span>\n
                 \s+(.*?)</div>}ix) {
                     my $crap = $1;
                     $crap =~ s{<a.href=./manga.*?genre.*?>(.*?)</a>}{$1}g;
                     my @tmp = split(', ',$crap);
                     $mess->{genres} = \@tmp;
                   }
                   
  if ($blah =~ m{<h2>Statistics</h2><div><span.class=.dark_text.>Score:</span>\s?(.*)<sup>}) {
    $mess->{members_score} = $1;
  }
  
  if ($blah =~ m{\s+<li><a.href=./manga/(\d+)/.*?Details</a>}) {
    $mess->{id} = $1;
  }
  
  if ($blah =~ m{.*<h2>Synopsis</h2>(.*?)</td>}s) {
    $mess->{synopsis} = $1;
  }
  
  $mess->{name} = undef;
  #$mess = [ $mess ];
}
#---------------- USERS --------------------#
elsif ($searchtype eq 'profile' or $searchtype eq 'profile-manga') {
 # die "This function is a stub. You can help Yayoi by expanding it.";
 if ($blah =~ m{\s+<tr>\n
                \s+<td.width.*?lightLink.>Time..Days.</span></td>\n
                \s+<td.width.*?><span.*?Days.>(.*?)</span></td>\n
                .*\n
                .*\n
                .*\n
                \s+<td.width.*?lightLink.>Watching</span></td>\n
                \s+<td.align..center.>(\d+)</td>\n
                .*\n
                .*\n
                .*\n
                \s+<td.width.*?lightLink.>Completed</span></td>\n
                \s+<td.align..center.>(\d+)</td>\n
                .*\n
                .*\n
                .*\n
                \s+<td.width.*?lightLink.>On.Hold</span></td>\n
                \s+<td.align..center.>(\d+)</td>\n
                .*\n
                .*\n
                .*\n
                \s+<td.width.*?lightLink.>Dropped</span></td>\n
                \s+<td.align..center.>(\d+)</td>\n
                .*\n
                .*\n
                .*\n
                \s+<td.width.*?lightLink.>Plan.to.Watch</span></td>\n
                \s+<td.align..center.>(\d+)</td>\n
                .*\n
                .*\n
                .*\n
                \s+<td.width.*?lightLink.>Total.Entries</span></td>\n
                \s+<td.align..center.>(\d+)</td>\n
              }ix) {
                     $mess->{anime_stats} = {
                                               time_days     => $1,
                                               watching      => $2,
                                               completed     => $3,
                                               on_hold       => $4,
                                               dropped       => $5,
                                               plan_to_watch => $6,
                                               total_entries => $7
                                             };
                   } else {
                     die "Data seems malformed";
                   }
				   
 if ($blah =~ m{\s+<tr>\n
                \s+<td.width.*?lightLink.>Time..Days.</span></td>\n
                \s+<td.width.*?><span.*?Days.>(.*?)</span></td>\n
                .*\n
                .*\n
                .*\n
                \s+<td.width.*?lightLink.>Reading</span></td>\n
                \s+<td.align..center.>(\d+)</td>\n
                .*\n
                .*\n
                .*\n
                \s+<td.width.*?lightLink.>Completed</span></td>\n
                \s+<td.align..center.>(\d+)</td>\n
                .*\n
                .*\n
                .*\n
                \s+<td.width.*?lightLink.>On.Hold</span></td>\n
                \s+<td.align..center.>(\d+)</td>\n
                .*\n
                .*\n
                .*\n
                \s+<td.width.*?lightLink.>Dropped</span></td>\n
                \s+<td.align..center.>(\d+)</td>\n
                .*\n
                .*\n
                .*\n
                \s+<td.width.*?lightLink.>Plan.to.Read</span></td>\n
                \s+<td.align..center.>(\d+)</td>\n
                .*\n
                .*\n
                .*\n
                \s+<td.width.*?lightLink.>Total.Entries</span></td>\n
                \s+<td.align..center.>(\d+)</td>\n
              }ix) {
                     $mess->{manga_stats} = {
                                               time_days     => $1,
                                               reading       => $2,
                                               completed     => $3,
                                               on_hold       => $4,
                                               dropped       => $5,
                                               plan_to_read  => $6,
                                               total_entries => $7
                                             };
                   } else {
                     die "Data seems malformed";
                   }
}

return $mess;
}

sub Escha {
# ** Escha Malier, Alchemist of the Dusk Sky
# ** VNDB scraper and data synthesizer

my $blah = shift;
#print $blah,"\n";
my $mess ;
if ($blah =~ m{<title>Browse visual novels</title>}) {
	#say "landed on search page";
	if ($blah =~ m{<body>(.*)</body>}si) {
	                my $vndump = $1;
	                #say $vndump;
	                my @vns;
	                while ($vndump =~ m{<a.href...(v\d+).*?>(.*?)</a>.*?<td.class..tc6.>(.*?)<b.class..grayedout.>}ig) {
	                                      push @vns, {
	                                                   'title' => $2,
	                                                   'id'    => $1,
	                                                   'rating' => $3,
	                                                  };
	                                            }
	                                      if (scalar(@vns) > 0) {
	                                        #pop @vns;
											return \@vns;
										  } else {
											return [];
										  }
	                }
} else {
	$mess->{nsfw} = 0;
	if ($blah =~ m{<li.class="tabselected">.*?<a.*?>(v\d+?)</a>}i) {
		$mess->{id} = $1;
	}
	if ($blah =~ m{<td.*?>Title</td>.*?<td>(.*?)</td>
	               .*?
	               (?|<td>Original.title</td>.*?<td>(.*?)</td>|<td>Aliases</td>.*?<td>(.*?)</td>)
	               }six) {
		                  $mess->{title} = $1;
		                  $mess->{japanese} = $2;
	}
	if ($blah =~ m{<td>Length</td>.*?<td>(.*?)</td>
	               .*?
	               <td>Developer</td>.*?<td><a.href=.*?>(.*?)</a></td>
	               .*?
	               <td>Publishers</td>.*?
	               <acronym.*?Japanese">.*?<a.*?>(.*?)</a>
	               }six) {
		                  $mess->{len} = $1;
		                  $mess->{dev} = $2;
		                  $mess->{pub} = $3;
	}
	if ($blah =~ m{<tr.class="nostripe">.*?
	               <td.class="vndesc".*?
	               <h2>Description</h2>.*?
	               <p>(.*?)</p>.*?</td>
	               }ix) {
	                      $mess->{desc} = $1;
	}
	if ($blah =~ m{<h3>Ranking</h3>.*?
	               .*?
	               <p>Bayesian.rating:.ranked.\#(\d+?)\swith.a.rating.of\s(.*?)</p>
	              }ix) {
	                     $mess->{rank} = $1;
	                     $mess->{score} = $2;
	}
	if ($blah =~ m{<td.class..tc2.>18\+}ix) {
	    $mess->{nsfw} = 1;
	}
	if ($blah =~ m{<div.class..mainbox.releases.>(.*?)</div>}i) {
	    my $reldump = $1;
		my @rels;
		while ($reldump =~ m{<td.class..tc3.><acronym.class..*?..title..(.*?).>}igcx) {
							    push @rels, $1 unless (grep {$_ eq $1} (@rels,"Trial","Complete"));
						    }
		$mess->{rels} = \@rels;
	}
	return [$mess];
}
}

sub Wilbell {
# ** Wilbell
# ** (Magical!) Google Search fallback

my ($searchterm,$searchtype) = @_;
my $searchtermwf;
eval { $searchtermwf = uri_escape("$searchterm site:myanimelist.net/$searchtype"); };
if ($@) { $searchtermwf = uri_escape_utf8("$searchterm site:myanimelist.net/$searchtype"); }

my $mess;
print "Someone rang for a Wilbell?\n" if $test;

eval { $mess = decode_json(HTTP::Tiny->new->get("http://ajax.googleapis.com/ajax/services/search/web?v=1.0&q=$searchtermwf")->{content}); };
if ($@) { return undef; }

if (defined($mess->{responseData}->{'results'}->[0]->{unescapedUrl})
     and $mess->{responseData}->{'results'}->[0]->{unescapedUrl} =~ m{http://myanimelist.net/$searchtype/(\d+?)/.*}i) {
        return $1;
} else {
  return undef;
}

}


sub cleanup {
 my $data =  shift;
 return '' if (not defined($data) or $data eq '');

    #$data = encode('UTF-8', $data);
    #utf8::downgrade($data);
    $data = decode_entities($data);
    $data = encode('UTF-8',$data,Encode::FB_PERLQQ);
    $data =~ s{<input.type.*?Hide.spoiler.>(<br\s?/?>)?(.*?)<!--spoiler--></span>}{$2}si; # Prepare to be spoiled!
    $data =~ s/\\(n|r)+/ | /g;
    $data =~ s/(\n|\r)+//g;
    $data =~ s/(<[bh]r\s*?\/?>)+/ | /g;
    $data =~ s/<(.*?)(\s+)?.*?>(.*?)<\/\g1>/$3/g;
    $data =~ s/\\(\'|\")/$1/g;
    #$data =~ s/\s+/ /g;
    $data =~ s/ \.\.\.$/.../;
    $data =~ s/ \| $//;
    $data = decode('UTF-8',$data,Encode::FB_QUIET);
    print "Cleaned: ",Dumper($data) if $test;
 return $data;
}

sub weight {
 my $animu = shift;
 my $flag = shift;
 my %weight = (
   "TV" => 1000000000000,
   "OVA" => 100000000000,
   "ONA" => 100000000000,
   "Movie" => 10000000000,
   "Special" => 1000000000,
   "Music" => 0,
   
   "Currently Airing" => 100000000000000,
   "Finished Airing" => 100000000000000,
   "Not yet aired" => 0,
 );
 
 if ($flag eq 'whodid') { return $animu->{id} + $weight{$animu->{type}} + $weight{$animu->{status}}; }
 else { return $animu->{id} + $weight{$animu->{type}}; }
}

sub spaceit {
  my $clean = shift;
  $clean =~ s/([a-z])([A-Z])/$1 $2/g;
  $clean =~ s/-(chan|sama|kun|dono|san)$//;
  $clean =~ s/_|\||`|-/ /g;
  return $clean;
}

sub puppet {
my $command = shift;
my $nick = shift;

 if ($command =~ /^!kill$/i) {
   print $sock "PRIVMSG $channels[0] :\x01ACTION sighs!\x01\r\n";
   print $sock "PRIVMSG $channels[0] :\x01ACTION yawns!\x01\r\n";
   print $sock "PRIVMSG $channels[0] :\x01ACTION noms!\x01\r\n";
   print $sock "PRIVMSG $channels[0] :\x01ACTION hungers!\x01\r\n";
   &resetTimeout;
  } elsif ($command =~ /^!act (.*)$/i) { 
    print $sock "PRIVMSG $channels[0] :\x01ACTION $1\x01\r\n";
    &resetTimeout;
   } elsif ($command =~ /^!quit\s?(.*)$/i) {
     $iQuit = 1;
       my $quitreason = $1;
       if ($quitreason =~ /^bero/i || $quitreason eq "") { 
           print $sock "QUIT :$quitmsg\r\n";
         } else {
             print $sock "QUIT :$quitreason\r\n";
           }
    } elsif ($command =~ /^!pp (.*)$/i) {
      print $sock "PRIVMSG $channels[0] :$1\r\n";
      &resetTimeout;
     } elsif ($command =~ /^!raw (.*)$/i) {
       print $sock "$1\r\n";
       &resetTimeout;
      }
}

sub eggroll {
 my $maxvalue = shift;
 $maxvalue+=2;
 my $randnum  = 0;
 do { $randnum = int(rand($maxvalue)); } while ($randnum >= $maxvalue || $randnum == 0);
 return $randnum - 1;
}

sub stripcode {
 my $stripper = shift;
 $stripper =~ s/\\x02//g;              # Remove bold codes
 $stripper =~ s/\x02//g;               # Remove bold codes
 $stripper =~ s/\\x0F//g;              # Remove format codes
 $stripper =~ s/\x0F//g;               # Remove format codes
 $stripper =~ s/\\x03(\d{0,2})?(,\d{0,2})?//g; # Remove color codes
 $stripper =~ s/\x03(\d{0,2})?(,\d{0,2})?//g;  # Remove color codes
 return $stripper;
}

# Core subroutines
sub sendSay {
  my ($target,$msg) = @_;
  &sendRaw("PRIVMSG $target :$msg");
 }

sub sendAction {
  my ($target,$msg) = @_;
  &sendRaw("PRIVMSG $target :\x01ACTION $msg\x01");
 }

sub sendNotice {
  my ($target,$msg) = @_;
  &sendRaw("NOTICE $target :$msg");
 }

sub sendRaw {
  my $msg = shift;
  print $sock "$msg\r\n";
  &resetTimeout;
 }
 
sub resetTimeout {
  alarm(0);
  alarm($pingTimeout);
 }

# Internal subroutines
sub nss {
 my $s = shift;
 my $ns = $s * 1000000000;
 return $ns;
}

sub now {
 my ($sec,$msec) = gettimeofday;
 return $sec;
}

# (Outdated) POD incoming
__END__
=head1 NAME

bero.pl - Just another MAL info IRC bot

=head1 SYNOPSIS

	perl -X bero.pl & # normal usage
	perl -w bero.pl --test # test usage
    
=head1 DESCRIPTION

This is a generic IRC bot that provides information from MyAnimeList.net
(L<http://myanimelist.net>). Currently, it provides information about
anime, manga, characters, people, and users.

It pulls information using the following resources:

=over 4

=item *

B<MyAnimeList API>: for anime and manga search

=item *

B<Unofficial MAL API>: for detailed anime/manga/user info

=item *

B<MyAnimeList.net>: for character and people search/info

=back

=head1 CONFIGURATION

The script provides a configuration section at the beginning of the file.
This allows you to customize your bot's nick, to which server it should
connect, which channel(s) should it join, etc.

This section is documented with numerous comments, so you might want to
check that out.

=head1 COMMANDS

Once run, this bot provides commands to all users in the channel(s) it
joined. All commands start with C<.mal>.

Available commands are:

=over 4

=item *

C<.mal>: displays help messages, outlining all the other commands listed
below.

=item *

C<.mal [search term(s)]>: searches MyAnimeList for B<anime> whose title(s)
match(es) C<[search term(s)]>. If a single result is found, displays
complete info; otherwise, displays search results. A maximum of three
results is displayed per search.

=item *

C<.mal -m [search term(s)]>: searches MyAnimeList for B<manga> whose title(s)
match(es) C<[search term(s)]>. If a single result is found, displays
complete info; otherwise, displays search results. A maximum of three
results is displayed per search.

=item *

C<.mal -p [search term(s)]>: searches MyAnimeList for B<people>
(seiyuu, mangaka, etc.) whose name(s) match(es) C<[search term(s)]>. If a
single result is found, displays complete info; otherwise, displays search
results. A maximum of three results is displayed per search.

=item *

C<.mal -c [search term(s)]>: searches MyAnimeList for B<characters> whose
name(s) match(es) C<[search term(s)]>. If a single result is found, displays
complete info; otherwise, displays search results. A maximum of three
results is displayed per search.

=item *

C<.mal -u [username]>: displays detailed info about a user on MyAnimeList.

=back

=head1 DIAGNOSTICS

This script is designed to be run on VPSs, and hence, generates B<no> output.
(hence the -X flag.) However, unexpected errors are logged to a log file whose
path is specified in the configuration.

=head1 SEE ALSO

=over 4

=item *

L<http://myanimelist.net> - Official API documentation

=item *

L<http://mal-api.com> - Unofficial API

=back

=head1 AUTHOR

TakatsukiYayoi - TakatsukiYayoi on #doki at irc[dot]rizon[dot]net

=head1 COPYRIGHT

This software is copyright (c) 2013 by TakatsukiYayoi.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=head1 DISCLAIMER

The search functions are performed using APIs; if anime/manga search output
is broken, 90% of the time it can be blamed on MAL. :p

If character/people search breaks, 99% of the time it's my fault; sorry :D

This software is provided "as-is"; B<no warranties expressed or implied.>

B<I, the Author, shall not be held liable for any and all damages arising from
use, misuse, or abuse of this software.>

=cut