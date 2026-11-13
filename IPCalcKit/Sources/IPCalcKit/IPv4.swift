/// A single IPv4 address stored as a 32-bit integer.
public struct IPv4Address: Hashable, Comparable, Sendable, CustomStringConvertible {
    public var value: UInt32

    public init(_ value: UInt32) {
        self.value = value
    }

    /// Parses a dotted-quad address. Missing trailing octets are treated as zero
    /// ("10" -> 10.0.0.0, "192.168" -> 192.168.0.0), matching ipcalc.
    public init?<S: StringProtocol>(_ string: S) {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return nil }
        var value: UInt32 = 0
        for index in 0..<4 {
            var octet: UInt32 = 0
            if index < parts.count {
                let part = parts[index]
                guard (1...3).contains(part.count),
                      part.utf8.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }),
                      let parsed = UInt32(part), parsed <= 255
                else { return nil }
                octet = parsed
            }
            value = value << 8 | octet
        }
        self.value = value
    }

    public var description: String {
        "\(value >> 24).\(value >> 16 & 0xFF).\(value >> 8 & 0xFF).\(value & 0xFF)"
    }

    public static func < (lhs: IPv4Address, rhs: IPv4Address) -> Bool {
        lhs.value < rhs.value
    }

    /// Binary representation with dots between octets and a space at the prefix boundary,
    /// e.g. `10101100.0001 0000.00000000.00000000` for prefix 12.
    public func binary(splitAt prefix: Int) -> String {
        var result = ""
        for bit in 0..<32 {
            if bit > 0 && bit % 8 == 0 { result += "." }
            if bit == prefix && prefix != 0 { result += " " }
            result += (value >> (31 - bit)) & 1 == 1 ? "1" : "0"
        }
        return result
    }
}

public enum IPv4Class: String, Sendable {
    case a = "Class A"
    case b = "Class B"
    case c = "Class C"
    case d = "Class D, Multicast"
    case e = "Class E, Reserved"

    public init(_ address: IPv4Address) {
        switch address.value >> 28 {
        case 0b0000...0b0111: self = .a
        case 0b1000...0b1011: self = .b
        case 0b1100...0b1101: self = .c
        case 0b1110: self = .d
        default: self = .e
        }
    }

    /// Number of leading bits that identify the class (highlighted in the binary output).
    public var leadingBits: Int {
        switch self {
        case .a: 1
        case .b: 2
        case .c: 3
        case .d, .e: 4
        }
    }
}

public struct IPv4Network: Hashable, Sendable {
    /// The address as entered, which may be a host inside the network.
    public let address: IPv4Address
    public let prefix: Int

    public init(address: IPv4Address, prefix: Int) {
        precondition((0...32).contains(prefix), "prefix must be 0...32")
        self.address = address
        self.prefix = prefix
    }

    public static func netmask(prefix: Int) -> UInt32 {
        // Smart shift: shifting by 32 yields 0, which is the /0 mask.
        UInt32.max << (32 - prefix)
    }

    /// Returns the prefix length for a contiguous netmask, or nil if the mask has holes.
    public static func prefix(forNetmask mask: UInt32) -> Int? {
        let prefix = mask.nonzeroBitCount
        return netmask(prefix: prefix) == mask ? prefix : nil
    }

    public var netmask: IPv4Address { IPv4Address(Self.netmask(prefix: prefix)) }
    public var wildcard: IPv4Address { IPv4Address(~Self.netmask(prefix: prefix)) }
    public var network: IPv4Address { IPv4Address(address.value & netmask.value) }
    public var broadcast: IPv4Address { IPv4Address(network.value | wildcard.value) }

    /// /31 (RFC 3021 point-to-point) and /32 (host route) networks have no broadcast address.
    public var hasBroadcast: Bool { prefix < 31 }

    public var hostMin: IPv4Address { hasBroadcast ? IPv4Address(network.value + 1) : network }
    public var hostMax: IPv4Address { hasBroadcast ? IPv4Address(broadcast.value - 1) : broadcast }

    public var addressCount: UInt64 { 1 << UInt64(32 - prefix) }
    public var hostCount: UInt64 { hasBroadcast ? addressCount - 2 : addressCount }

    public var ipClass: IPv4Class { IPv4Class(network) }
    public var cidr: String { "\(network)/\(prefix)" }

    public func contains(_ other: IPv4Network) -> Bool {
        other.prefix >= prefix && other.network.value & netmask.value == network.value
    }

    /// The most specific IANA special-purpose block that contains this network, if any.
    public var specialRange: SpecialRange? {
        SpecialRange.all
            .filter { $0.network.contains(self) }
            .max { $0.network.prefix < $1.network.prefix }
    }

    /// Human-readable address type, e.g. "Private (RFC 1918)" or "Public".
    public var type: String {
        if let specialRange { return specialRange.name }
        return SpecialRange.all.contains { contains($0.network) } ? "Contains special-purpose ranges" : "Public"
    }

    public func subnetCount(prefix newPrefix: Int) -> UInt64 {
        1 << UInt64(newPrefix - prefix)
    }

    public func subnet(_ index: UInt64, prefix newPrefix: Int) -> IPv4Network {
        let size = UInt64(1) << UInt64(32 - newPrefix)
        return IPv4Network(address: IPv4Address(UInt32(UInt64(network.value) + index * size)), prefix: newPrefix)
    }

    /// Splits an inclusive address range into the minimal list of CIDR networks.
    public static func deaggregate(from start: IPv4Address, to end: IPv4Address) -> [IPv4Network] {
        var result: [IPv4Network] = []
        var current = UInt64(start.value)
        let last = UInt64(end.value)
        while current <= last {
            var bits = UInt32(current).trailingZeroBitCount
            while bits > 0 && current + (UInt64(1) << UInt64(bits)) - 1 > last {
                bits -= 1
            }
            result.append(IPv4Network(address: IPv4Address(UInt32(current)), prefix: 32 - bits))
            current += UInt64(1) << UInt64(bits)
        }
        return result
    }
}

public struct SpecialRange: Sendable {
    public let network: IPv4Network
    public let name: String

    init(_ address: String, _ prefix: Int, _ name: String) {
        network = IPv4Network(address: IPv4Address(address)!, prefix: prefix)
        self.name = name
    }

    /// IANA IPv4 Special-Purpose Address Registry (RFC 6890 and successors).
    public static let all: [SpecialRange] = [
        SpecialRange("0.0.0.0", 8, "This network (RFC 791)"),
        SpecialRange("10.0.0.0", 8, "Private (RFC 1918)"),
        SpecialRange("100.64.0.0", 10, "Shared address space, CGNAT (RFC 6598)"),
        SpecialRange("127.0.0.0", 8, "Loopback (RFC 1122)"),
        SpecialRange("169.254.0.0", 16, "Link-local (RFC 3927)"),
        SpecialRange("172.16.0.0", 12, "Private (RFC 1918)"),
        SpecialRange("192.0.0.0", 24, "IETF protocol assignments (RFC 6890)"),
        SpecialRange("192.0.2.0", 24, "Documentation, TEST-NET-1 (RFC 5737)"),
        SpecialRange("192.88.99.0", 24, "6to4 relay anycast, deprecated (RFC 7526)"),
        SpecialRange("192.168.0.0", 16, "Private (RFC 1918)"),
        SpecialRange("198.18.0.0", 15, "Benchmarking (RFC 2544)"),
        SpecialRange("198.51.100.0", 24, "Documentation, TEST-NET-2 (RFC 5737)"),
        SpecialRange("203.0.113.0", 24, "Documentation, TEST-NET-3 (RFC 5737)"),
        SpecialRange("224.0.0.0", 4, "Multicast (RFC 5771)"),
        SpecialRange("240.0.0.0", 4, "Reserved (RFC 1112)"),
        SpecialRange("255.255.255.255", 32, "Limited broadcast (RFC 919)"),
    ]
}
