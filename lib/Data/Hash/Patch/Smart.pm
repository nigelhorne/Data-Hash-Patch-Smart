package Data::Hash::Patch::Smart;

use strict;
use warnings;

use Exporter 'import';
use Data::Hash::Patch::Smart::Engine ();

our @EXPORT_OK = qw(patch);

sub patch {
    my ($data, $changes, %opts) = @_;

    die "patch() expects an arrayref of changes"
        unless ref($changes) eq 'ARRAY';

    return Data::Hash::Patch::Smart::Engine::patch($data, $changes, %opts);
}

1;
