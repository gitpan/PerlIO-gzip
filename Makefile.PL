require 5.007; # Stop perl 5.005 or earler barfing on the v string
# require 5.7.0;
use ExtUtils::MakeMaker;
use Config;

unless ($Config{useperlio} eq 'define' and $Config{usesfio} eq 'false') {
  die <<BARF;
You need perl 5.7.0 or later, configured to use perlio (and not to use sfio)
Yes, this module is currently only suitable for the development branch of
perl

Note
  1: The features required for layers have only recently been added to
     development perl, so if your doesn't have the header perliol.h it's
     to old
  2: perlio is not the default Configure choices, as it does not give binary
     compatibility with previous perl versions. You may need to compile a
     new perl from source if you are unable to find a perl precompiled with
     these options.
BARF
}

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'PerlIO::gzip',
    'VERSION_FROM'	=> 'gzip.pm', # finds $VERSION
    'PREREQ_PM'		=> {}, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => 'gzip.pm', # retrieve abstract from module
       AUTHOR     => 'Nicholas Clark <nick@talking.bollo.cx>') : ()),
    'LIBS'		=> ['-lz'],
    'DEFINE'		=> '-g -DDEBUG_LAYERGZIP',
	# Insert -I. if you add *.h files later:
    'INC'		=> '', # e.g., '-I/usr/include/other'
	# Un-comment this if you add C files to link with later:
    # 'OBJECT'		=> '$(O_FILES)', # link all the C files too
);

# Check out Radioactive::Decay at http://belfast.pm.org/Modules/
# It might be more useful than this module :-)
