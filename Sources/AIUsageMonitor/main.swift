import AppKit
import UsageCore

// A dead child turns the next pipe write into SIGPIPE, which kills the whole
// process before any diagnostic is printed. Ignoring it surfaces the same
// failure as a thrown error instead.
signal(SIGPIPE, SIG_IGN)

// `--probe` prints one snapshot and exits: the data path, verifiable without
// taking over the menu bar.
if CommandLine.arguments.contains("--probe") {
    func render(_ provider: ProviderUsage) {
        let plan = provider.planLabel.map { " (\($0))" } ?? ""
        print("\(provider.provider.displayName)\(plan): \(provider.status.rawValue)")
        if let detail = provider.detail { print("  \(detail)") }
        for window in provider.windows + provider.extraWindows {
            let reset = window.resetsAt.map { " · \(Format.reset($0))" } ?? ""
            print("  \(Format.bar(window.usedPercent)) \(Format.percent(window.usedPercent))  \(window.label)\(reset)")
        }
    }
    // Each probe prints as it finishes so one hung provider cannot hide the
    // other's output.
    render(await ClaudeProbe.run())
    render(await CodexProbe.run())
    exit(0)
}

// An accessory app: menu bar only, no Dock tile, no windows to restore.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let controller = StatusController()
application.delegate = controller
application.run()
