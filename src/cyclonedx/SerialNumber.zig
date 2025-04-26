//! Every BOM generated SHOULD have a unique serial number, even if the contents of the BOM have not changed over time. If specified, the serial number must conform to [RFC 4122](https://www.ietf.org/rfc/rfc4122.html). Use of serial numbers is recommended.
//!
//! [CycloneDX v1.6 serialNumber](https://cyclonedx.org/docs/1.6/json/#serialNumber)

const uuid = @import("uuid");
const std = @import("std");

const prefix = "urn:uuid:";

pub const SerialNumber = [45]u8;

pub fn new() SerialNumber {
    var t: SerialNumber = undefined;

    const id = uuid.v4.new();
    const urn = uuid.urn.serialize(id);
    @memcpy(t[0..prefix.len], prefix);
    @memcpy(t[prefix.len..], urn[0..]);

    return t;
}

pub fn get(self: *const @This()) []const u8 {
    return self.serial_number[0..];
}
