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

	# Split path into segments like ('items', '0') or ('items', '*')
	my @parts = _split_path($path);

	# Leaf is the last segment; parent is everything before it
	my $leaf  = pop @parts;

	# Walk down to the parent container (hash or array)
	my $parent = _walk_to_parent($root, \@parts, $opts);

	# Unordered array semantics: leaf is '*'
	if ($leaf eq '*') {
		if ($op eq 'add') {
			_add_unordered($parent, $c->{value}, $opts);
		}
		elsif ($op eq 'remove') {
			_remove_unordered($parent, $c->{from}, $opts);
		}
		else {
			die "Unsupported op '$op' for unordered path '$path'";
		}
		return;
	}

	# Normal index/hash semantics
	if ($op eq 'change') {
		_set_value($parent, $leaf, $c->{to}, $opts);
	}
	elsif ($op eq 'add') {
		_add_value($parent, $leaf, $c->{value}, $opts);
	}
	elsif ($op eq 'remove') {
		_remove_value($parent, $leaf, $opts);
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

# Walk down the structure following the given path segments,
# stopping at the parent of the leaf. In strict mode, we die
# on invalid paths or type mismatches.
sub _walk_to_parent {
	my ($cur, $parts, $opts) = @_;

	for my $p (@$parts) {

		# Undefined parent: invalid path
		if (!defined $cur) {
			die "Invalid path: encountered undef while walking"
				if $opts->{strict};
			return undef;
		}

		# Hash navigation
		if (ref($cur) eq 'HASH') {
			if (!exists $cur->{$p}) {
				die "Invalid path: missing hash key '$p'"
					if $opts->{strict};
				return undef;
			}
			$cur = $cur->{$p};
			next;
		}

		# Array navigation
		if (ref($cur) eq 'ARRAY') {
			if ($p !~ /^\d+$/ || $p > $#$cur) {
				die "Invalid path: array index '$p' out of bounds"
					if $opts->{strict};
				return undef;
			}
			$cur = $cur->[$p];
			next;
		}

		# Not a container
		die "Invalid path: cannot descend into non-container"
			if $opts->{strict};

		return undef;
	}

	return $cur;
}


sub _set_value {
	my ($parent, $leaf, $value, $opts) = @_;

	if (ref($parent) eq 'HASH') {
		if (!exists $parent->{$leaf} && $opts->{strict}) {
			die "Strict mode: cannot change missing hash key '$leaf'";
		}
		$parent->{$leaf} = $value;
		return;
	}

	if (ref($parent) eq 'ARRAY') {
		if ($leaf !~ /^\d+$/ || $leaf > $#$parent) {
			die "Strict mode: array index '$leaf' out of bounds"
				if $opts->{strict};
		}
		$parent->[$leaf] = $value;
		return;
	}

	die "Strict mode: cannot set value on non-container"
		if $opts->{strict};
}

sub _add_value {
	my ($parent, $leaf, $value, $opts) = @_;

	if (ref($parent) eq 'HASH') {
		if (exists $parent->{$leaf} && $opts->{strict}) {
			die "Strict mode: cannot add existing hash key '$leaf'";
		}
		$parent->{$leaf} = $value;
		return;
	}

	if (ref($parent) eq 'ARRAY') {
		if ($leaf !~ /^\d+$/) {
			die "Strict mode: invalid array index '$leaf'";
		}
		splice @$parent, $leaf, 0, $value;
		return;
	}

	die "Strict mode: cannot add value to non-container"
		if $opts->{strict};
}

sub _remove_value {
	my ($parent, $leaf, $opts) = @_;

	if (ref($parent) eq 'HASH') {
		if (!exists $parent->{$leaf} && $opts->{strict}) {
			die "Strict mode: cannot remove missing hash key '$leaf'";
		}
		delete $parent->{$leaf};
		return;
	}

	if (ref($parent) eq 'ARRAY') {
		if ($leaf !~ /^\d+$/ || $leaf > $#$parent) {
			die "Strict mode: array index '$leaf' out of bounds";
		}
		splice @$parent, $leaf, 1;
		return;
	}

	die "Strict mode: cannot remove value from non-container"
		if $opts->{strict};
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
	my ($parent, $value, $opts) = @_;

	die "Unordered remove requires an array parent"
		unless ref($parent) eq 'ARRAY';

	for (my $i = 0; $i < @$parent; $i++) {
		if (!defined $parent->[$i] && !defined $value) {
			splice @$parent, $i, 1;
			return;
		}
		if (defined $parent->[$i] && defined $value && $parent->[$i] eq $value) {
			splice @$parent, $i, 1;
			return;
		}
	}

	die "Unordered remove: value '$value' not found" if $opts->{strict};

	# Non-strict: silently ignore
}

# Apply a change to all paths matching a wildcard pattern.
# Example pattern: ['users', '*', 'password']
#
# We recursively walk the data structure, matching literal segments
# and branching on '*' segments.
sub _apply_wildcard {
	my ($cur, $parts, $change, $opts, $depth) = @_;

	$depth //= 0;

	# If we've consumed all parts, we are at the leaf.
	if ($depth == @$parts) {
		# Apply the operation to this exact location.
		# We treat this as a non-wildcard leaf.
		my $op = $change->{op};

		if ($op eq 'change') {
			# Replace the entire subtree
			return $change->{to};
		}
		elsif ($op eq 'add') {
			# For wildcard add, we push into arrays or set hash keys
			# but since wildcard leafs are ambiguous, we do nothing here.
			# Wildcard adds are only meaningful when the leaf is '*'
			return $cur;
		}
		elsif ($op eq 'remove') {
			# Remove the entire subtree
			return undef;
		}
		else {
			die "Unsupported wildcard op: $op";
		}
	}

	my $seg = $parts->[$depth];

	# Literal segment: descend into matching child
	if ($seg ne '*') {
		if (ref($cur) eq 'HASH' && exists $cur->{$seg}) {
			$cur->{$seg} = _apply_wildcard($cur->{$seg}, $parts, $change, $opts, $depth+1);
		}
		elsif (ref($cur) eq 'ARRAY' && $seg =~ /^\d+$/ && $seg <= $#$cur) {
			$cur->[$seg] = _apply_wildcard($cur->[$seg], $parts, $change, $opts, $depth+1);
		}
		return;
	}

	# Wildcard segment: match all children at this level
	if (ref($cur) eq 'HASH') {
		for my $k (sort keys %$cur) {
			$cur->{$k} = _apply_wildcard($cur->{$k}, $parts, $change, $opts, $depth+1);
		}
	}
	elsif (ref($cur) eq 'ARRAY') {
		for my $i (0 .. $#$cur) {
			$cur->[$i] = _apply_wildcard($cur->[$i], $parts, $change, $opts, $depth+1);
		}
	}
}

1;
