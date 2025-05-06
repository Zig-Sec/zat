# Zig Audit Tool - ZAT

**ZAT is part of my master thesis with the title: Cyber risk reduction through transparency for Zig packages**

Required compiler version: 0.14.0

After compiling run _zat -h_.

> This is alpha software. Expect bugs and breaking changes!

## Features

### Auditing Zig Packages

Use ZAT to to audit a Zig package.

```bash
$ zat --audit
Scanning build.zig.zon for vulnerabilities (8 package dependencies)

Package:      zbor
Version:      0.17.0
Title:        This is the first advisory published to zig-sec/advisory-db.
Date:         2025-03-16
ID:           ZIGSEC-2025-0001
URL:          https://zigsec.org/advisories/ZIGSEC-2025-0001/
Solution:     Don't worry! But you should upgrade anyway as a new zbor release is available.
Dependency tree:
keylib 0.6.1
  └──zbor 0.17.0

error: 1 vulnerability found!
```

The example above is an audit of the [PassKeeZ](https://github.com/Zig-Sec/PassKeeZ) application.

The `--audit` command tries to find published vulnerabilities for every (transitive) dependency of a package.
Currently, ZAT only sources the [Zig-Sec Advisory Database](https://zigsec.org/). 

### Dependency Graphs

Use ZAT to create dependency graphs.

```mermaid
%%{init: {"flowchart": {"htmlLabels": false}} }%%
graph TD;
c25aabcf9323b699["`<a href='https://github.com/Zig-Sec/keylib/archive/refs/tags/0.6.1.tar.gz'>keylib</a>
v0.6.1`"]
    c25aabcf9323b699 --> 32fbe7d2a082bf92
    c25aabcf9323b699 --> 274758e14a01bde3
    c25aabcf9323b699 --> d17f50a6219ee8a0
8ba83cc904d99578["`<a href='https://github.com/Zig-Sec/kdbx/archive/refs/tags/0.1.2.tar.gz'>kdbx</a>
v0.1.2`"]
    8ba83cc904d99578 --> 65f99e6f07a316a0
    8ba83cc904d99578 --> d17f50a6219ee8a0
    8ba83cc904d99578 --> 7a7a16eec9417569
32fbe7d2a082bf92["`<a href='https://github.com/r4gus/zbor/archive/refs/tags/0.17.2.tar.gz'>zbor</a>
v0.17.0`"]
7a7a16eec9417569["`<a href='https://github.com/edqx/dishwasher/archive/refs/tags/1.0.7.tar.gz'>dishwasher</a>
v2.0.0`"]
274758e14a01bde3["`<a href='https://github.com/r4gus/hidapi/archive/refs/tags/0.15.0.tar.gz'>hidapi</a>
v0.15.0`"]
dd1692d15d21a6f6["`<a href='git@github.com:Zig-Sec/PassKeeZ.git'>passkeez</a>
v0.5.2`"]
    dd1692d15d21a6f6 --> c25aabcf9323b699
    dd1692d15d21a6f6 --> 8ba83cc904d99578
    dd1692d15d21a6f6 --> d17f50a6219ee8a0
    dd1692d15d21a6f6 --> e06b5c5f6286b39a
65f99e6f07a316a0["`<a href='https://github.com/Hejsil/zig-clap/archive/refs/tags/0.10.0.tar.gz'>clap</a>
v0.10.0`"]
e06b5c5f6286b39a["`<a href='https://github.com/r4gus/ccdb/archive/refs/tags/0.3.1.tar.gz'>ccdb</a>
v0.3.2`"]
    e06b5c5f6286b39a --> 32fbe7d2a082bf92
    e06b5c5f6286b39a --> d17f50a6219ee8a0
    e06b5c5f6286b39a --> 65f99e6f07a316a0
d17f50a6219ee8a0["`<a href='https://github.com/r4gus/uuid-zig/archive/refs/tags/0.3.1.tar.gz'>uuid</a>
v0.3.0`"]
```

The graph depicted above has been generated using `zat --graph --mermaid --path ~/passkeez-graph.txt`. Mermaid graphs can be added to a Github readme by putting it into a code block of the type `mermaid`.

### Software Bill of Materials (SBOMs)

User ZAT to create a SBOMs for your Zig packages.

Just run:
```bash
$ zat --sbom
```

To write the SBOM directly to a file use the `--path <PATH>` option.

#### Open Source SBOM tools

The following tools can be used to play with generated SBOMs:
- [sbom.sh](https://sbom.sh)

### Sources of Information

Information about a package are gathered from the following sources:

- `build.zig.zon`: Package properties, including the version and package dependencies.
- `.git/config`: The url of the audited package.

## Thanks

Special thanks to the following authors:
- Hejsil for [clap](https://github.com/Hejsil/zig-clap)
- nektro for [zig-time](https://github.com/nektro/zig-time)    
- ziglibs for [ini](https://github.com/ziglibs/ini)
