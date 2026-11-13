import AppIntents

/// The Spotlight / Shortcuts action: type an address and the IP Calc panel opens with the result.
///
/// Spotlight runs actions with their output ignored, so it shows neither returned values nor
/// snippets in a useful way. Opening our own panel also enables keyboard navigation and copying.
struct CalculateSubnetIntent: AppIntent {
    static let title: LocalizedStringResource = "IP"
    static let description = IntentDescription(
        "Shows network, broadcast, host range, netmask and wildcard for an IPv4 address. Accepts 10.0.0.1/24, 10.0.0.1 255.255.255.0, 192.168.0.0/16 /20 (subnets) or 10.0.0.5 - 10.0.0.70 (range).",
        categoryName: "Network",
        searchKeywords: ["ip", "ipcalc", "subnet", "cidr", "netmask", "network", "calculator"]
    )
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Address", description: "e.g. 172.16.0.0/12",
               inputOptions: String.IntentInputOptions(capitalizationType: .none, autocorrect: false, smartQuotes: false, smartDashes: false),
               requestValueDialog: "Which address or network?")
    var input: String

    static var parameterSummary: some ParameterSummary {
        Summary("IP \(\.$input)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.input = input
        PanelController.shared.show()
        return .result()
    }
}

struct IPCalcShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CalculateSubnetIntent(),
            phrases: [
                "Calculate subnet with \(.applicationName)",
                "Calculate IP with \(.applicationName)",
                "\(.applicationName)",
            ],
            shortTitle: "IP",
            systemImageName: "network"
        )
    }
}
