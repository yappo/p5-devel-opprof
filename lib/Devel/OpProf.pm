package Devel::OpProf;
use strict;
use warnings;
our $VERSION = '0.01';

use XSLoader;
XSLoader::load 'Devel::OpProf', $VERSION;

use B qw(walkoptree svref_2object ppname);

sub profile {
    my $code = shift;

    # getting running status
    my $profile = {};
    start($profile);
    $code->();
    stop();

    # get op tree
    my $max_seq = 0;
    local *B::OP::for_opprof = sub {
        my $self = shift;
        my $seq  = $self->seq;
        my $stash = $profile->{$seq};
        return unless $stash;

        $stash->{on_inner} = 1;
        $stash->{class}    = ref($self);
        $stash->{name}     = $self->name;
        $stash->{desc}     = $self->desc;

        $max_seq = $seq if $max_seq < $seq;
    };
    local *B::NULL::for_opprof = sub { warn 'NULL' };

    walkoptree(svref_2object($code)->ROOT, 'for_opprof');

    # grep real running opes
    my $running_profile = {};
    my $skip_prepare_op = 1;
    for my $seq (sort { $a <=> $b } keys %{ $profile }) {
        my $stash = $profile->{$seq};

        # skips to prepare phase
        if ($skip_prepare_op) {
            if (ppname($stash->{type}) eq 'pp_entersub') {
                $skip_prepare_op = 0;
            }
            next;
        }
        last if $max_seq eq $seq;  # strip to leavesub on callback code

        if (!$stash->{on_inner}) {
            # running external sub
            $stash->{on_inner} = 0;
            $stash->{class}    = 'external';
            $stash->{name}     = ppname($stash->{type});
            $stash->{desc}     = '';
        }

        $running_profile->{$seq} = $profile->{$seq};
    }

    $running_profile;
}

sub show_profile {
    my $profile = profile(@_);
    my $level = 0;

    my $total_steps = 0;
    my $total_usec  = 0;
    for my $seq (sort { $a <=> $b } keys %{ $profile }) {
        my $stash = $profile->{$seq};
        $level-- if $stash->{name} =~ /leave/;

        printf "%s%s(%s): %s(%s): %s steps, user time: %s/%s usec/avg\n",
            ('    ' x $level ),
            $stash->{class}, $seq,
            $stash->{name}, $stash->{desc},
            $stash->{steps},
            $stash->{usec}, ($stash->{usec} / $stash->{steps});

        $total_steps += $stash->{steps};
        $total_usec  += $stash->{usec};

        $level++ if $stash->{name} =~ /enter(?!sub)/;
    }

    printf "Result:\n";
    printf "     total steps : %s\n", $total_steps;
    printf " total user time : %s usec\n", $total_usec;
    printf "             avg : %s\n", ($total_usec / $total_steps);
}

1;

__END__

=head1 name

Devel::OpProf - OP code profiler

=head1 SYNOPSIS

  use Devel::OpProf;

  Devel::OpProf::show_profile(sub {
     my $i = 0;
     for (0..100) {
         $i += $_;
     }
  });

=head1 DESCRIPTION

Devel::OpProf is

=head1 AUTHOR

Kazuhiro Osawa E<lt>yappo <at> shibuya <döt> plE<gt>

=head1 SEE ALSO

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

