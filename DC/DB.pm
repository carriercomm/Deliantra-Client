=head1 NAME

DC::DB - async. database and filesystem access for cfplus

=head1 SYNOPSIS

 use DC::DB;

=head1 DESCRIPTION

=over 4

=cut

package DC::DB;

use strict;
use utf8;

use Carp ();
use Storable ();
use Config;
use BDB;

use DC;

our $DBDIR   = "cfplus-" . BDB::VERSION . "-$Config{archname}";
our $DB_HOME = "$Deliantra::VARDIR/$DBDIR";

if (!-e $DB_HOME and -e "$Deliantra::OLDDIR/$DBDIR") {
   rename "$Deliantra::OLDDIR/$DBDIR", $DB_HOME;
   print STDERR "INFO: moved old database from $Deliantra::OLDDIR/$DBDIR to $DB_HOME\n";
}

BDB::max_poll_time 0.03;

our $DB_ENV;
our $DB_STATE;
our %DB_TABLE;

sub open_db {
   mkdir $DB_HOME, 0777;

   $DB_ENV = db_env_create;

   $DB_ENV->set_errfile (\*STDERR);
   $DB_ENV->set_msgfile (\*STDERR);
   $DB_ENV->set_verbose (-1, 1);

   $DB_ENV->set_flags (BDB::AUTO_COMMIT | BDB::LOG_AUTOREMOVE | BDB::TXN_WRITE_NOSYNC);
   $DB_ENV->set_cachesize (0, 2048 * 1024, 0);

   db_env_open $DB_ENV, $DB_HOME,
               BDB::CREATE | BDB::REGISTER | BDB::RECOVER | BDB::INIT_MPOOL | BDB::INIT_LOCK | BDB::INIT_TXN,
               0666;

   $! and die "cannot open database environment $DB_HOME: " . BDB::strerror;

   1
}

sub table($) {
   $DB_TABLE{$_[0]} ||= do {
      my ($table) = @_;

      $table =~ s/([^a-zA-Z0-9_\-])/sprintf "=%x=", ord $1/ge;

      my $db = db_create $DB_ENV;
      $db->set_flags (BDB::CHKSUM);

      db_open $db, undef, $table, undef, BDB::BTREE,
              BDB::AUTO_COMMIT | BDB::CREATE | BDB::READ_UNCOMMITTED, 0666;

      $! and "unable to open/create database table $_[0]: ". BDB::strerror;

      $db
   }
}

#############################################################################

unless (eval { open_db }) {
   warn "$@";#d#
   eval { File::Path::rmtree $DB_HOME };
   open_db;
}

our $WATCHER = EV::io BDB::poll_fileno, EV::READ, \&BDB::poll_cb;

our $SYNC = EV::timer_ns 0, 60, sub {
   $_[0]->stop;
   db_env_txn_checkpoint $DB_ENV, 0, 0, 0, sub { };
};

our $tilemap;

sub exists($$$) {
   my ($db, $key, $cb) = @_;

   my $data;
   db_get table $db, undef, $key, $data, 0, sub {
      $cb->($! ? () : length $data);
   };
}

sub get($$$) {
   my ($db, $key, $cb) = @_;

   my $data;
   db_get table $db, undef, $key, $data, 0, sub {
      $cb->($! ? () : $data);
   };
}

sub put($$$$) {
   my ($db, $key, $data, $cb) = @_;

   db_put table $db, undef, $key, $data, 0, sub {
      $cb->($!);
      $SYNC->again unless $SYNC->is_active;
   };
}

sub do_table {
   my ($db, $cb) = @_;

   $db = table $db;

   my $cursor = $db->cursor;
   my %kv;

   for (;;) {
      db_c_get $cursor, my $k, my $v, BDB::NEXT;
      last if $!;
      $kv{$k} = $v;
   }

   $cb->(\%kv);
}

sub do_get_tile_id {
   my ($name, $cb) = @_;

   my $table = table "facemap";
   my $id;

   db_get $table, undef, $name, $id, 0;
   return $cb->($id) unless $!;

   for (1..100) {
      my $txn = $DB_ENV->txn_begin;
      db_get $table, $txn, id => $id, 0;

      $id = 64 if $id < 64;

      ++$id;

      db_put $table, $txn, id => $id, 0;
      db_txn_finish $txn;

      $SYNC->again unless $SYNC->is_active;

      return $cb->($id) unless $!;

      select undef, undef, undef, 0.01 * rand;
   }

   die "maximum number of transaction retries reached - database problems?";
}

sub get_tile_id_sync($) {
   my ($name) = @_;

   $tilemap->{$name} ||= do {
      my $id;
      do_get_tile_id $name, sub {
         $id = $_[0];
      };
      BDB::flush;
      $id
   }
}

#############################################################################

sub path_of_res($) {
   utf8::downgrade $_[0]; # bug in unpack "H*"
   "$DB_HOME/res-data-" . unpack "H*", $_[0]
}

sub sync {
   # for debugging
   #DC::DB::Server::req (sync => sub { });
   DC::DB::Server::sync ();
}

sub unlink($$) {
   DC::DB::Server::req (unlink => @_);
}

sub read_file($$) {
   DC::DB::Server::req (read_file => @_);
}

sub write_file($$$) {
   DC::DB::Server::req (write_file => @_);
}

sub prefetch_file($$$) {
   DC::DB::Server::req (prefetch_file => @_);
}

sub logprint($$$) {
   DC::DB::Server::req (logprint => @_);
}

#############################################################################

# fetch the full face table first
unless ($tilemap) {
   do_table facemap => sub {
      $tilemap = $_[0];
      delete $tilemap->{id};
      my %maptile = reverse %$tilemap;#d#
      if ((scalar keys %$tilemap) != (scalar keys %maptile)) {#d#
         $tilemap = { };#d#
         DC::error "FATAL: facemap is not a 1:1 mapping, please report this and delete your $DB_HOME directory!\n";#d#
      }#d#
   };
}

package DC::DB::Server;

use strict;

use EV ();
use Fcntl;

our %CB;
our $FH;
our $ID = "aaa0";
our ($fh_r_watcher, $fh_w_watcher);
our $sync_timer;
our $write_buf;
our $read_buf;

sub fh_write {
   my $len = syswrite $FH, $write_buf;

   substr $write_buf, 0, $len, "";

   $fh_w_watcher->stop
      unless length $write_buf;
}

sub fh_read {
   my $status = sysread $FH, $read_buf, 16384, length $read_buf;

   die "FATAL: database process died\n"
      if $status == 0 && defined $status;

   while () {
      return if 4 > length $read_buf;
      my $len = unpack "N", $read_buf;

      return if $len + 4 > length $read_buf;

      substr $read_buf, 0, 4, "";
      my $res = Storable::thaw substr $read_buf, 0, $len, "";

      my ($id, @args) = @$res;
      (delete $CB{$id})->(@args);
   }
}

sub sync {
   # biggest mess evarr
   my $fds; (vec $fds, fileno $FH, 1) =  1;

   while (1 < scalar keys %CB) {
      my $r = $fds;
      my $w = length $write_buf ? $fds : undef;
      select $r, $w, undef, undef;

      fh_write if vec $w, fileno $FH, 1;
      fh_read  if vec $r, fileno $FH, 1;
   }
}

sub req {
   my ($type, @args) = @_;
   my $cb = pop @args;

   my $id = ++$ID;
   $write_buf .= pack "N/a*", Storable::freeze [$id, $type, @args];
   $CB{$id} = $cb;

   $fh_w_watcher->start;
}

sub do_unlink {
   unlink $_[0];
}

sub do_read_file {
   my ($path) = @_;

   utf8::downgrade $path;
   open my $fh, "<:raw", $path
      or return;
   sysread $fh, my $buf, -s $fh;

   $buf
}

sub do_write_file {
   my ($path, $data) = @_;

   utf8::downgrade $path;
   utf8::downgrade $data;
   open my $fh, ">:raw", $path
      or return;
   syswrite $fh, $data;
   close $fh;

   1
}

sub do_prefetch_file {
   my ($path, $size) = @_;

   utf8::downgrade $path;
   open my $fh, "<:raw", $path
      or return;
   sysread $fh, my $buf, $size;

   1
}

our %LOG_FH;

sub do_logprint {
   my ($path, $line) = @_;

   $LOG_FH{$path} ||= do {
      open my $fh, ">>:utf8", $path
         or warn "Couldn't open logfile $path: $!";

      $fh->autoflush (1);

      $fh
   };

   my ($sec, $min, $hour, $mday, $mon, $year) = localtime time;

   my $ts = sprintf "%04d-%02d-%02d %02d:%02d:%02d",
               $year + 1900, $mon + 1, $mday, $hour, $min, $sec;

   print { $LOG_FH{$path} } "$ts $line\n"
}

sub run {
   ($FH, my $fh) = DC::socketpipe;

   my $oldfh = select $FH; $| = 1; select $oldfh;
   my $oldfh = select $fh; $| = 1; select $oldfh;

   my $pid = fork;
   
   if (defined $pid && !$pid) {
      local $SIG{QUIT} = "IGNORE";
      local $SIG{__DIE__};
      local $SIG{__WARN__};
      eval {
         close $FH;

         while () {
            4 == read $fh, my $len, 4
               or last;
            $len = unpack "N", $len;
            $len == read $fh, my $req, $len
               or die "unexpected eof while reading request";

            $req = Storable::thaw $req;

            my ($id, $type, @args) = @$req;
            my $cb = DC::DB::Server->can ("do_$type")
               or die "$type: unknown database request type\n";
            my $res = pack "N/a*", Storable::freeze [$id, $cb->(@args)];
            (syswrite $fh, $res) == length $res
               or die "DB::write: $!";
         }
      };

      my $error = $@;

      eval {
         Storable::store_fd [die => $error], $fh;
      };

      warn $error
         if $error;

      DC::_exit 0;
   }

   close $fh;
   DC::fh_nonblocking $FH, 1;

   $CB{die} = sub { die shift };

   $fh_r_watcher = EV::io $FH, EV::READ , \&fh_read;
   $fh_w_watcher = EV::io $FH, EV::WRITE, \&fh_write;
}

sub stop {
   close $FH;
}

1;

=back

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut

