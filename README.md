# Zig Audit Tool - ZAT

**ZAT is part of my master thesis with the title: Cyber risk reduction through transparency for Zig packages**

Required compiler version: 0.14.0

After compiling run _zat -h_.

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
0x65f99e6f07a316a0["`<a href='https://github.com/Hejsil/zig-clap/archive/refs/tags/0.10.0.tar.gz'>clap</a>
clap-0.10.0-oBajB434AQBDh-Ei3YtoKIRxZacVPF1iSwp3IX_ZB8f0
v0.10.0`"]
0xc25aabcf9323b699["`<a href='https://github.com/Zig-Sec/keylib/archive/refs/tags/0.6.1.tar.gz'>keylib</a>
keylib-0.6.1-mbYjk9-WCQBOqB9oq2ZqWQFeWI2HwuBEuPgL-wkJDHTg
v0.6.1`"]
    0xc25aabcf9323b699 --> 0x32fbe7d2a082bf92
    0xc25aabcf9323b699 --> 0x274758e14a01bde3
    0xc25aabcf9323b699 --> 0xd17f50a6219ee8a0
0x0["`<a href=''>passkeez</a>

v0.5.1`"]
    0x0 --> 0xc25aabcf9323b699
    0x0 --> 0x8ba83cc904d99578
    0x0 --> 0xd17f50a6219ee8a0
    0x0 --> 0xe06b5c5f6286b39a
0x8ba83cc904d99578["`<a href='https://github.com/Zig-Sec/kdbx/archive/refs/tags/0.1.1.tar.gz'>kdbx</a>
kdbx-0.1.1-eJXZBIysCgCWP6t03J0luSrYdP742K2W_WEv49Vy3xku
v0.1.1`"]
    0x8ba83cc904d99578 --> 0x65f99e6f07a316a0
    0x8ba83cc904d99578 --> 0xd17f50a6219ee8a0
    0x8ba83cc904d99578 --> 0x7a7a16eec9417569
0xd17f50a6219ee8a0["`<a href='https://github.com/r4gus/uuid-zig/archive/refs/tags/0.3.1.tar.gz'>uuid</a>
uuid-0.3.0-oOieIYF1AAA_BtE7FvVqqTn5uEYTvvz7ycuVnalCOf8C
v0.3.0`"]
0x32fbe7d2a082bf92["`<a href='https://github.com/r4gus/zbor/archive/refs/tags/0.17.2.tar.gz'>zbor</a>
zbor-0.17.0-kr-CoHIkAwCy2WhoS6MgwSvyQsLWzzNy6a7UTHqMPMmO
v0.17.0`"]
0x7a7a16eec9417569["`<a href='https://github.com/edqx/dishwasher/archive/refs/tags/1.0.7.tar.gz'>dishwasher</a>
dishwasher-2.0.0-aXVByeyCAQBuf9acPDoFACdxIfpbzkRdvcz_QNM6XZDU
v2.0.0`"]
0xe06b5c5f6286b39a["`<a href='https://github.com/r4gus/ccdb/archive/refs/tags/0.3.1.tar.gz'>ccdb</a>
ccdb-0.3.2-mrOGYn4KDgC0cJl4CKpKaJB95wwIlHegHLV7NSbMYXu0
v0.3.2`"]
    0xe06b5c5f6286b39a --> 0x32fbe7d2a082bf92
    0xe06b5c5f6286b39a --> 0xd17f50a6219ee8a0
    0xe06b5c5f6286b39a --> 0x65f99e6f07a316a0
0x274758e14a01bde3["`<a href='https://github.com/r4gus/hidapi/archive/refs/tags/0.15.0.tar.gz'>hidapi</a>
hidapi-0.15.0-470BShXnGgD8ruGfG_aXZMgI6nKSBi6_TsVfWF7ymGZ8
v0.15.0`"]
```

The graph depicted above has been generated using `zat --graph --mermaid --path ~/passkeez-graph.txt`. Mermaid graphs can be added to a Github readme by putting it into a code block of the type `mermaid`.
