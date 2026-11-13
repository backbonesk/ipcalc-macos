/// ipcalc-style output, structured so a UI can render and copy each value separately.
public struct IPCalcReport: Sendable, Equatable {
    public var sections: [Section]

    public struct Section: Sendable, Equatable {
        public var title: String?
        public var lines: [Line]
    }

    public enum Line: Sendable, Equatable {
        case field(Field)
        /// The blank line separating the input from the computed network (`=>` in the original ipcalc).
        case arrow
        case text(String)
    }

    public struct Field: Sendable, Equatable {
        public var label: String
        /// What is shown, e.g. `255.240.0.0 = 12`.
        public var value: String
        /// What is copied, e.g. `255.240.0.0`.
        public var copyValue: String
        public var binary: Binary?
        public var note: Note?
        /// Position among all fields of the report, used for keyboard selection.
        public var index = 0
        /// Width of the value column in characters, so binary and notes line up: 22 like ipcalc,
        /// wider for IPv6.
        public var valueWidth = 22

        /// The whole row as plain text in the ipcalc column layout.
        public var plainLine: String {
            var row = label.isEmpty ? value : pad(label, 11) + value
            if binary != nil || note != nil {
                row = pad(row, (label.isEmpty ? 0 : 11) + valueWidth)
            }
            var tail: [String] = []
            if let binary { tail.append(binary.text) }
            if let note { tail.append("(\(note.text))") }
            row += tail.joined(separator: " ")
            while row.last == " " { row.removeLast() }
            return row
        }

        private func pad(_ text: String, _ width: Int) -> String {
            text.count >= width ? text + " " : text + String(repeating: " ", count: width - text.count)
        }
    }

    /// All fields in display order; `fields[i].index == i`.
    public var fields: [Field] {
        sections.flatMap(\.lines).compactMap { line in
            if case .field(let field) = line { field } else { nil }
        }
    }

    /// Numbers the fields and sizes the value column to the longest value followed by more columns.
    init(sections: [Section]) {
        var index = 0
        let valueWidth = sections.flatMap(\.lines).reduce(22) { width, line in
            guard case .field(let field) = line, !field.label.isEmpty, field.binary != nil || field.note != nil
            else { return width }
            return max(width, field.value.count + 2)
        }
        self.sections = sections.map { section in
            var section = section
            section.lines = section.lines.map { line in
                guard case .field(var field) = line else { return line }
                field.index = index
                field.valueWidth = valueWidth
                index += 1
                return .field(field)
            }
            return section
        }
    }

    public struct Binary: Sendable, Equatable {
        public enum Style: Sendable { case plain, netmask }
        public var text: String
        public var style: Style
        /// Number of leading characters that encode the address class (highlighted).
        public var classBits: Int
    }

    /// A short annotation after the value, e.g. the address class or `2^64`.
    public struct Note: Sendable, Equatable {
        public var text: String
    }

    /// Plain-text rendering in the column layout of the original ipcalc.
    public var plainText: String {
        var blocks: [String] = []
        for section in sections {
            var out: [String] = []
            if let title = section.title { out.append(title) }
            for line in section.lines {
                switch line {
                case .arrow:
                    out.append("")
                case .text(let text):
                    out.append(text)
                case .field(let field):
                    out.append(field.plainLine)
                }
            }
            blocks.append(out.joined(separator: "\n"))
        }
        return blocks.joined(separator: "\n\n")
    }
}

public enum IPCalc {
    /// Parses `input` and builds the report. `subnetLimit` caps how many subnets are listed
    /// when splitting a network (the totals are always shown).
    public static func report(for input: String, subnetLimit: Int = 1024) throws(IPCalcError) -> IPCalcReport {
        report(for: try IPCalcQuery.parse(input), subnetLimit: subnetLimit)
    }

    public static func report(for query: IPCalcQuery, subnetLimit: Int = 1024) -> IPCalcReport {
        switch query {
        case .range(let start, let end):
            let networks = IPv4Network.deaggregate(from: start, to: end)
            return IPCalcReport(sections: [
                .init(title: "deaggregate \(start) - \(end)",
                      lines: networks.map { .field(.init(label: "", value: $0.cidr, copyValue: $0.cidr)) }),
            ])

        case .network(let network, let moveTo):
            var sections = [IPCalcReport.Section(title: nil, lines: inputLines(network) + [.arrow] + networkLines(network))]
            if let moveTo, moveTo > network.prefix {
                sections += subnetSections(network, moveTo: moveTo, limit: subnetLimit)
            } else if let moveTo, moveTo < network.prefix {
                let supernet = IPv4Network(address: network.network, prefix: moveTo)
                sections.append(.init(title: "Supernet", lines: maskLines(supernet) + [.arrow] + networkLines(supernet)))
            }
            return IPCalcReport(sections: sections)

        case .range6(let start, let end):
            let networks = IPv6Network.deaggregate(from: start, to: end)
            return IPCalcReport(sections: [
                .init(title: "deaggregate \(start) - \(end)",
                      lines: networks.map { .field(.init(label: "", value: $0.cidr, copyValue: $0.cidr)) }),
            ])

        case .network6(let network, let moveTo):
            var sections = [IPCalcReport.Section(title: nil, lines: inputLines6(network) + [.arrow] + networkLines6(network))]
            if let moveTo, moveTo > network.prefix {
                sections += subnetSections6(network, moveTo: moveTo, limit: subnetLimit)
            } else if let moveTo, moveTo < network.prefix {
                let supernet = IPv6Network(address: network.network, prefix: moveTo)
                sections.append(.init(title: "Supernet", lines: [maskLine6(supernet), .arrow] + networkLines6(supernet)))
            }
            return IPCalcReport(sections: sections)
        }
    }

    private static func inputLines6(_ network: IPv6Network) -> [IPCalcReport.Line] {
        [
            .field(.init(label: "Address:", value: network.address.description, copyValue: network.address.description)),
            .field(.init(label: "Expanded:", value: network.address.expanded, copyValue: network.address.expanded)),
            maskLine6(network),
        ]
    }

    private static func maskLine6(_ network: IPv6Network) -> IPCalcReport.Line {
        .field(.init(label: "Netmask:", value: "\(network.netmask) = \(network.prefix)", copyValue: network.netmask.description))
    }

    private static func networkLines6(_ network: IPv6Network) -> [IPCalcReport.Line] {
        [
            .field(.init(label: "Network:", value: network.cidr, copyValue: network.cidr)),
            .field(.init(label: "HostMin:", value: network.network.description, copyValue: network.network.description)),
            .field(.init(label: "HostMax:", value: network.last.description, copyValue: network.last.description)),
            .field(.init(label: "Addresses:", value: network.addressCount, copyValue: network.addressCount,
                         note: .init(text: "2^\(128 - network.prefix)"))),
            .field(.init(label: "Reverse:", value: network.reverseZone, copyValue: network.reverseZone)),
            .field(.init(label: "Type:", value: network.type, copyValue: network.type)),
        ]
    }

    private static func subnetSections6(_ network: IPv6Network, moveTo: Int, limit: Int) -> [IPCalcReport.Section] {
        let template = IPv6Network(address: network.network, prefix: moveTo)
        var sections = [IPCalcReport.Section(title: "Subnets after transition from /\(network.prefix) to /\(moveTo)",
                                             lines: [maskLine6(template)])]
        let bits = moveTo - network.prefix
        // Only compare against the limit when the count fits; 2^bits can exceed any Int.
        let shown = bits < 63 ? min(1 << bits, max(limit, 0)) : max(limit, 0)
        for index in 0..<shown {
            sections.append(.init(title: "\(index + 1).", lines: networkLines6(network.subnet(UInt128(index), prefix: moveTo))))
        }
        let count = IPv6Network.powerOfTwo(bits)
        var summary: [IPCalcReport.Line] = []
        if bits >= 63 || 1 << bits > shown {
            summary.append(.text("… \(count) subnets in total, first \(shown) shown"))
        }
        summary.append(.field(.init(label: "Subnets:", value: count, copyValue: count)))
        sections.append(.init(title: nil, lines: summary))
        return sections
    }

    private static func inputLines(_ network: IPv4Network) -> [IPCalcReport.Line] {
        [field("Address:", network.address, network.prefix)] + maskLines(network)
    }

    private static func maskLines(_ network: IPv4Network) -> [IPCalcReport.Line] {
        [
            .field(.init(label: "Netmask:",
                         value: "\(network.netmask) = \(network.prefix)",
                         copyValue: network.netmask.description,
                         binary: .init(text: network.netmask.binary(splitAt: network.prefix), style: .netmask, classBits: 0))),
            field("Wildcard:", network.wildcard, network.prefix),
        ]
    }

    private static func networkLines(_ network: IPv4Network) -> [IPCalcReport.Line] {
        var lines: [IPCalcReport.Line] = [
            .field(.init(label: "Network:",
                         value: network.cidr,
                         copyValue: network.cidr,
                         binary: .init(text: network.network.binary(splitAt: network.prefix), style: .plain,
                                       classBits: network.ipClass.leadingBits),
                         note: .init(text: network.ipClass.rawValue))),
        ]
        if network.hasBroadcast {
            lines.append(field("Broadcast:", network.broadcast, network.prefix))
        }
        lines.append(field("HostMin:", network.hostMin, network.prefix))
        lines.append(field("HostMax:", network.hostMax, network.prefix))
        lines.append(.field(.init(label: "Hosts/Net:", value: String(network.hostCount), copyValue: String(network.hostCount))))
        lines.append(.field(.init(label: "Type:", value: network.type, copyValue: network.type)))
        return lines
    }

    private static func subnetSections(_ network: IPv4Network, moveTo: Int, limit: Int) -> [IPCalcReport.Section] {
        let count = network.subnetCount(prefix: moveTo)
        let template = IPv4Network(address: network.network, prefix: moveTo)
        var sections = [IPCalcReport.Section(title: "Subnets after transition from /\(network.prefix) to /\(moveTo)",
                                             lines: maskLines(template))]
        for index in 0..<min(count, UInt64(max(limit, 0))) {
            sections.append(.init(title: "\(index + 1).", lines: networkLines(network.subnet(index, prefix: moveTo))))
        }
        var summary: [IPCalcReport.Line] = []
        if count > UInt64(limit) {
            summary.append(.text("… \(count - UInt64(limit)) more subnets not shown"))
        }
        let hosts = count * template.hostCount
        summary.append(.field(.init(label: "Subnets:", value: String(count), copyValue: String(count))))
        summary.append(.field(.init(label: "Hosts:", value: String(hosts), copyValue: String(hosts))))
        sections.append(.init(title: nil, lines: summary))
        return sections
    }

    private static func field(_ label: String, _ address: IPv4Address, _ prefix: Int) -> IPCalcReport.Line {
        .field(.init(label: label,
                     value: address.description,
                     copyValue: address.description,
                     binary: .init(text: address.binary(splitAt: prefix), style: .plain, classBits: 0)))
    }
}
