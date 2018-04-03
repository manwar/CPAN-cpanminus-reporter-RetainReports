package CPAN::cpanminus::reporter::RetainReports;
use strict;
use warnings;
use 5.10.1;
use parent ('App::cpanminus::reporter');
our $VERSION = '0.10';
use Carp;
use File::Path qw( make_path );
use File::Spec;
use JSON;
use URI;
use CPAN::DistnameInfo;
use Data::Dump qw( dd pp );

=head1 NAME

CPAN::cpanminus::reporter::RetainReports - Retain reports on disk rather than transmitting them

=head1 SYNOPSIS

    use CPAN::cpanminus::reporter::RetainReports;

    my $cpanmdir                        = '/home/username/.cpanm';
    my $log                             = "$cpanmdir/build.log";
    local $ENV{PERL_CPANM_HOME}         = $cpanmdir;
    local $ENV{PERL_CPAN_REPORTER_DIR}  = '/home/username/.cpanreporter';

    my $reporter = CPAN::cpanminus::reporter::RetainReports->new(
        force               => 1,           # ignore mtime check on cpanm build.log
        build_dir           => $cpanmdir,
        build_logfile       => $log,
        'ignore-versions' => 1,
    );

    my $analysisdir = '/home/username/bbc/testing/results/perl-5.27.0';
    $reporter->set_report_dir($analysisdir);
    $reporter->run;

=head1 DESCRIPTION

This library parses the output of a F<build.log> generated by running
L<cpanm|http://search.cpan.org/~miyagawa/App-cpanminus-1.7043/bin/cpanm> and
writes the output of that parsing to disk for later analysis or processing.

This is B<alpha> code; the API is subject to change.

=head2 Rationale:  Who Should Use This Library?

This library is a subclass of Breno G. de Oliveira's CPAN library
L<App-cpanminus-reporter|http://search.cpan.org/~garu/App-cpanminus-reporter-0.17/>.
That library provides the utility program
F<cpanm-reporter|http://search.cpan.org/dist/App-cpanminus-reporter-0.17/bin/cpanm-reporter>
a way to generate and transmit CPANtesters reports after using Tatsuhiko
Miyagawa's
L<cpanm|http://search.cpan.org/~miyagawa/App-cpanminus-1.7043/bin/cpanm>
utility to install libraries from CPAN.

Like similar test reporting methodologies, F<App-cpanminus-reporter> does not
retain test reports on disk once they have been transmitted to
L<CPANtesters|http://www.cpantesters.org>.  Whether a particular module passed
or failed its tests is very quickly reported to
L<http://fast-matrix.cpantesters.org/> and, after a lag, the complete report
is posted to L<http://matrix.cpantesters.org/>.  That works fine under normal
circumstances, but if there are any technical problems with those websites the
person who ran the tests originally has no easy access to reports --
particularly to reports of failures.  Quick access to reports of test failures
is particularly valuable when testing a library against specific commits to
the Perl 5 core distribution and against Perl's monthly development releases.

This library is intended to provide at least a partial solution to that
problem.  It is intended for use by at least three different kinds of users:

=over 4

=item * People working on the Perl 5 core distribution or the Perl toolchain

These individuals (commonly known as the Perl 5 Porters (P5P) and the Perl
Toolchain Gang) often want to know the impact on the most commonly used CPAN
libraries of (a) a particular commit to Perl 5's master development branch
(known as I<blead>) or some other branch in the repository; or (b) a monthly
development release of F<perl> (5.27.1, 5.27.2, etc.).  After installing
blead, a branch or a monthly dev release, they often want to install hundreds
of modules at a time and inspect the results for breakage.

=item * CPAN library authors and maintainers

A diligent CPAN maintainer pays attention to whether her libraries are
building and testing properly against Perl 5 blead.  Such a maintainer can use
this library to get reports more quickly than waiting upon CPANtesters.

=item * People maintaining lists of CPAN libraries which they customarily install with F<perl>

Organizations which use many CPAN libraries in their production tend to keep a
curated list of them, often in a format like
L<cpanfile|http://search.cpan.org/~miyagawa/Module-CPANfile-1.1002/lib/cpanfile.pod>.
Those organizations can use this library to assess the impact of changes in
blead or a branch or of a monthly dev release on such a list.

=back

=head1 METHODS

=head2 C<new()>

=over 4

=item * Purpose

F<CPAN::cpanminus::reporter::RetainReports> constructor.

=item * Arguments

    my $reporter = CPAN::cpanminus::reporter::RetainReports->new(
        force               => 1,
        build_dir           => $cpanmdir,
        build_logfile       => $log,
        'ignore-versions' => 1,
    );

Takes a list of key-value pairs or hash.  Keys may be any eligible for passing
to C<App::cpanminus::reporter::new()>.  Those shown have proven to be useful
for this library's author.

=item * Return Value

F<CPAN::cpanminus::reporter::RetainReports> object.

=item * Comments

=over 4

=item * Inherited from F<App-cpanminus-reporter>.

=item * Environmental Variables

At this time it is thought that these two environmental variables should be
explicitly set if either the F<.cpanm> or the F<.cpanreporter> directory is in a
non-standard location, I<i.e.,> in a location other than directly under the
user's home directory.

    local $ENV{PERL_CPANM_HOME}         = '/home/username/.cpanm';
    local $ENV{PERL_CPAN_REPORTER_DIR}  = '/home/username/.cpanreporter';

=back

=back

=head2 C<set_report_dir()>

=over 4

=item * Purpose

Identify the directory to which reports will be written, creating it if needed.

=item * Arguments

    $reporter->set_report_dir($analysisdir);

String holding path to desired directory.

=item * Return Value

String holding path to desired directory.

=back

=cut

sub set_report_dir {
    my ($self, $dir) = @_;
    unless (-d $dir) {
        make_path($dir, { mode => 0711 }) or croak "Unable to create $dir";
    }
    $self->{report_dir} = $dir;
}

=head2 C<get_report_dir()>

=over 4

=item * Purpose

Identify the already created directory in which reports will be ridden.

=item * Arguments

    $self->get_report_dir();

None.

=item * Return Value

String holding path to relevant directory.

=back

=cut

sub get_report_dir {
    my $self = shift;
    return $self->{report_dir};
}

=head2 C<parse_uri()>

=over 4

=item * Purpose

While parsing a build log, parse a URI.

=item * Arguments

    $self->parse_uri("http://www.cpan.org/authors/id/J/JK/JKEENAN/Perl-Download-FTP-0.02.tar.gz");

String holding a URI such as the one above.

=item * Return Value

True value upon success; C<undef> otherwise.

=item * Comments

=over 4

=item * Stores the following attributes for a given CPAN distribution:

    distname        => 'Perl-Download-FTP'
    distversion     => '0.02'
    distfile        => 'JKEENAN/Perl-Download-FTP-0.02.tar.gz'
    author          => 'JKEENAN'

These attributes can subsequently be accessed via:

    $self->distname();
    $self->distversion();
    $self->distfile();
    $self->author();

=item * Limited to parsing these URI schemes:

    http https ftp cpan file

=item * Overwrites C<App::cpanminus::reporter::parse_uri()>.

=back

=back

=cut

sub parse_uri {
  my ($self, $resource) = @_;

  my $d = CPAN::DistnameInfo->new($resource);
  $self->distversion($d->version);
  $self->distname($d->dist);

  my $uri = URI->new( $resource );
  my $scheme = lc $uri->scheme;
  my %eligible_schemes = map {$_ => 1} (qw| http https ftp cpan file |);
  if (! $eligible_schemes{$scheme}) {
    print "invalid scheme '$scheme' for resource '$resource'. Skipping...\n"
      unless $self->quiet;
    return;
  }

  my $author;
  if ($scheme eq 'file') {
    # A local file may not be in the correct format for Metabase::Resource.
    # Hence, we may not be able to parse it for the author.
    $author = '';
  }
  else {
    $author = $self->get_author( $uri->path );
  }
  unless (defined $author) {
    print "error fetching author for resource '$resource'. Skipping...\n"
      unless $self->quiet;
    return;
  }

  # the 'LOCAL' user is reserved and should never send reports.
  if ($author eq 'LOCAL') {
    print "'LOCAL' user is reserved. Skipping resource '$resource'\n"
      unless $self->quiet;
    return;
  }

  $self->author($author);

  # If $author eq '', then distfile will be set to $uri.
  $self->distfile(substr("$uri", index("$uri", $author)));

  return 1;
}

sub distversion {
  my ($self, $distversion) = @_;
  $self->{_distversion} = $distversion if $distversion;
  return $self->{_distversion};
}

sub distname {
  my ($self, $distname) = @_;
  $self->{_distname} = $distname if $distname;
  return $self->{_distname};
}

=head2 C<transmit_report()>

=over 4

=item * Purpose

Transmit a report to CPANtesters as well as retaining report on disk.

=item * Arguments

   $self->transmit_report();

=item * Return Value

None.

=item * Comment

This method must be called after C<new()> but before C<run()>.

=back

=cut

sub transmit_report {
    my $self = shift;
    $self->{transmit_report}++;
    return $self;
}

=head2 C<run()>

=over 4

=item * Purpose

Execute a run of processing of a F<cpanm> build log.

=item * Arguments

None.

=item * Return Value

None relevant.

=item * Comments

=over 4

=item *

See the F<examples/> directory for sample reports.

=item *

Inherited from C<App-cpanminus-reporter>.  However, whereas that library's
method composes and transmits a report to L<CPANtesters.org>, this library's
C<run()> method generates a F<.json> report file for each distribution
analyzed and retains that on disk for subsequent processing or analysis.  As
such, this is the crucial difference between this library and
F<App-cpanminus-reporter>.

=item *

In a later version of this library we will provide a more human-friendly,
plain-text version of the report.

=back

=back

=cut

sub make_report {
    my ($self, $resource, $dist, $result, @test_output) = @_;

if ($self->{transmit_report}) { say STDERR "Requesting report transmission"; }
    if ( index($dist, 'Local-') == 0 ) {
        print "'Local::' namespace is reserved. Skipping resource '$resource'\n"
          unless $self->quiet;
        return;
    }
    return unless $self->parse_uri($resource);

    my $author = $self->author;

    my $cpanm_version = $self->{_cpanminus_version} || 'unknown cpanm version';
    my $meta = $self->get_meta_for( $dist );
    my %CTCC_args = (
        author      => $self->author || '',
        distname    => $dist,   # string like: Mason-Tidy-2.57
        grade       => $result,
        via         => "App::cpanminus::reporter $App::cpanminus::reporter::VERSION ($cpanm_version)",
        test_output => join( '', @test_output ),
        prereqs     => ($meta && ref $meta) ? $meta->{prereqs} : undef,
    );
    my $tdir = $self->get_report_dir();
    croak "Could not locate $tdir" unless (-d $tdir);
    my $report = (length $author)
        ? File::Spec->catfile($tdir, join('.' => $self->author, $dist, 'log', 'json'))
        : File::Spec->catfile($tdir, join('.' =>                $dist, 'log', 'json'));
    open my $OUT, '>', $report or croak "Unable to open $report for writing";
    say $OUT encode_json( {
        %CTCC_args,
        'distversion' => $self->distversion,
        'dist'        => $self->distname,   # string like: Mason-Tidy
    } );
    close $OUT or croak "Unable to close $report after writing";

    return unless $self->{transmit_report};

    require CPAN::Testers::Common::Client;
    require Test::Reporter;
    require Test::Reporter::Transport;
  	my $client = CPAN::Testers::Common::Client->new(%CTCC_args);
    if (!$self->skip_history && $client->is_duplicate) {
      print "($resource, $author, $dist, $result) was already sent. Skipping...\n"
        if $self->verbose;
      return;
    }
    else {
      print "sending: ($resource, $author, $dist, $result)\n" unless $self->quiet;
    }
    say STDERR "CPAN::cpanminus::reporter::RetainReports object";
    pp($self);
    say STDERR "CPAN::Testers::Common::Client object";
    pp($client);

    my %TR_args = (
      grade          => $client->grade,
      distribution   => $dist,
      distfile       => $self->distfile,
      comments       => $client->email,
      via            => $client->via,
    );
    say STDERR "XXX: Test::Reporter arguments -- SO FAR!";
    pp(\%TR_args);
    # TODO: Need to get values for transport, transport_args, from
#    my $reporter = Test::Reporter->new(
#      transport      => $self->config->transport_name,
#      transport_args => $self->config->transport_args,
#      grade          => $client->grade,
#      distribution   => $dist,
#      distfile       => $self->distfile,
#      from           => $self->config->email_from,
#      comments       => $client->email,
#      via            => $client->via,
#    );
#    pp($reporter);

#        if ($self->dry_run) {
#          print "not sending (dry run)\n" unless $self->quiet;
#          return;
#        }

#        try {
#          $reporter->send() || die $reporter->errstr();
#        }
#        catch {
#          print "Error while sending this report, continuing with the next one ($_)...\n" unless $self->quiet;
#          print "DEBUG: @_" if $self->verbose;
#        } finally{
#          $client->record_history unless $self->skip_history;
#        };

    return;
}


=head1 BUGS AND SUPPORT

Please report any bugs by mail to C<bug-CPAN-cpanminus-reporter-RetainReports@rt.cpan.org>
or through the web interface at L<http://rt.cpan.org>.

=head1 AUTHOR

    James E Keenan
    CPAN ID: JKEENAN
    jkeenan@cpan.org
    http://thenceforward.net/perl/modules/CPAN-cpanminus-reporter-RetainReports

=head1 COPYRIGHT

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.

=head1 SEE ALSO

perl(1).  cpanm(1).  cpanm-reporter(1).  App::cpanminus(3). App::cpanminus::reporter(3).

=cut

1;

