package Data::Hash::Patch::Smart::Engine;

use strict;
use warnings;

use Storable qw(dclone);

sub patch {
    my ($data, $changes, %opts) = @_;

    my $copy = dclone($data);

    for my $c (@$changes) {
        _apply_change($copy, $c, \%opts);
    }

    return $copy;
}

sub _apply_change {
    my ($root, $c, $opts) = @_;

    my $op   = $c->{op}   or die "change missing op";
    my $path = $c->{path} or die "change missing path";

    # Split path into segments
    my @parts = _split_path($path);

    # Leaf is the last segment; parent is everything before it
    my $leaf  = pop @parts;

    my $parent = _walk_to_parent($root, \@parts, $opts);

    # Unordered array semantics: leaf is '*'
    if ($leaf eq '*') {
        if ($op eq 'add') {
            _add_unordered($parent, $c->{value});
        }
        elsif ($op eq 'remove') {
            _remove_unordered($parent, $c->{from});
        }
        else {
            die "Unsupported op '$op' for unordered path '$path'";
        }
        return;
    }

    # Normal index/hash semantics
    if ($op eq 'change') {
        _set_value($parent, $leaf, $c->{to});
    }
    elsif ($op eq 'add') {
        _add_value($parent, $leaf, $c->{value});
    }
    elsif ($op eq 'remove') {
        _remove_value($parent, $leaf);
    }
    else {
        die "Unsupported op: $op";
    }
}

sub _split_path {
    my ($path) = @_;
    return () if !defined $path || $path eq '';
    my @parts = grep { length $_ } split m{/}, $path;
    return @parts;
}

sub _walk_to_parent {
    my ($cur, $parts, $opts) = @_;

    for my $p (@$parts) {
        if (ref($cur) eq 'HASH') {
            $cur = $cur->{$p};
        }
        elsif (ref($cur) eq 'ARRAY') {
            $cur = $cur->[$p];
        }
        else {
            die "Cannot walk into non-container at segment '$p'";
        }
    }

    return $cur;
}

sub _set_value {
    my ($parent, $leaf, $value) = @_;

    if (ref($parent) eq 'HASH') {
        $parent->{$leaf} = $value;
    }
    elsif (ref($parent) eq 'ARRAY') {
        $parent->[$leaf] = $value;
    }
    else {
        die "Cannot set value on non-container";
    }
}

sub _add_value {
    my ($parent, $leaf, $value) = @_;

    if (ref($parent) eq 'HASH') {
        $parent->{$leaf} = $value;
    }
    elsif (ref($parent) eq 'ARRAY') {
        # index mode: insert at position, shifting later elements
        splice @$parent, $leaf, 0, $value;
    }
    else {
        die "Cannot add value to non-container";
    }
}

sub _remove_value {
    my ($parent, $leaf) = @_;

    if (ref($parent) eq 'HASH') {
        delete $parent->{$leaf};
    }
    elsif (ref($parent) eq 'ARRAY') {
        # index mode: remove element, shifting later elements
        splice @$parent, $leaf, 1;
    }
    else {
        die "Cannot remove value from non-container";
    }
}

# Add a value to an unordered array.
# We treat the parent as an arrayref and simply push the new value.
sub _add_unordered {
    my ($parent, $value) = @_;

    die "Unordered add requires an array parent"
        unless ref($parent) eq 'ARRAY';

    push @$parent, $value;
}

# Remove a single matching value from an unordered array.
# We scan linearly and delete the first element that compares equal.
sub _remove_unordered {
    my ($parent, $value) = @_;

    die "Unordered remove requires an array parent"
        unless ref($parent) eq 'ARRAY';

    for (my $i = 0; $i < @$parent; $i++) {
        # Simple string/defined comparison; this matches how the diff engine
        # treats unordered values (stringified keys).
        if (defined $parent->[$i] && $parent->[$i] eq $value) {
            splice @$parent, $i, 1;
            return;
        }
        elsif (!defined $parent->[$i] && !defined $value) {
            splice @$parent, $i, 1;
            return;
        }
    }

    # In non-strict mode we silently do nothing if the value is not found.
    # Later we can add a 'strict' option to turn this into a fatal error.
}


1;
