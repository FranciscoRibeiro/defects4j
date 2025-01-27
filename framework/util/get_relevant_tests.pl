#!/usr/bin/env perl
#
#-------------------------------------------------------------------------------
# Copyright (c) 2014-2019 René Just, Darioush Jalali, and Defects4J contributors.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROBIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#-------------------------------------------------------------------------------

=pod

=head1 NAME

get_relevant_tests.pl -- determine the set of relevant tests for a set of bugs of a given project.

=head1 SYNOPSIS

  get_relevant_tests.pl -p project_id [-b bug_id] [-t tmp_dir] [-o out_dir] [-l|--loaded]

=head1 OPTIONS

=over 4

=item -p C<project_id>

The id of the project for which the relevant tests are determined.

=item -b C<bug_id>

Only determine relevant tests for this bug id (optional). Format: C<\d+>

=item B<-t F<tmp_dir>>

The temporary root directory to be used to check out revisions (optional).
The default is F</tmp>.

=item B<-o F<out_dir>>

The output directory to be used (optional).
The default is F<relevant_tests> in Defects4J's project directory.

=item B<-l|--loaded>

If enabled, gets relevant tests of loaded classes instead of modified classes (optional).
Disabled by default.

=back

=head1 DESCRIPTION

Determines the set of relevant tests for each bug (or a particular bug) of a
given project. The script stops as soon as an error occurs for any project version.

=cut

use warnings;
use strict;

use FindBin;
use File::Basename;
use Cwd qw(abs_path);
use Getopt::Long;
use Pod::Usage;

use lib abs_path("$FindBin::Bin/../core");
use Constants;
use Project;

#
# Process arguments and issue usage message if necessary.
#
my %cmd_opts;
GetOptions(\%cmd_opts,
	   "p=s",
	   "b=i",
	   "t=s",
	   "o=s",
	   "loaded") or pod2usage(1);

pod2usage(1) unless defined $cmd_opts{p};

my $PID = $cmd_opts{p};
my $BID = $cmd_opts{b};
my $TYPE_OF_CLASSES = defined $cmd_opts{loaded} ? "loaded" : "modified";

# Set up project
my $TMP_DIR = Utils::get_tmp_dir($cmd_opts{t});
system("mkdir -p $TMP_DIR");
my $project = Project::create_project($PID);
$project->{prog_root} = $TMP_DIR;
my $project_dir = "$PROJECTS_DIR/$PID";
my $out_dir = $cmd_opts{o} // "$project_dir/relevant_tests";

my @ids;
if (defined $BID) {
    $BID =~ /^(\d+)$/ or die "Wrong bug_id format: $BID! Expected: \\d+";
    @ids = ($BID);
} else {
    @ids = $project->get_bug_ids();
}

foreach my $id (@ids) {
    printf ("%4d: $project->{prog_name}\n", $id);
    my $vid = "${id}f";
    $project->checkout_vid($vid) or die "Could not checkout ${vid}";
    $project->fix_tests($vid);
    $project->compile() or die "Could not compile";
    $project->compile_tests() or die "Could not compile tests";

    # Hash all modified/loaded classes
    my %mod_classes = ();
    open(IN, "<${project_dir}/$TYPE_OF_CLASSES\_classes/${id}.src") or die "Cannot read $TYPE_OF_CLASSES classes";
    while(<IN>) {
        chomp;
        $mod_classes{$_} = 1;
    }
    close(IN);

    # Result: list of relevant tests
    my @relevant = ();

    my $error = 0;

    # Iterate over all tests and determine whether or not a test is relevant
    my @all_tests = `cd $TMP_DIR && $SCRIPT_DIR/bin/defects4j export -ptests.all`; 
    foreach my $test (@all_tests) {
        chomp($test);
        print(STDERR "Analyze test: $test\n");
        my $loaded = $project->monitor_test($test, $vid);
        unless (defined $loaded) {
            print(STDERR "Failed test: $test\n");
            # Indicate error and skip all remaining tests
            $error = 1;
            last;
        }
        foreach my $class (@{$loaded->{src}}) {
            if (defined $mod_classes{$class}) {
                push(@relevant, $test);
                # A test is relevant if it loads at least one of the modified
                # classes!
                last;
            }
        }
    }
    if ($error == 1) {
        print(STDERR "Failed version: $id\n");
    } else {
        open(OUT, ">${out_dir}/${id}") or die "Cannot write relevant tests";
        for (@relevant) {
            print(OUT $_, "\n"); 
        }
        close(OUT);
    }
}
# Clean up
system("rm -rf $TMP_DIR");
