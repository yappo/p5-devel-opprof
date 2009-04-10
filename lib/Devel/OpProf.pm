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
    local *B::OP::for_opprof = sub {
        my $self = shift;
        my $seq  = $self->seq;
        my $stash = $profile->{$seq};
        return unless $stash;

        $stash->{on_inner} = 1;
        $stash->{class}    = ref($self);
        $stash->{name}     = $self->name;
        $stash->{desc}     = $self->desc;
    };
    local *B::NULL::for_opprof = sub { warn 'NULL' };

    walkoptree(svref_2object($code)->ROOT, 'for_opprof');

    # grep real running opes
    my $running_profile = {};
    my $skip_prepare_op = 1;
    my $last_step_seq;
    for my $seq (sort { $a <=> $b } keys %{ $profile }) {
        my $stash = $profile->{$seq};

        if ($stash->{before_op_seq} && $profile->{$stash->{before_op_seq}}->{package} eq __PACKAGE__) {
            # delete first steps
            next;
        }

        if ($stash->{package} eq __PACKAGE__) {
            if ($stash->{before_op_seq} && $profile->{$stash->{before_op_seq}}->{package} ne __PACKAGE__) {
                # save last step seq
                $last_step_seq = $stash->{before_op_seq};
            }

            # delete bootstrap steps
            next;
        }

        if (!$stash->{on_inner}) {
            # running external sub
            $stash->{on_inner} = 0;
            $stash->{class}    = 'external';
            $stash->{name}     = ppname($stash->{type});
            $stash->{desc}     = '';
        }

        $running_profile->{$seq} = $profile->{$seq};
    }
    delete $running_profile->{$last_step_seq}; # delete last step


    $running_profile;
}

sub _sourcecode_decoration {
    my $profile = shift;

    my %file_cache;
    while (my($seq, $stash) = each %{ $profile }) {
        my $file = $stash->{file};
        my $file_data = $file_cache{$file} || do {
            open my $fh, '<', $file or die $!;
            my @lines = map { s/\n$//; $_ } <$fh>;
            unshift @lines, undef;
            \@lines;
        };
        $stash->{sourcecode} = $file_data->[$stash->{line}];
    }
    $profile;
}

sub show_profile {
    my $profile = _sourcecode_decoration( profile(@_) );
    my $level = 0;

    my $total_steps = 0;
    my $total_usec  = 0;
    my $file_line = '';
    for my $seq (sort { $a <=> $b } keys %{ $profile }) {
        my $stash = $profile->{$seq};
        $level-- if $stash->{name} =~ /leave/;

        my $now_file_line = sprintf "%s, line of %s", 
            $stash->{file}, $stash->{line};
        unless ($file_line eq $now_file_line) {
            $file_line = $now_file_line;
            printf "%s\nin: %s\n", $file_line, $stash->{sourcecode};;
        }
        my $padding_space = ('    ' x $level );

        printf "%s%- 20s%- 20s%s\n", $padding_space,
            ($stash->{class} . "($seq)"),
            $stash->{name}, $stash->{desc};

        printf "%s    STEPS:% 10s, TIME: % 10s usec, AVRG: %s usec\n", $padding_space,
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

