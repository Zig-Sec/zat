//! External references provide a way to document systems, sites, and information that may be relevant but are not included with the BOM. They may also establish specific relationships within or external to the BOM.

const std = @import("std");
const Allocator = std.mem.Allocator;

url: []const u8,
type: Type,

pub const Type = enum {
    /// Version Control System
    vcs,
    @"issue-tracker",
    website,
    advisories,
    bom,
    @"mailing-list",
    social,
    chat,
    documentation,
    support,
    @"source-distribution",
    distribution,
    @"distribution-intake",
    license,
    @"build-meta",
    @"build-system",
    @"release-notes",
    @"security-contact",
    @"model-card",
    log,
    configuration,
    evidence,
    formulation,
    attestation,
    @"thread-model",
    @"adversary-model",
    @"risk-assessment",
    @"vulnerability-assertion",
    @"exploitability-statement",
    @"pentest-report",
    @"static-analysis-report",
    @"dynamic-analysis-report",
    @"runtime-analysis-report",
    @"component-analysis-report",
    @"maturity-report",
    @"certification-report",
    @"quality-metrics",
    poam,
    @"electronic-signature",
    @"digital-signature",
    @"rfc-9116",
    other,
};

pub fn deinit(self: *const @This(), allocator: Allocator) void {
    allocator.free(self.url);
}
