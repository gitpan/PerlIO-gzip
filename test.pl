#!perl -w
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test;
BEGIN { plan tests => 98 };
use File::Compare; # This is standard in all distributions that have layers.
use Config;
use PerlIO::gzip;
ok(1); # If we made it this far, we're ok.

#########################

# Insert your test code below, the Test module is use()ed here so read
# its man page ( perldoc Test ) for help writing this test script.


if (open FOO, "<:gzip", "ok3.gz") {
  print "ok 2\n";
} else {
  print "not ok 2\n";
}
 
while (<FOO>) {
  print;
}

# check with no args
if (open FOO, "<:gzip()", "ok3.gz") {
  print "ok 4\n";
} else {
  print "not ok 4\n";
}
while (<FOO>) {
  if ($_ eq "ok 3\n") {
    print "ok 5\n";
  } else {
    print "not ok 5 # $_\n";
  }
}


# check with explict gzip header
if (open FOO, "<:gzip(gzip)", "ok3.gz") {
  print "ok 6\n";
} else {
  print "not ok 6\n";
}
while (<FOO>) {
  if ($_ eq "ok 3\n") {
    print "ok 7\n";
  } else {
    print "not ok 7 # $_\n";
  }
}

# check with lazy header check
if (open FOO, "<:gzip(lazy)", "ok3.gz") {
  print "ok 8\n";
} else {
  print "not ok 8\n";
}
while (<FOO>) {
  if ($_ eq "ok 3\n") {
    print "ok 9\n";
  } else {
    print "not ok 9 # $_\n";
  }
}

if (open FOO, "<:gzip(gzip,lazy)", "ok3.gz") {
  print "ok 10\n";
} else {
  print "not ok 10\n";
}
while (<FOO>) {
  if ($_ eq "ok 3\n") {
    print "ok 11\n";
  } else {
    print "not ok 11 # $_\n";
  }
}

# This should open
if (open FOO, "<", "README") {
  print "ok 12\n";
} else {
  print "not ok 12\n";
}

# This should fail to open
if (open FOO, "<:gzip", "README") {
  print "not ok 13\n";
} else {
  print "ok 13\n";
}

# This should open (lazy mode)
if (open FOO, "<:gzip(lazy)", "README") {
  print "ok 14\n";
} else {
  print "not ok 14\n";
}

# But as the gzip header check is on first read it should fail here
my $line = <FOO>;
if (defined $line) {
  print "not ok 15 # $_\n";
} else {
  print "ok 15\n";
}

# This file has an embedded filename. Being short it also checks get_more
# (called by eat_nul) and the unread of the excess data.
if (open FOO, "<:gzip", "ok17.gz") {
  print "ok 16\n";
} else {
  print "not ok 16\n";
}
while (<FOO>) {
  print;
}
  
if (open FOO, "<:gzip(none)", "ok19") {
  print "ok 18\n";
} else {
  print "not ok 18\n";
}
while (<FOO>) {
  print;
}

if (open FOO, "<", "ok21") {
  print "ok 20\n";
} else {
  print "not ok 20\n";
}
print scalar <FOO>;
if (binmode FOO, ":gzip") { # Ho ho. Switch to gunzip mid stream.
  print "ok 22\n";
} else {
  print "not ok 22\n";
}
print scalar <FOO>;

# Test auto mode
if (open FOO, "<:gzip(auto)", "ok19") {
  print "ok 24\n";
} else {
  print "not ok 24\n";
}
while (<FOO>) {
  if ($_ eq "ok 19\n") {
    print "ok 25\n";
  } else {
    print "ok 25\n";
  }
}

if (open FOO, "<:gzip(auto)", "ok3.gz") {
  print "ok 26\n";
} else {
  print "not ok 26\n";
}
while (<FOO>) {
  if ($_ eq "ok 3\n") {
    print "ok 27\n";
  } else {
    print "not ok 27 # $_\n";
  }
}

if (open FOO, "<:gzip(lazy,auto)", "ok19") {
  print "ok 28\n";
} else {
  print "not ok 28\n";
}
while (<FOO>) {
  if ($_ eq "ok 19\n") {
    print "ok 29\n";
  } else {
    print "ok 29\n";
  }
}

if (open FOO, "<:gzip(auto,lazy)", "ok3.gz") {
  print "ok 30\n";
} else {
  print "not ok 30\n";
}
while (<FOO>) {
  if ($_ eq "ok 3\n") {
    print "ok 31\n";
  } else {
    print "not ok 31 # $_\n";
  }
}

# This should open (auto will find no gzip header and assume deflate stream)
if (open FOO, "<:gzip(auto)", "README") {
  print "ok 32\n";
} else {
  print "not ok 32\n";
}
# But as it's not (meant to be) a deflate stream it (hopefully) will go wrong
# here
$line = <FOO>;
if (defined $line) {
  print "not ok 33 # $_\n";
} else {
  print "ok 33\n";
}

# This should open (lazy mode)
if (open FOO, "<:gzip(auto,lazy)", "README") {
  print "ok 34\n";
} else {
  print "not ok 34\n";
}
# But as the gzip header check is on first read it should fail here
$line = <FOO>;
if (defined $line) {
  print "not ok 35 # $_\n";
} else {
  print "ok 35\n";
}

if (system "gzip -c --fast $^X >perl.gz") {
  print "ok 36 # skipping .. gzip -c -fast $^X >perl.gz  failed\nok 36";
} else {
  if (open GZ, "<:gzip", "perl.gz") {
    print "ok 36\n";
  } else {
    print "not ok 36\n";
  }
  
  if (compare ($^X, \*GZ) == 0) {
    print "ok 37\n";
  } else {
    print "not ok 37\n";
  }

  if (close GZ) {
    print "ok 38\n";
  } else {
    print "not ok 38\n";
  }
}
while (-f "perl.gz") {
  unlink "perl.gz" or die $!;
}

# OK. autopop mode. muhahahahaha

if (open FOO, "<:gzip(autopop)", "README") {
  print "ok 39\n";
} else {
  print "not ok 39\n";
}
print "not " unless defined <FOO>;
print "ok 40\n";

# Verify that line 2 of REAME starts with = signs
$line = <FOO>;
print "not " unless $line =~ /^======/;
print "ok 41\n";

if (open FOO, "<:gzip(autopop)", "ok3.gz") {
  print "ok 42\n";
} else {
  print "not ok 42\n";
}
while (<FOO>) {
  if ($_ eq "ok 3\n") {
    print "ok 43\n";
  } else {
    print "not ok 43 # $_\n";
  }
}

# autopop writes should work
if (open FOO, ">:gzip(autopop)", "empty") {
  print "ok 44\n";
} else {
  print "not ok 44\n";
}
if (print FOO "ok 47\n") {
  print "ok 45\n";
} else {
  print "not ok 45\n";
}
if (open FOO, "<empty") {
  print "ok 46\n";
} else {
  print "not 46\n";
}
print while <FOO>;
if (close FOO) {
  print "ok 48\n";
} else {
  print "not ok 48\n";
}

# Verify that short files get an error on close
if (open FOO, "<:gzip", "ok50.gz.short") {
  print "ok 49\n";
} else {
  print "not ok 49\n";
}
while (<FOO>) {
  print;
}
if (eof FOO) {
  print "ok 51\n";
} else {
  print "not ok 51\n";
}
# this should error
if (close FOO) {
  print "not ok 52\n";
} else {
  print "ok 52\n";
}

# Verify that files with erroroneous lengths get an error on close
if (open FOO, "<:gzip", "ok54.gz.len") {
  print "ok 53\n";
} else {
  print "not ok 53\n";
}
while (<FOO>) {
  print;
}
if (eof FOO) {
  print "ok 55\n";
} else {
  print "not ok 55\n";
}
# this should error
if (close FOO) {
  print "not ok 56\n";
} else {
  print "ok 56\n";
}

# Verify that files with erroroneous crc get an error on close
if (open FOO, "<:gzip", "ok58.gz.crc") {
  print "ok 57\n";
} else {
  print "not ok 57\n";
}
while (<FOO>) {
  print;
}
if (eof FOO) {
  print "ok 59\n";
} else {
  print "not ok 59\n";
}
# this should error
if (close FOO) {
  print "not ok 60\n";
} else {
  print "ok 60\n";
}

# writes now work  
if (open FOO, ">:gzip", "foo") {
  print "ok 61\n";
} else {
  print "not ok 61\n";
}
if (close FOO) {
  print "ok 62\n";
} else {
  print "not ok 62\n";
}
if (-s "foo" == 20) {
  print "ok 63\n";
} else {
  printf "not ok 63 # -s foo is %d, not 20\n", -s "foo";
}

if (open FOO, ">:gzip", "foo") {
  print "ok 64\n";
} else {
  print "not ok 64\n";
}
if (print FOO "ok 68\n") {
  print "ok 65\n";
} else {
  print "not ok 65 # $!\n";
}
if (close FOO) {
  print "ok 66\n";
} else {
  print "not ok 66\n";
}
if (open FOO, "<:gzip", "foo") {
  print "ok 67\n";
} else {
  print "not ok 67\n";
}
print while defined ($_ = <FOO>);
if (close FOO) {
  print "ok 69\n";
} else {
  print "not ok 69\n";
}

if (-s $Config{'sh'}) {
  open FOO, "<", $Config{'sh'} or die $!;
  binmode FOO;
  undef $/;

  my $sh = <FOO>;
  die "Can't slurp $Config{'sh'}: $!" unless defined $sh;
  die sprintf ("Slurped %d, but disk file $Config{'sh'} is %d bytes",
	       length $sh, -s $Config{'sh'})
    unless length $sh == -s $Config{'sh'};
  close FOO or die "Close failed: $!";

  if (open GZ, ">:gzip", "foo") {
    print "ok 70\n";
  } else {
    print "not ok 70\n";
  }
  
  if (print GZ $sh) {
    print "ok 71\n";
  } else {
    print "not ok 71\n";
  }
  if (close GZ) {
    print "ok 72\n";
  } else {
    print "not ok 72\n";
  }

  if (open GZ, "<:gzip", "foo") {
    print "ok 73\n";
  } else {
    print "not ok 73\n";
  }
  if (compare (\*GZ, $Config{'sh'}) == 0) {
    print "ok 74\n";
  } else {
    print "not ok 74\n";
  }
  if (close GZ) {
    print "ok 75\n";
  } else {
    print "not ok 75\n";
  }

  # Unbuffered layer below worked from 0.01, but no standard regression tests
  # for it (I just ran the regular tests with PERLIO=unix)
  # you'll need 8825 (ish) or later for these three to work
  if (open GZ, "<:unix:gzip", "foo") {
    print "ok 76\n";
  } else {
    print "not ok 76\n";
  }
  if (compare (\*GZ, $Config{'sh'}) == 0) {
    print "ok 77\n";
  } else {
    print "not ok 77\n";
  }
  if (close GZ) {
    print "ok 78\n";
  } else {
    print "not ok 78\n";
  }
} else {
  print "ok $_ # skipping\n" foreach (70..78);
}

while (-f "foo") {
  unlink "foo" or die $!;
}

if (open GZ, ">:gzip(lazy)", "empty") {
  print "ok 79\n";
} else {
  print "not ok 79\n";
}
if (close GZ) {
  print "ok 80\n";
} else {
  print "not ok 80\n";
}
if (-z "empty") {
  print "ok 81\n";
} else {
  printf "not ok 81 # -s empty is %d\n", -s "empty";
}

if (open GZ, ">:gzip(lazy)", "foo") {
  print "ok 82\n";
} else {
  print "not ok 82\n";
}
if (print GZ "ok 87\n") {
  print "ok 83\n";
} else {
  print "not ok 83\n";
}
{
  local $\ = "\n";
  if (print GZ "ok 88") {
    print "ok 84";
  } else {
    print "not ok 84";
  }
}
if (close GZ) {
  print "ok 85\n";
} else {
  print "not ok 85\n";
}
if (open GZ, "<:gzip", "foo") {
  print "ok 86\n";
} else {
  print "not ok 86\n";
}
print while defined ($_ = <GZ>);
if (close GZ) {
  print "ok 89\n";
} else {
  print "not ok 89\n";
}

if (open FOO, ">:gzip(none)", "foo") {
  print "ok 90\n";
} else {
  print "not ok 90\n";
}
if (print FOO "ok 95\n") {
  print "ok 91\n";
} else {
  print "not ok 91\n";
}
if (close FOO) {
  print "ok 92\n";
} else {
  print "not ok 92\n";
}
# No header. Should fail
if (open FOO, "<:gzip", "foo") {
  print "not ok 93\n";
} else {
  print "ok 93\n";
}
if (open FOO, "<:gzip(none)", "foo") {
  print "ok 94\n";
} else {
  print "not ok 94\n";
}
print while defined ($_ = <FOO>);
if (close FOO) {
  print "ok 96\n";
} else {
  print "not ok 96\n";
}

while (-f "foo") {
  # VMS is going to have several of these, isn't it?
  unlink "foo" or die $!;
}

# Read/writes don't work
if (open FOO, "+<:gzip", "empty") {
  print "not ok 97\n";
} else {
  print "ok 97\n";
}
if (open FOO, "+>:gzip(lazy)", "empty") {
  print "not ok 98\n";
} else {
  print "ok 98\n";
}
while (-f "empty") {
  # VMS is going to have several of these, isn't it?
  unlink "empty" or die $!;
}
