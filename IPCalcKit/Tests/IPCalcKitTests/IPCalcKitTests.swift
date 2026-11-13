import Testing
@testable import IPCalcKit

@Suite struct ParsingTests {
    @Test(arguments: [
        "172.16.0.0/12", "172.16.0.0 12", "172.16.0.0/255.240.0.0", "172.16.0.0 255.240.0.0",
        "172.16.0.0/0.15.255.255", "  172.16.0.0/12\n", "172.16/12",
    ])
    func networkForms(input: String) throws {
        #expect(try IPCalcQuery.parse(input) == .network(net("172.16.0.0", 12), moveTo: nil))
    }

    @Test(arguments: ["172.16.0.0/12 /14", "172.16.0.0/12 14", "172.16.0.0 12 14", "172.16.0.0/12 -> 14", "172.16.0.0/12 > /14"])
    func moveTo(input: String) throws {
        #expect(try IPCalcQuery.parse(input) == .network(net("172.16.0.0", 12), moveTo: 14))
    }

    @Test func defaultPrefix() throws {
        #expect(try IPCalcQuery.parse("10.1.2.3") == .network(net("10.1.2.3", 24), moveTo: nil))
    }

    @Test func range() throws {
        #expect(try IPCalcQuery.parse("10.0.0.70 - 10.0.0.5") == .range(addr("10.0.0.5"), addr("10.0.0.70")))
        #expect(try IPCalcQuery.parse("10.0.0.5-10.0.0.70") == .range(addr("10.0.0.5"), addr("10.0.0.70")))
    }

    @Test func errors() {
        #expect(throws: IPCalcError.empty) { try IPCalcQuery.parse("  ") }
        #expect(throws: IPCalcError.invalidRange("10.0.0.1 - ::1")) { try IPCalcQuery.parse("10.0.0.1 - ::1") }
        #expect(throws: IPCalcError.invalidNetmask("129")) { try IPCalcQuery.parse("::/129") }
        #expect(throws: IPCalcError.invalidNetmask("255.255.0.0")) { try IPCalcQuery.parse("2001:db8:: 255.255.0.0") }
        #expect(throws: IPCalcError.invalidAddress("256.0.0.1")) { try IPCalcQuery.parse("256.0.0.1/8") }
        #expect(throws: IPCalcError.invalidAddress("1.2.3.4.5")) { try IPCalcQuery.parse("1.2.3.4.5") }
        #expect(throws: IPCalcError.invalidNetmask("33")) { try IPCalcQuery.parse("10.0.0.0/33") }
        #expect(throws: IPCalcError.invalidNetmask("255.0.255.0")) { try IPCalcQuery.parse("10.0.0.0 255.0.255.0") }
        #expect(throws: IPCalcError.unexpected("9")) { try IPCalcQuery.parse("10.0.0.0 8 16 9") }
        #expect(throws: IPCalcError.invalidRange("1.1.1.1 - 2.2.2.2 - 3.3.3.3")) { try IPCalcQuery.parse("1.1.1.1 - 2.2.2.2 - 3.3.3.3") }
    }
}

@Suite struct NetworkTests {
    @Test func screenshotExample() {
        let n = net("172.16.0.0", 12)
        #expect(n.netmask.description == "255.240.0.0")
        #expect(n.wildcard.description == "0.15.255.255")
        #expect(n.broadcast.description == "172.31.255.255")
        #expect(n.hostMin.description == "172.16.0.1")
        #expect(n.hostMax.description == "172.31.255.254")
        #expect(n.hostCount == 1_048_574)
        #expect(n.ipClass == .b)
        #expect(n.type == "Private (RFC 1918)")
        #expect(n.address.binary(splitAt: 12) == "10101100.0001 0000.00000000.00000000")
        #expect(n.netmask.binary(splitAt: 12) == "11111111.1111 0000.00000000.00000000")
    }

    @Test func hostInsideNetwork() {
        let n = net("192.168.1.77", 26)
        #expect(n.cidr == "192.168.1.64/26")
        #expect(n.broadcast.description == "192.168.1.127")
        #expect(n.hostCount == 62)
    }

    @Test func edgePrefixes() {
        let zero = net("1.2.3.4", 0)
        #expect(zero.cidr == "0.0.0.0/0")
        #expect(zero.broadcast.description == "255.255.255.255")
        #expect(zero.hostCount == 4_294_967_294)
        #expect(zero.address.binary(splitAt: 0) == "00000001.00000010.00000011.00000100")

        let p2p = net("10.0.0.1", 31)
        #expect(!p2p.hasBroadcast)
        #expect(p2p.hostMin.description == "10.0.0.0")
        #expect(p2p.hostMax.description == "10.0.0.1")
        #expect(p2p.hostCount == 2)

        let host = net("8.8.8.8", 32)
        #expect(host.hostMin == host.hostMax)
        #expect(host.hostCount == 1)
        #expect(host.address.binary(splitAt: 32) == "00001000.00001000.00001000.00001000")
    }

    @Test func classes() {
        #expect(IPv4Class(addr("10.0.0.0")) == .a)
        #expect(IPv4Class(addr("128.0.0.0")) == .b)
        #expect(IPv4Class(addr("192.0.0.0")) == .c)
        #expect(IPv4Class(addr("224.0.0.1")) == .d)
        #expect(IPv4Class(addr("240.0.0.1")) == .e)
    }

    @Test func specialRanges() {
        #expect(net("100.100.0.0", 16).specialRange?.name == "Shared address space, CGNAT (RFC 6598)")
        #expect(net("192.0.2.10", 32).specialRange?.name == "Documentation, TEST-NET-1 (RFC 5737)")
        #expect(net("255.255.255.255", 32).specialRange?.name == "Limited broadcast (RFC 919)")
        #expect(net("8.8.8.8", 32).type == "Public")
        #expect(net("0.0.0.0", 0).type == "Contains special-purpose ranges")
        #expect(net("172.0.0.0", 8).specialRange == nil)
        #expect(net("8.8.8.8", 32).specialRange == nil)
    }

    @Test func deaggregate() {
        let cidrs = IPv4Network.deaggregate(from: addr("10.0.0.5"), to: addr("10.0.0.70")).map(\.cidr)
        #expect(cidrs == ["10.0.0.5/32", "10.0.0.6/31", "10.0.0.8/29", "10.0.0.16/28", "10.0.0.32/27",
                          "10.0.0.64/30", "10.0.0.68/31", "10.0.0.70/32"])
        #expect(IPv4Network.deaggregate(from: addr("0.0.0.0"), to: addr("255.255.255.255")).map(\.cidr) == ["0.0.0.0/0"])
        #expect(IPv4Network.deaggregate(from: addr("255.255.255.255"), to: addr("255.255.255.255")).map(\.cidr) == ["255.255.255.255/32"])
    }
}

@Suite struct ReportTests {
    @Test func plainTextMatchesIpcalc() throws {
        let text = try IPCalc.report(for: "172.16.0.0/12").plainText
        #expect(text == """
            Address:   172.16.0.0            10101100.0001 0000.00000000.00000000
            Netmask:   255.240.0.0 = 12      11111111.1111 0000.00000000.00000000
            Wildcard:  0.15.255.255          00000000.0000 1111.11111111.11111111

            Network:   172.16.0.0/12         10101100.0001 0000.00000000.00000000 (Class B)
            Broadcast: 172.31.255.255        10101100.0001 1111.11111111.11111111
            HostMin:   172.16.0.1            10101100.0001 0000.00000000.00000001
            HostMax:   172.31.255.254        10101100.0001 1111.11111111.11111110
            Hosts/Net: 1048574
            Type:      Private (RFC 1918)
            """)
    }

    @Test func copyValues() throws {
        let fields = try IPCalc.report(for: "172.16.0.0/12").sections[0].lines.compactMap { line -> IPCalcReport.Field? in
            if case .field(let field) = line { field } else { nil }
        }
        #expect(fields.map(\.copyValue) == ["172.16.0.0", "255.240.0.0", "0.15.255.255", "172.16.0.0/12",
                                            "172.31.255.255", "172.16.0.1", "172.31.255.254", "1048574", "Private (RFC 1918)"])
    }

    @Test func fieldIndicesAndRows() throws {
        let fields = try IPCalc.report(for: "192.168.0.0/24 /25").fields
        #expect(fields.map(\.index) == Array(0..<fields.count))
        #expect(fields[3].plainLine == "Network:   192.168.0.0/24        11000000.10101000.00000000. 00000000 (Class C)")
    }

    @Test func subnets() throws {
        let report = try IPCalc.report(for: "192.168.0.0/24 /26")
        #expect(report.sections.map(\.title) == [nil, "Subnets after transition from /24 to /26", "1.", "2.", "3.", "4.", nil])
        #expect(report.plainText.hasSuffix("Subnets:   4\nHosts:     248"))
    }

    @Test func subnetLimit() throws {
        let report = try IPCalc.report(for: "10.0.0.0/8 /24", subnetLimit: 3)
        #expect(report.sections.count == 2 + 3 + 1)
        #expect(report.plainText.contains("… 65533 more subnets not shown"))
        #expect(report.plainText.hasSuffix("Subnets:   65536\nHosts:     16646144"))
    }

    @Test func supernet() throws {
        let report = try IPCalc.report(for: "172.16.0.0/12 /8")
        #expect(report.sections.last?.title == "Supernet")
        #expect(report.plainText.contains("Network:   172.0.0.0/8"))
    }

    @Test func rangeReport() throws {
        let report = try IPCalc.report(for: "10.0.0.0 - 10.0.1.255")
        #expect(report.plainText == "deaggregate 10.0.0.0 - 10.0.1.255\n10.0.0.0/23")
    }
}

@Suite struct IPv6Tests {
    @Test(arguments: [
        ("2001:db8::1", "2001:db8::1"),
        ("2001:0DB8:0000:0000:0000:0000:0000:0001", "2001:db8::1"),
        ("::", "::"),
        ("::1", "::1"),
        ("1::", "1::"),
        ("2001:db8:0:0:1:0:0:1", "2001:db8::1:0:0:1"),      // first of equal runs is compressed
        ("2001:db8:0:1:1:1:1:1", "2001:db8:0:1:1:1:1:1"),   // a single zero group is not compressed
        ("::ffff:192.0.2.1", "::ffff:192.0.2.1"),
        ("64:ff9b::192.0.2.33", "64:ff9b::c000:221"),
        ("fe80::1%en0", "fe80::1"),
    ])
    func canonicalForm(input: String, expected: String) throws {
        #expect(try #require(IPv6Address(input)).description == expected)
    }

    @Test(arguments: ["", ":", ":::", "1::2::3", "12345::", "g::", "1:2:3:4:5:6:7", "1:2:3:4:5:6:7:8:9",
                      "1:2:3:4:5:6:7::8", "1.2.3.4::", "::1.2.3", "::+1"])
    func invalid(input: String) {
        #expect(IPv6Address(input) == nil)
    }

    @Test func network() throws {
        guard case .network6(let n, nil) = try IPCalcQuery.parse("2001:db8:abcd:12::77/64") else {
            Issue.record("not an IPv6 network"); return
        }
        #expect(n.cidr == "2001:db8:abcd:12::/64")
        #expect(n.last.description == "2001:db8:abcd:12:ffff:ffff:ffff:ffff")
        #expect(n.netmask.description == "ffff:ffff:ffff:ffff::")
        #expect(n.addressCount == "18446744073709551616")
        #expect(n.reverseZone == "2.1.0.0.d.c.b.a.8.b.d.0.1.0.0.2.ip6.arpa")
        #expect(n.type == "Documentation (RFC 3849)")
        #expect(n.address.expanded == "2001:0db8:abcd:0012:0000:0000:0000:0077")
    }

    @Test func defaultsAndEdges() throws {
        #expect(try IPCalcQuery.parse("fe80::1") == .network6(IPv6Network(address: IPv6Address("fe80::1")!, prefix: 64), moveTo: nil))
        let all = IPv6Network(address: IPv6Address("::")!, prefix: 0)
        #expect(all.addressCount == "340282366920938463463374607431768211456")
        #expect(all.last.description == "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff")
        #expect(all.reverseZone == "ip6.arpa")
        #expect(all.specialRange == nil)
        #expect(IPv6Network(address: IPv6Address("fd12::")!, prefix: 48).specialRange?.name == "Unique local (RFC 4193)")
        #expect(IPv6Network(address: IPv6Address("2a00:1450::")!, prefix: 32).specialRange?.name == "Global unicast (RFC 4291)")
        #expect(IPv6Network(address: IPv6Address("4000::")!, prefix: 16).type == "Reserved by IETF")
        #expect(all.type == "Contains special-purpose ranges")
    }

    @Test func deaggregate() {
        let cidrs = IPv6Network.deaggregate(from: IPv6Address("2001:db8::1")!, to: IPv6Address("2001:db8::10")!).map(\.cidr)
        #expect(cidrs == ["2001:db8::1/128", "2001:db8::2/127", "2001:db8::4/126", "2001:db8::8/125", "2001:db8::10/128"])
        #expect(IPv6Network.deaggregate(from: IPv6Address("::")!, to: IPv6Address("ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff")!).map(\.cidr) == ["::/0"])
        #expect(IPv6Network.deaggregate(from: IPv6Address("ffff:ffff:ffff:ffff:ffff:ffff:ffff:fffe")!, to: IPv6Address("ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff")!).map(\.cidr) == ["ffff:ffff:ffff:ffff:ffff:ffff:ffff:fffe/127"])
    }

    @Test func report() throws {
        let text = try IPCalc.report(for: "2001:db8::1/64").plainText
        #expect(text == """
            Address:   2001:db8::1
            Expanded:  2001:0db8:0000:0000:0000:0000:0000:0001
            Netmask:   ffff:ffff:ffff:ffff:: = 64

            Network:   2001:db8::/64
            HostMin:   2001:db8::
            HostMax:   2001:db8::ffff:ffff:ffff:ffff
            Addresses: 18446744073709551616  (2^64)
            Reverse:   0.0.0.0.0.0.0.0.8.b.d.0.1.0.0.2.ip6.arpa
            Type:      Documentation (RFC 3849)
            """)
    }

    @Test func subnets() throws {
        let report = try IPCalc.report(for: "2001:db8::/48 /64", subnetLimit: 2)
        #expect(report.sections.map(\.title) == [nil, "Subnets after transition from /48 to /64", "1.", "2.", nil])
        #expect(report.plainText.contains("Network:   2001:db8:0:1::/64"))
        #expect(report.plainText.hasSuffix("… 65536 subnets in total, first 2 shown\nSubnets:   65536"))
        // 2^128 subnets must not overflow.
        #expect(try IPCalc.report(for: "::/0 /128", subnetLimit: 1).plainText.hasSuffix("Subnets:   340282366920938463463374607431768211456"))
    }

    @Test func supernetAndRange() throws {
        #expect(try IPCalc.report(for: "2001:db8:1::/48 /32").plainText.contains("Network:   2001:db8::/32"))
        #expect(try IPCalc.report(for: "2001:db8::1 - 2001:db8::3").plainText == "deaggregate 2001:db8::1 - 2001:db8::3\n2001:db8::1/128\n2001:db8::2/127")
    }
}

private func addr(_ string: String) -> IPv4Address { IPv4Address(string)! }
private func net(_ string: String, _ prefix: Int) -> IPv4Network { IPv4Network(address: addr(string), prefix: prefix) }
