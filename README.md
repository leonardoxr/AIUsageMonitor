# AI Usage Monitor

A macOS menu bar app that shows how much of your **Claude** and **Codex**
subscription quotas is spent, before the next turn silently stops running.

![Menu bar excerpt](assets/menu-bar.png)

## Why

- **Costs nothing to read.** Both quotas come from metadata endpoints that bill
  nothing against the plan, so the numbers keep refreshing even after a limit
  is reached — which is exactly when they matter.
- **Extremely light.** Native Swift/AppKit. No Electron, no Node, no web view,
  no polling loop that repaints. Idle cost is one coalesced timer wake per
  interval; the menu is only built while it is open.

## Requirements

- macOS 14+
- Xcode Command Line Tools (`xcode-select --install`) — Swift 6
- The `claude` and/or `codex` CLIs installed and **signed in to a subscription
  plan** (API keys have no plan quota and are reported as unsigned)

## Install

```bash
make install
```

That builds `dist/AIUsageMonitor.app`, copies it to `/Applications`, and opens
it. Build and ad-hoc sign only — sharing the app with another Mac needs a
Developer ID identity (`CODESIGN_IDENTITY=… make app`).

## Use

The menu bar shows each provider's brand mark next to its binding percentage:
the window closest to stopping the next turn (Claude's five-hour session or
weekly, Codex's weekly). Past 90% the figure turns red.

Click for the full menu:

- every rolling window as a bar (`████░░░░░░  51%  5 hour · resets in 2h 10m`)
- per-model allowances (e.g. Codex Spark) kept apart from the plan quota
- **Refresh Now** (`⌘R`), refresh interval (5/10/30 min), **Launch at Login**
- **Quit** (`⌘Q`)

The stored Claude password is read, never written — refreshing an expired
login is Claude Code's job, and the menu tells you to run `claude` again when
it is stale.

## Without the menu bar

```bash
make probe          # print one snapshot and exit (~20 s, Codex spawn included)
```

## Development

```bash
make build          # swift build
make test           # 14 parser + formatting tests against captured payloads
make app            # assemble + ad-hoc sign dist/AIUsageMonitor.app
```

`Sources/UsageCore` has no AppKit and is fully unit-tested; the AppKit shell
in `Sources/AIUsageMonitor` is deliberately thin. Quota mechanics came from
[T3 Code](https://github.com/t3dotgg/t3code)'s `SubscriptionUsageService` (see
`docs/internals/providers.md` there) and were re-verified by hand before any
Swift was written.