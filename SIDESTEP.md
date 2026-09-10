# SIDESTEP — Naga Configurator native rewrite lane
2026-09-07 18:45 ET

Forked from: ~/dev/naga-configurator, branch `main` (commit df26197, initial baseline)
This lane: branch `native-rewrite`, worktree `~/dev/naga-configurator-native`

## This lane owns
- Everything native: AppKit/SwiftUI rewrite of the configurator UI, replacing Electron entirely.
- DMG packaging + notarization path.
- Mac App Store distribution research (Apple Developer account already exists — Jorivan's own).
- The App Store sandboxing / HID-entitlement risk (below) — this lane's first job.

## Original session keeps (do not touch from this lane)
- `electron/`, `src/`, `index.html`, Vite config — the whole Electron+React app, actively shipping
  (per-button naming already live, hyper-shift schema/UI in progress there).
- Both lanes share `.git` history — commits are visible either direction via `git log`, but never
  edit the other lane's files from this worktree.

## Open risk to resolve FIRST — before writing any SwiftUI
**Does Mac App Store sandboxing block the HID access this app depends on?**

Critical context already known from the Electron lane's existing Swift helper
(`electron/native/naga-hid-helper.swift`, present in the initial commit — read it before assuming
anything):
- It already proves `IOHIDManager` **non-exclusive** open (Input Monitoring entitlement only) works
  on an **ad-hoc-signed, non-sandboxed** binary today.
- `kIOHIDOptionsTypeSeizeDevice` (exclusive open) was tried and confirmed to fail —
  `kIOReturnNotPrivileged` — because it needs a privileged-client entitlement no ad-hoc-signed binary
  can hold. That's a *separate*, already-settled dead end — don't re-litigate exclusive HID access.
- Output injection uses `CGEventPost` (Accessibility entitlement only), also outside the sandbox.

The unresolved question is specifically: does the **Mac App Store's stricter App Sandbox**
(`com.apple.security.app-sandbox = true`, required for Store submission) still permit non-exclusive
`IOHIDManager` device matching + Input Monitoring, or does sandboxing block HID device enumeration
entirely regardless of entitlements? Resolve with Apple's actual sandbox + entitlement docs and/or a
minimal sandboxed test build — not assumption. Report a clear yes/no/it-depends before starting the
full rewrite.

If it's a hard no: the practical answer is DMG-only distribution (direct download + notarization,
no Store) — simpler anyway for a free giveaway app. Say so plainly rather than a workaround.

## Priority after the risk clears
1. Native AppKit/SwiftUI shell replicating current Electron UI: 1-12 button grid, per-button custom
   naming (already shipped in the Electron lane — treat its behavior as the spec to match), hyper-
   shift 3-way layer toggle (schema being designed in the Electron lane in parallel — check its
   latest state in `~/dev/naga-configurator` before assuming it's final).
2. DMG packaging + notarization.
3. Distribution decision (Store vs. DMG-only) based on the risk finding above.

## Do NOT
- Re-litigate exclusive HID device access (`kIOHIDOptionsTypeSeizeDevice`) — permanently dead end,
  confirmed above.
- Re-litigate button 10 / keyboard-shortcut / osascript / TCC approaches — permanently abandoned in
  the Electron lane, applies here too.
- Build a numpad/dual-mode/swap-box selector — right-handed hardware feature, out of scope.
- Assume "one codebase, two stores" (DMG + App Store) works without resolving the risk above first.

## Merge-back plan
**Hard cutover, no line-level merge.** Different language/framework (Swift vs. TS/Electron) — there
is nothing to diff-merge. Once this lane reaches feature parity with the Electron app (1-12 grid,
naming, hyper-shift), it replaces it: the Electron lane is archived, not merged in. No merge attempt
before parity.

## DONE WHEN
Sandbox risk has a documented yes/no/it-depends answer, AND (if yes/it-depends) a working native
AppKit/SwiftUI shell exists reading the same 1-12 button grid + naming behavior as the Electron app.

Full transcript (Electron-lane session that spawned this fork): /Users/jorivan/.claude/projects/-Users-jorivan/ce3bdeb3-3c80-4a21-b817-4640ccb1b663.jsonl
