# 1.0.0 source provenance

This record maps the Huawei AppGallery Connect 1.0.0 submission to the first
public HarmoTTY source baseline without publishing the private development
history or production signing material.

## Submitted build authority

| Field | Value |
|---|---|
| Private source commit | `6aafa1079f3218edd3e73f71d05b56accc3d842e` |
| Private source tree | `4022a95a752dab3342dcc3bd8b77f653844f9552` |
| Release ID | `1.0.0` |
| Target ABI | `arm64-v8a` |
| Submitted signed APP SHA-256 | `D758C0D4E36A69A7C75CF504886C9E1A7AE0C1931790CBC9AD505C3E9E32D22C` |

The corresponding HAP, APP, native-library and manifest hashes, signature
verification output, exact source archive and a complete Git bundle are held in
the private release evidence archive. Production signing material remains
outside every Git repository.

## Public baseline identity

The canonical first public baseline is root commit
`93ce79d80533f37ccc7501897d4e92f8549c25de` in the public
`wandcs/harmotty` repository. The commit is also recorded in the private 1.0.0
release evidence.

The public baseline was exported from the private source commit above. Runtime
behavior is preserved, while the public tree deliberately changes
repository-only material as classified below.

## Deliberate public-tree differences

| Category | Public treatment | Reason |
|---|---|---|
| Private Git history and refs | Replaced by a clean root commit | Avoid disclosure of internal investigation and machine history |
| Signing files and release packages | Excluded | Credentials and production artifacts are outside source control |
| Build caches and generated output | Excluded | Reproducible output, not source |
| x86_64/emulator-only files | Excluded | Unsupported product target |
| Internal archived plans and logs | Replaced by a minimal archive notice | Contained obsolete and machine-specific material |
| Documentation and governance | Rewritten for public collaboration | Establish accurate scope, support and contribution rules |
| Public CI and metadata | Added or corrected | Provide reproducible checks and canonical project identity |
| Pure Rust core formatting | `cargo fmt` only | Make the inherited source satisfy the public formatting gate without changing behavior |
| Native build output setup | Create the fixed ARM64 output directory before copying | Make a clean clone build independently of residual local directories |

These changes do not make the public root commit the byte-for-byte source tree
of the already submitted APP. The immutable private commit above remains the
exact build authority for that artifact. The public baseline is its reviewed
open-source continuation, with every difference limited to the classified
repository material and unsupported target configuration.

## Verified unchanged application inputs

Before creating the public root commit, the staged public tree was compared with
the private submission commit by Git object ID:

| Input subtree | Git tree ID | Result |
|---|---|---|
| `AppScope` | `ded587abb9d21350377f6e4e91042db46522e462` | Exact match |
| `entry/src/main/ets` | `14ee29a1c225e724ac0fe2b502db2dd977af3382` | Exact match |
| `entry/src/main/resources` | `ee37b3f9b3d74a17c049ab369ece711e9b2b757b` | Exact match |
| `harmotty_ssh/src` | `1586dea40cf8eec87b0016e1bc8b4e39a67eae37` | Exact match |

A fresh public-baseline ARM64 native build also produced SHA-256
`9EE5170D607461D324FD7ADCE76D98EC72DF23D9CBEAF394610EB8B195A9E75C`,
exactly matching the native library recorded for the submitted 1.0.0 build.
