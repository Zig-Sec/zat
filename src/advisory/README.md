Advisories are published via Github (TODO: maybe one can just define a public repository to allow different sources; maybe even multiple ones). The structure of the advisory-db is as follows:

```
\-
 |- packages/
    |- fingerprint-for-package-abc
       |- ZIGSEC-YYYY-0001
       |- ZIGSEC-YYYY-0002
       |- ...
       |- ZIGSEC-YYYY-NNNN
    |- ...
    |- fingerprint-for-package-xyz
```

Advisories for a specific package are published by creating a pull request to [TBD](). The pull request must contain a [Zig Object Notation (ZON)]() file describing the vulnerability (see `EXAMPLE_ADVISORY.zon` for an example). Each advisory is reviewed for soundness and then assigned a unique ID in the format `ZIGSEC-YYYY-NNNN` before being published. Advisories for the same package are gathered within a sub-folder identified by the fingerprint of the package.

Advisories are consumed by tools like the [Zig Release Tool (ZRT)](), e.g. when using `zrt audit`.
