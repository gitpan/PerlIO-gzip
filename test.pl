#!perl -w
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test;
BEGIN { plan tests => 40 };
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


# Writes don't work (yet)
if (open FOO, ">:gzip", "empty") {
  print "not ok 38\n";
} else {
  print "ok 38\n";
}
if (open FOO, ">>:gzip", "empty") {
  print "not ok 39\n";
} else {
  print "ok 39\n";
}
if (open FOO, "+<:gzip", "empty") {
  print "not ok 40\n";
} else {
  print "ok 40\n";
}
while (-f "empty") {
  # VMS is going to have several of these, isn't it?
  unlink "empty" or die $!;
}
