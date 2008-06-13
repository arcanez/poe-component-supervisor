#!/usr/bin/perl

sub POE::Kernel::USE_SIGCHLD () { 1 }

use strict;
use warnings;

use Log::Dispatch::Config::TestLog;

use Test::More 'no_plan';

use ok 'POE::Component::Supervisor';
use ok 'POE::Component::Supervisor::Supervised::Proc';

use POE;

{
    # test a simple explicit stop scenario

    my $output = 0;
    my $pid;

    my ( $supervisor, $child );

    POE::Session->create(
        inline_states => {
            _start => sub {
                $supervisor = POE::Component::Supervisor->new(
                    children => [
                        $child = POE::Component::Supervisor::Supervised::Proc->new(
                            program => sub {
                                while (1) {
                                    print "$$\n";
                                    select(undef,undef,undef,0.1);
                                }
                            },
                            stdout_callback => sub { $pid ||= 0 + $_[ARG0]; $output++ },
                        ),
                    ],
                );

                $_[KERNEL]->delay_set( stop_child => 0.1 );
            },
            stop_child => sub {
                $supervisor->logger->debug("delay expired, stoping child");
                $supervisor->stop($child);
            },
        },
    );

    $poe_kernel->run;

    cmp_ok( $output, '>=', 1, "output" );
    cmp_ok( $output, '<=', 2, "output" );

    isnt( $pid, $$, "pid was diff" );
}

{
    # normal exit scenario

    my @pids;

    my ( $supervisor, $child );

    POE::Session->create(
        inline_states => {
            _start => sub {
                $supervisor = POE::Component::Supervisor->new(
                    children => [
                        $child = POE::Component::Supervisor::Supervised::Proc->new(
                            program => sub {
                                print "$$\n";
                                exit 0; # it's transient, so exit with status 0 is acceptable
                            },
                            stdout_callback => sub { push @pids, 0 + $_[ARG0] },
                        ),
                    ],
                );
            },
        },
    );

    $poe_kernel->run;

    is( scalar(@pids), 1, "one child" );
    isnt( $pids[0], $$, "pid was diff" );
}


{
    # restart scenario

    my @pids;

    my ( $supervisor, $child );

    POE::Session->create(
        inline_states => {
            _start => sub {
                $supervisor = POE::Component::Supervisor->new(
                    children => [
                        $child = POE::Component::Supervisor::Supervised::Proc->new(
                            program => sub {
                                print "$$\n";
                                exit 1;
                            },
                            stdout_callback => sub { push @pids, 0 + $_[ARG0] },
                        ),
                    ],
                );

                $_[KERNEL]->delay_set( stop_child => 0.5 );
            },
            stop_child => sub {
                $supervisor->stop($child);
            },
        },
    );

    $poe_kernel->run;

    cmp_ok( scalar(@pids), '>=', 2, "at least two children" );
    isnt( $pids[0], $$, "pid was diff" );
    isnt( $pids[1], $$, "pid was diff" );
    isnt( $pids[0], $pids[1], "pids are distinct" );
}

{
    # normal exit scenario

    my @pids;

    my $supervisor;

    POE::Session->create(
        inline_states => {
            _start => sub {
                $supervisor = POE::Component::Supervisor->new(
                    children => [
                        map {
                            my $i = $_;
                            POE::Component::Supervisor::Supervised::Proc->new(
                                program => sub {
                                    print "$$\n";
                                    exit 0;
                                },
                                stdout_callback => sub { push @pids, 0 + $_[ARG0] },
                            ),
                        } ( 1 .. 5 ),
                    ],
                );
            },
        },
    );

    $poe_kernel->run;

    is( scalar(@pids), 5, "5 children" );
    
    foreach my $pid ( @pids ) {
        isnt( $pid, $$, "pid was diff" );
    }
}

