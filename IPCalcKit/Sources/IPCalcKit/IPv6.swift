/// A single IPv6 address stored as a 128-bit integer.
public struct IPv6Address: Hashable, Comparable, Sendable, CustomStringConvertible {
    public var value: UInt128

    public init(_ value: UInt128) {
        self.value = value
    }

    /// Parses any RFC 4291 text form: full, `::`-compressed and with an embedded IPv4 address
    /// (`::ffff:192.0.2.1`). A zone index (`fe80::1%en0`) is accepted and ignored.
    public init?<S: StringProtocol>(_ string: S) {
        var text = Substring(string)
        if let percent = text.firstIndex(of: "%") {
            text = text[..<percent]
        }
        let halves = text.split(separator: "::", maxSplits: 2, omittingEmptySubsequences: false)
        guard (1...2).contains(halves.count) else { return nil }

        let compressed = halves.count == 2
        guard let head = Self.groups(halves[0], allowsIPv4: !compressed),
              let tail = compressed ? Self.groups(halves[1], allowsIPv4: true) : []
        else { return nil }
        let missing = 8 - head.count - tail.count
        guard compressed ? missing >= 1 : missing == 0 else { return nil }

        value = (head + Array(repeating: 0, count: missing) + tail).reduce(0) { $0 << 16 | UInt128($1) }
    }

    /// Parses colon-separated hex groups; the last one may be a dotted IPv4 address (two groups).
    private static func groups(_ part: Substring, allowsIPv4: Bool) -> [UInt16]? {
        guard !part.isEmpty else { return [] }
        let items = part.split(separator: ":", omittingEmptySubsequences: false)
        var result: [UInt16] = []
        for (index, item) in items.enumerated() {
            if allowsIPv4, index == items.count - 1, item.contains(".") {
                guard item.split(separator: ".").count == 4, let v4 = IPv4Address(item) else { return nil }
                result += [UInt16(v4.value >> 16), UInt16(v4.value & 0xFFFF)]
            } else {
                guard (1...4).contains(item.count), item.allSatisfy(\.isHexDigit), let group = UInt16(item, radix: 16)
                else { return nil }
                result.append(group)
            }
        }
        return result
    }

    public var groups: [UInt16] {
        (0..<8).map { UInt16(truncatingIfNeeded: value >> (112 - 16 * $0)) }
    }

    /// Canonical RFC 5952 form: lowercase, no leading zeros, longest zero run (≥ 2 groups) as `::`.
    public var description: String {
        if value >> 32 == 0xFFFF {
            return "::ffff:\(IPv4Address(UInt32(truncatingIfNeeded: value)))"
        }
        let groups = groups
        var best = (start: 0, length: 0)
        var index = 0
        while index < 8 {
            var end = index
            while end < 8 && groups[end] == 0 { end += 1 }
            if end - index > best.length { best = (index, end - index) }
            index = max(end, index + 1)
        }
        let hex = groups.map { String($0, radix: 16) }
        guard best.length >= 2 else { return hex.joined(separator: ":") }
        return hex[..<best.start].joined(separator: ":") + "::" + hex[(best.start + best.length)...].joined(separator: ":")
    }

    /// All eight groups with four digits each.
    public var expanded: String {
        groups.map { group in
            let hex = String(group, radix: 16)
            return String(repeating: "0", count: 4 - hex.count) + hex
        }.joined(separator: ":")
    }

    /// The `ip6.arpa` name covering the first `nibbles` hex digits.
    public func reverseZone(nibbles: Int) -> String {
        let digits = Array(groups.map { group in
            let hex = String(group, radix: 16)
            return String(repeating: "0", count: 4 - hex.count) + hex
        }.joined())
        return (digits[..<nibbles].reversed().map(String.init) + ["ip6", "arpa"]).joined(separator: ".")
    }

    public static func < (lhs: IPv6Address, rhs: IPv6Address) -> Bool {
        lhs.value < rhs.value
    }
}

public struct IPv6Network: Hashable, Sendable {
    /// The address as entered, which may be a host inside the network.
    public let address: IPv6Address
    public let prefix: Int

    public init(address: IPv6Address, prefix: Int) {
        precondition((0...128).contains(prefix), "prefix must be 0...128")
        self.address = address
        self.prefix = prefix
    }

    public static func netmask(prefix: Int) -> UInt128 {
        // Smart shift: shifting by 128 yields 0, which is the /0 mask.
        UInt128.max << (128 - prefix)
    }

    public var netmask: IPv6Address { IPv6Address(Self.netmask(prefix: prefix)) }
    public var network: IPv6Address { IPv6Address(address.value & netmask.value) }
    /// IPv6 has no broadcast address, so the whole range is usable.
    public var last: IPv6Address { IPv6Address(network.value | ~netmask.value) }
    public var cidr: String { "\(network)/\(prefix)" }

    /// Number of addresses as a decimal string (2^128 does not fit in UInt128).
    public var addressCount: String { Self.powerOfTwo(128 - prefix) }

    public var reverseZone: String { network.reverseZone(nibbles: prefix / 4) }

    public func contains(_ other: IPv6Network) -> Bool {
        other.prefix >= prefix && other.network.value & netmask.value == network.value
    }

    public var specialRange: SpecialRange6? {
        SpecialRange6.all
            .filter { $0.network.contains(self) }
            .max { $0.network.prefix < $1.network.prefix }
    }

    /// Human-readable address type, e.g. "Global unicast (RFC 4291)".
    public var type: String {
        if let specialRange { return specialRange.name }
        return SpecialRange6.all.contains { contains($0.network) } ? "Contains special-purpose ranges" : "Reserved by IETF"
    }

    public func subnet(_ index: UInt128, prefix newPrefix: Int) -> IPv6Network {
        IPv6Network(address: IPv6Address(network.value + index << (128 - newPrefix)), prefix: newPrefix)
    }

    static func powerOfTwo(_ bits: Int) -> String {
        bits < 128 ? String(UInt128(1) << bits) : "340282366920938463463374607431768211456"
    }

    /// Splits an inclusive address range into the minimal list of CIDR networks.
    public static func deaggregate(from start: IPv6Address, to end: IPv6Address) -> [IPv6Network] {
        var result: [IPv6Network] = []
        var current = start.value
        while true {
            var bits = current.trailingZeroBitCount
            while bits > 0 && (bits == 128 ? UInt128.max : (current | (UInt128(1) << bits - 1))) > end.value {
                bits -= 1
            }
            result.append(IPv6Network(address: IPv6Address(current), prefix: 128 - bits))
            let blockEnd = bits == 128 ? UInt128.max : current | (UInt128(1) << bits - 1)
            if blockEnd >= end.value { return result }
            current = blockEnd + 1
        }
    }
}

public struct SpecialRange6: Sendable {
    public let network: IPv6Network
    public let name: String

    init(_ address: String, _ prefix: Int, _ name: String) {
        network = IPv6Network(address: IPv6Address(address)!, prefix: prefix)
        self.name = name
    }

    /// IANA IPv6 Special-Purpose Address Registry plus the main allocation blocks.
    public static let all: [SpecialRange6] = [
        SpecialRange6("::", 128, "Unspecified (RFC 4291)"),
        SpecialRange6("::1", 128, "Loopback (RFC 4291)"),
        SpecialRange6("::ffff:0:0", 96, "IPv4-mapped (RFC 4291)"),
        SpecialRange6("64:ff9b::", 96, "NAT64 (RFC 6052)"),
        SpecialRange6("64:ff9b:1::", 48, "Local-use NAT64 (RFC 8215)"),
        SpecialRange6("100::", 64, "Discard-only (RFC 6666)"),
        SpecialRange6("2000::", 3, "Global unicast (RFC 4291)"),
        SpecialRange6("2001::", 23, "IETF protocol assignments (RFC 2928)"),
        SpecialRange6("2001::", 32, "Teredo (RFC 4380)"),
        SpecialRange6("2001:db8::", 32, "Documentation (RFC 3849)"),
        SpecialRange6("2002::", 16, "6to4 (RFC 3056)"),
        SpecialRange6("3fff::", 20, "Documentation (RFC 9637)"),
        SpecialRange6("fc00::", 7, "Unique local (RFC 4193)"),
        SpecialRange6("fe80::", 10, "Link-local (RFC 4291)"),
        SpecialRange6("ff00::", 8, "Multicast (RFC 4291)"),
    ]
}
