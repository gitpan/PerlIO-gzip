package PerlIO::gzip;

use 5.006;
use strict;
use warnings;

require DynaLoader;

our @ISA = qw(DynaLoader);
our $VERSION = '0.03';

bootstrap PerlIO::gzip $VERSION;

1;
__END__

=head1 NAME

PerlIO::gzip - Perl extension to provide a PerlIO layer to gzip/gunzip

=head1 SYNOPSIS

  use PerlIO::gzip;
  open FOO, "<:gzip", "file.gz" or die $!;
  print while <FOO>; # And it will be uncompressed.

  binmode FOO, ":gzip(none)" # Starts reading deflate stream from here on.

=head1 DESCRIPTION

PerlIO::gzip provides a PerlIO layer that manipulates files in the format used
by the C<gzip> program.  Currently only decompression is implemented.

=head1 EXPORT

PerlIO::gzip exports no subroutines or symbols, just a perl layer C<gzip>

=head1 LAYER ARGUMENTS

The C<gzip> layer takes a comma separated list of arguments. 3 exclusive
options choose the header checking mode:

=over 4

=item gzip

The default. Expects a standard gzip file header

=item none

Expects no file header; assumes the file handle is immediately  a deflate
stream (eg as would be found inside a C<zip> file)

=item auto

Potentially dangerous. If the first two bytes match the C<gzip> header
"\x1f\x8b" then a gzip header is assumed (and checked) else a deflate stream
is assumed

=back

Optionally you can add this flag:

=over 4

=item lazy

Defer header checking until the first read.  By default, gzip header
checking is done before the C<open> (or C<binmode>) returns, so if an error
is detected in the gzip header the C<open> or C<binmode> will fail.  However,
this will require reading some data.  With lazy set the check is deferred
until the first read, so the C<open> should always succeed, but any problems
with the header will cause an error on read.

  open FOO, "<:gzip(lazy)", "file.gz" or die $!; # Dangerous.
  while (<FOO>) {
    print;
  } # Whoa. Bad. You're not distinguishing between errors and EOF.

If you're not careful you won't spot the errors - like the example above
you'll think you got end of file.

=back

=head1 AUTHOR

Nicholas Clark, E<lt>nick@talking.bollo.cxE<gt>

=head1 SEE ALSO

L<perl>, L<gzip>.

=cut
