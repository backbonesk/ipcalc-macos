import Foundation

public enum IPCalcQuery: Equatable, Sendable {
    /// A host or network, optionally with a prefix to split into subnets or widen into a supernet.
    case network(IPv4Network, moveTo: Int?)
    /// An inclusive address range to deaggregate into CIDR networks.
    case range(IPv4Address, IPv4Address)
    case network6(IPv6Network, moveTo: Int?)
    case range6(IPv6Address, IPv6Address)

    /// Prefixes used when only an address is given: /24 like ipcalc, /64 (a LAN) for IPv6.
    public static let defaultPrefix = 24
    public static let defaultPrefix6 = 64

    /// Accepted forms:
    ///
    ///     172.16.0.0/12              172.16.0.0 12
    ///     172.16.0.0/255.240.0.0     172.16.0.0 255.240.0.0
    ///     172.16.0.0/0.15.255.255    (wildcard masks are inverted automatically)
    ///     172.16.0.0/12 /14          172.16.0.0/12 -> 14   (sub/supernet)
    ///     10.0.0.5 - 10.0.0.70       (range, deaggregated into networks)
    ///     2001:db8::/48 /64          2001:db8::1 - 2001:db8::ff
    public static func parse(_ input: String) throws(IPCalcError) -> IPCalcQuery {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw .empty }

        for arrow in ["->", "=>", ">"] {
            text = text.replacingOccurrences(of: arrow, with: " ")
        }

        if text.contains("-") {
            let ends = text.split(separator: "-", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard ends.count == 2 else { throw .invalidRange(input) }
            switch (ends[0].contains(":"), ends[1].contains(":")) {
            case (false, false):
                guard let start = IPv4Address(ends[0]) else { throw .invalidAddress(ends[0]) }
                guard let end = IPv4Address(ends[1]) else { throw .invalidAddress(ends[1]) }
                return .range(min(start, end), max(start, end))
            case (true, true):
                guard let start = IPv6Address(ends[0]) else { throw .invalidAddress(ends[0]) }
                guard let end = IPv6Address(ends[1]) else { throw .invalidAddress(ends[1]) }
                return .range6(min(start, end), max(start, end))
            default:
                throw .invalidRange(input)
            }
        }

        var tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var addressText = tokens.removeFirst()
        let isIPv6 = addressText.contains(":")
        let maxPrefix = isIPv6 ? 128 : 32
        var prefix: Int?
        if let slash = addressText.firstIndex(of: "/") {
            prefix = try parsePrefix(String(addressText[addressText.index(after: slash)...]), max: maxPrefix)
            addressText = String(addressText[..<slash])
        }
        if prefix == nil, !tokens.isEmpty {
            prefix = try parsePrefix(tokens.removeFirst(), max: maxPrefix)
        }
        var moveTo: Int?
        if !tokens.isEmpty {
            moveTo = try parsePrefix(tokens.removeFirst(), max: maxPrefix)
        }
        guard tokens.isEmpty else { throw .unexpected(tokens.joined(separator: " ")) }

        if isIPv6 {
            guard let address = IPv6Address(addressText) else { throw .invalidAddress(addressText) }
            return .network6(IPv6Network(address: address, prefix: prefix ?? defaultPrefix6), moveTo: moveTo)
        }
        guard let address = IPv4Address(addressText) else { throw .invalidAddress(addressText) }
        return .network(IPv4Network(address: address, prefix: prefix ?? defaultPrefix), moveTo: moveTo)
    }

    /// Parses `12`, `/12` and, for IPv4, `255.240.0.0` or the wildcard form `0.15.255.255`.
    static func parsePrefix(_ token: String, max: Int) throws(IPCalcError) -> Int {
        let token = token.hasPrefix("/") ? String(token.dropFirst()) : token
        if let prefix = Int(token) {
            guard (0...max).contains(prefix) else { throw .invalidNetmask(token) }
            return prefix
        }
        guard max == 32, token.contains("."), let mask = IPv4Address(token) else { throw .invalidNetmask(token) }
        if let prefix = IPv4Network.prefix(forNetmask: mask.value) ?? IPv4Network.prefix(forNetmask: ~mask.value) {
            return prefix
        }
        throw .invalidNetmask(token)
    }
}

public enum IPCalcError: Error, Equatable, LocalizedError {
    case empty
    case invalidAddress(String)
    case invalidNetmask(String)
    case invalidRange(String)
    case unexpected(String)

    public var errorDescription: String? {
        switch self {
        case .empty: "Enter an address, e.g. 172.16.0.0/12 or 2001:db8::/48"
        case .invalidAddress(let text): "Invalid address: \(text)"
        case .invalidNetmask(let text): "Invalid netmask: \(text)"
        case .invalidRange(let text): "Invalid range: \(text)"
        case .unexpected(let text): "Unexpected input: \(text)"
        }
    }
}
