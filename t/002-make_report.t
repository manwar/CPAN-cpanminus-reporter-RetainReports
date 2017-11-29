# -*- perl -*-
use strict;
use warnings;
use Test::More;
use Data::Dump qw( dd pp );

BEGIN { use_ok( 'App::cpanminus::reporter::RetainReports' ); }

{
    my $reporter = App::cpanminus::reporter::RetainReports->new(verbose => 1);
    ok(defined $reporter, "Inherited constructor returned defined object");
    isa_ok($reporter, 'App::cpanminus::reporter::RetainReports');
    can_ok('App::cpanminus::reporter::RetainReports', qw|
        run
        make_report
    | );
}

{
    my $dir = -d 't' ? 't/data' : 'data';
    my $reporter = App::cpanminus::reporter::RetainReports->new(
      force => 1, # ignore mtime check on build.log
      build_logfile => $dir . '/build.single.log', 
      'ignore-versions' => 1,
      #verbose => 1,
    );
    ok(defined $reporter, 'created new reporter object');

    {
      no warnings 'redefine';
      local *App::cpanminus::reporter::RetainReports::_check_cpantesters_config_data = sub { 1 };
      $reporter->run;
    };
}

done_testing;

