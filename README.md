# NAME

Data::Hash::Patch::Smart - Apply structural, wildcard, and array-aware patches to Perl data structures

# SYNOPSIS

    use Data::Hash::Patch::Smart qw(patch);

    my $data = {
        users => {
            alice => { role => 'user' },
            bob   => { role => 'admin' },
        }
    };

    my $changes = [
        { op => 'change', path => '/users/alice/role', to => 'admin' },
        { op => 'add',    path => '/users/bob/tags/0', value => 'active' },
        { op => 'remove', path => '/users/*/deprecated' },
    ];

    my $patched = patch($data, $changes, strict => 1);

# DESCRIPTION

`Data::Hash::Patch::Smart` applies structured patches to nested Perl
data structures. It is the companion to `Data::Hash::Diff::Smart` and
supports:

- Hash and array navigation via JSON-Pointer-like paths
- Index arrays (ordered semantics)
- Unordered arrays (push/remove semantics)
- Structural wildcards (`/foo/*/bar`)
- `create_missing` mode for auto-creating intermediate containers
- `strict` mode for validating paths
- Cycle-safe wildcard traversal

The goal is to provide a predictable, expressive patch engine suitable
for configuration management, data migrations, and diff/patch
round-tripping.

# PATCH OPERATIONS

Each change is a hashref with:

- `op`

    One of `add`, `remove`, `change`.

- `path`

    Slash-separated path segments.
    Numeric segments index arrays.

- `value` / `from` / `to`

    Payload for the operation.

## Unordered array wildcard

A leaf `*` applies unordered semantics:

    { op => 'add',    path => '/items/*', value => 'x' }
    { op => 'remove', path => '/items/*', from  => 'x' }

## Structural wildcard

A `*` in the parent path matches all children:

    /users/*/role
    /servers/*/ports/*

# ERROR HANDLING

## Strict mode

Strict mode enforces:

- Missing hash keys
- Out-of-bounds array indices
- Invalid array indices
- Unsupported operations

Wildcard segments do **not** trigger strict errors when no matches exist.

# CYCLE DETECTION

Wildcard traversal detects cycles and throws an exception in strict mode.

# FUNCTIONS

## patch( $data, \\@changes, %opts )

Applies a list of changes to a data structure and returns a deep clone
with the modifications applied.

### Options

- `strict => 1`

    Die on invalid paths, missing keys,
    or out-of-bounds array indices.

- `create_missing => 1`

    Auto-create intermediate hashes and arrays when walking a path.

- `arrays => 'unordered'`

    Enables unordered array semantics for leaf `*` paths.

# SEE ALSO

[Data::Hash::Diff::Smart](https://metacpan.org/pod/Data%3A%3AHash%3A%3ADiff%3A%3ASmart)

1;
