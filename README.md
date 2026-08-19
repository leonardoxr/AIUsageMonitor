# AI Usage Monitor

A macOS menu bar app that shows how much of your **Claude** and **Codex**
subscription quotas is spent — before the next turn silently stops running.

![Menu bar](assets/menu-bar.png)

## Why

- **Costs nothing to read.** Both quotas come from metadata endpoints that bill
  nothing against the plan, so the numbers keep refreshing even after a limit
  is reached — which is exactly when they matter.
- **Extremely light.** Native Swift/AppKit. No Electron, no Node, no web view,
  and no polling loop that repaints: one coalesced timer wake per refresh
  interval, and the menu is only built while it is open.

## Requirements

- macOS 14 or later (Apple Silicon and Intel)
- The `claude` and/or `codex` CLIs installed and **signed in to a
  subscription plan**. API-key logins have no plan quota and are reported as
  unsigned.

## Install

1. Download `AIUsageMonitor-x.x.x.zip` from the
   [latest release](https://github.com/leonardoxr/AIUsageMonitor/releases/latest).
2. Unzip and move the app to your Applications folder.

The app is ad-hoc signed (no Developer ID), so the first launch is blocked by
Gatekeeper. Open it once with **right-click → Open → Open**, or clear the
quarantine flag:

```bash
xattr -dr com.apple.quarantine /Applications/AIUsageMonitor.app
```

Then launch it — it lives in the menu bar, with no Dock tile.

## Use

The menu bar shows each provider's mark next to its binding percentage: the
window closest to stopping the next turn (Claude's five-hour session or
weekly, Codex's weekly). Past 90% the figure turns red.

Click for the full menu:

- every rolling window as a bar (`████░░░░░░  51%  5 hour · resets in 2h 10m`)
- per-model allowances (e.g. Codex Spark) kept apart from the plan quota
- **Refresh Now** (⌘R), refresh interval (5/10/30 min), **Launch at Login**
- **Quit** (⌘Q)

The stored Claude login is read, never written — refreshing an expired login
is Claude Code's own job, and the menu tells you to run `claude` when the
credential is stale.

## Limitations

- Quota figures move in hours, not seconds: the default 10-minute refresh
  (5/10/30 min options) matches how the windows actually change.
- Codex reports a plan quota only for ChatGPT-plan logins; API-key and
  Bedrock logins bill per token and are shown as unsigned.
- Both CLIs must be reachable; a missing binary or a failed request shows as
  unavailable rather than a guessed number.