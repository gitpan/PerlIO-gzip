#!perl -w
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test;
BEGIN { plan tests => 62 };
use File::Compare; # This is standard in all distributions that have layers.
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
}
while (-f "perl.gz") {
  unlink "perl.gz" or die $!;
}

# OK. autopop mode. muhahahahaha

if (open FOO, "<:gzip(autopop)", "README") {
  print "ok 38\n";
} else {
  print "not ok 38\n";
}
print "not " unless defined <FOO>;
print "ok 39\n";

# Verify that line 2 of REAME starts with = signs
$line = <FOO>;
print "not " unless $line =~ /^======/;
print "ok 40\n";

if (open FOO, "<:gzip(autopop)", "ok3.gz") {
  print "ok 41\n";
} else {
  print "not ok 41\n";
}
while (<FOO>) {
  if ($_ eq "ok 3\n") {
    print "ok 42\n";
  } else {
    print "not ok 42 # $_\n";
  }
}

# autopop writes should work
if (open FOO, ">:gzip(autopop)", "empty") {
  print "ok 43\n";
} else {
  print "not ok 43\n";
}
if (print FOO "ok 46\n") {
  print "ok 44\n";
} else {
  print "not ok 44\n";
}
if (open FOO, "<empty") {
  print "ok 45\n";
} else {
  print "not 45\n";
}
print while <FOO>;
if (close FOO) {
  print "ok 47\n";
} else {
  print "not ok 47\n";
}

# Verify that short files get an error on close
if (open FOO, "<:gzip", "ok49.gz.short") {
  print "ok 48\n";
} else {
  print "not ok 48\n";
}
while (<FOO>) {
  print;
}
if (eof FOO) {
  print "ok 50\n";
} else {
  print "not ok 50\n";
}
# this should error
if (close FOO) {
  print "not ok 51\n";
} else {
  print "ok 51\n";
}

# Verify that files with erroroneous lengths get an error on close
if (open FOO, "<:gzip", "ok53.gz.len") {
  print "ok 52\n";
} else {
  print "not ok 52\n";
}
while (<FOO>) {
  print;
}
if (eof FOO) {
  print "ok 54\n";
} else {
  print "not ok 54\n";
}
# this should error
if (close FOO) {
  print "not ok 55\n";
} else {
  print "ok 55\n";
}

# Verify that files with erroroneous crc get an error on close
if (open FOO, "<:gzip", "ok57.gz.crc") {
  print "ok 56\n";
} else {
  print "not ok 56\n";
}
while (<FOO>) {
  print;
}
if (eof FOO) {
  print "ok 58\n";
} else {
  print "not ok 58\n";
}
# this should error
if (close FOO) {
  print "not ok 59\n";
} else {
  print "ok 59\n";
}
  
# Writes don't work (yet)
if (open FOO, ">:gzip", "empty") {
  print "not ok 69\n";
} else {
  print "ok 60\n";
}
if (open FOO, ">>:gzip", "empty") {
  print "not ok 61\n";
} else {
  print "ok 61\n";
}
if (open FOO, "+<:gzip", "empty") {
  print "not ok 62\n";
} else {
  print "ok 62\n";
}
while (-f "empty") {
  # VMS is going to have several of these, isn't it?
  unlink "empty" or die $!;
}
