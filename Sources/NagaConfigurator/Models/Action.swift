import Foundation

// Mirrors electron/hid-capture.ts's InjectAction union exactly so a mapping.json exported from
// the Electron app is a drop-in match for this app's own mapping.json, field for field.

enum ModifierFlag: String, Codable, CaseIterable {
    case cmd, shift, ctrl, option
}

enum ActionKind: String, Codable {
    case key, mouse, macro, launch, layerToggle
}

struct MacroStep: Codable, Equatable, Identifiable {
    var id = UUID()
    var keyCode: Int
    var flags: [ModifierFlag]?
    var delayMs: Int?

    enum CodingKeys: String, CodingKey { case keyCode, flags, delayMs }
    init(keyCode: Int, flags: [ModifierFlag]? = nil, delayMs: Int? = nil) {
        self.keyCode = keyCode
        self.flags = flags
        self.delayMs = delayMs
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try c.decode(Int.self, forKey: .keyCode)
        flags = try c.decodeIfPresent([ModifierFlag].self, forKey: .flags)
        delayMs = try c.decodeIfPresent(Int.self, forKey: .delayMs)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(keyCode, forKey: .keyCode)
        try c.encodeIfPresent(flags, forKey: .flags)
        try c.encodeIfPresent(delayMs, forKey: .delayMs)
    }
}

enum MouseButton: String, Codable, CaseIterable {
    case left, right, middle, back, forward

    var label: String {
        switch self {
        case .left: return "Left Click"
        case .right: return "Right Click"
        case .middle: return "Middle Click"
        case .back: return "Back"
        case .forward: return "Forward"
        }
    }
}

/// One button's assigned action. Struct-of-optionals keyed by `kind` — same on-disk shape as
/// the TS discriminated union, just flattened for Codable instead of an enum-with-payload, so
/// stray fields from the other kind round-trip harmlessly instead of failing to decode.
struct Action: Codable, Equatable {
    var kind: ActionKind
    var keyCode: Int?
    var flags: [ModifierFlag]?
    var extraKeyDown: Int?
    var extraKeyUp: Int?
    var system: Bool?
    var button: MouseButton?
    var steps: [MacroStep]?
    var appName: String?
    var label: String?
    var targetLayer: HyperLayer?

    static func key(_ keyCode: Int, flags: [ModifierFlag] = [], extraKeyDown: Int? = nil, extraKeyUp: Int? = nil) -> Action {
        Action(kind: .key, keyCode: keyCode, flags: flags.isEmpty ? nil : flags, extraKeyDown: extraKeyDown, extraKeyUp: extraKeyUp)
    }
    static func mouse(_ button: MouseButton) -> Action {
        Action(kind: .mouse, button: button)
    }
    static func macro(_ steps: [MacroStep]) -> Action {
        Action(kind: .macro, steps: steps)
    }
    static func launch(_ appName: String) -> Action {
        Action(kind: .launch, appName: appName)
    }
    static func layerToggle(_ layer: HyperLayer) -> Action {
        Action(kind: .layerToggle, targetLayer: layer)
    }

    var displayLabel: String {
        if let label, !label.trimmingCharacters(in: .whitespaces).isEmpty { return label }
        switch kind {
        case .key:
            return "\(Keycodes.flagsLabel(flags))\(Keycodes.vkLabel(keyCode ?? -1))"
        case .mouse:
            return button?.label ?? "Mouse"
        case .macro:
            let n = steps?.count ?? 0
            return "Macro (\(n) step\(n == 1 ? "" : "s"))"
        case .launch:
            let base = (appName ?? "").split(separator: "/").last.map(String.init) ?? (appName ?? "")
            return base.hasSuffix(".app") ? String(base.dropLast(4)) : base
        case .layerToggle:
            return targetLayer?.label ?? "HyperShift"
        }
    }
}

enum HyperLayer: String, Codable, CaseIterable {
    case base, hyperA, hyperB

    var label: String {
        switch self {
        case .base: return "Standard"
        case .hyperA: return "HyperShift"
        case .hyperB: return "HyperShift B"
        }
    }
}

/// One physical button's full mapping across all three layers. Unset hyperA/hyperB means that
/// layer has no action for this button — each layer stands on its own, never falls back to base.
struct ButtonEntry: Codable, Equatable {
    var base: Action
    var hyperA: Action?
    var hyperB: Action?

    func action(for layer: HyperLayer) -> Action? {
        switch layer {
        case .base: return base
        case .hyperA: return hyperA
        case .hyperB: return hyperB
        }
    }

    func setting(_ action: Action, for layer: HyperLayer) -> ButtonEntry {
        var copy = self
        switch layer {
        case .base: copy.base = action
        case .hyperA: copy.hyperA = action
        case .hyperB: copy.hyperB = action
        }
        return copy
    }
}

typealias ButtonMapping = [String: ButtonEntry]

// Seeded from the same working right-handed Naga Pro V2 Synapse profile the Electron app used.
enum DefaultMapping {
    static let value: ButtonMapping = [
        "1": ButtonEntry(base: .key(Keycodes.VK.c, flags: [.cmd])),
        "2": ButtonEntry(base: .key(Keycodes.VK.v, flags: [.cmd])),
        "3": ButtonEntry(base: .key(Keycodes.VK.a, flags: [.cmd])),
        "4": ButtonEntry(base: .key(Keycodes.VK.left)),
        "5": ButtonEntry(base: .key(Keycodes.VK.down)),
        "6": ButtonEntry(base: .key(Keycodes.VK.right)),
        "7": ButtonEntry(base: .key(Keycodes.VK.delete)),
        "8": ButtonEntry(base: .key(Keycodes.VK.enter, flags: [.shift], extraKeyDown: Keycodes.VK.rightShift, extraKeyUp: Keycodes.VK.rightShift)),
        "9": ButtonEntry(base: .key(Keycodes.VK.escape)),
        "0": ButtonEntry(base: .launch("Mission Control")),
        "-": ButtonEntry(base: .key(Keycodes.VK.space)),
        "=": ButtonEntry(base: .key(Keycodes.VK.enter)),
        // The two buttons flanking the wheel — previously hardwired one-shot layer toggles,
        // now ordinary customizable buttons like 1-12. Default: the one closest to the wheel
        // stays the single HyperShift toggle; the far one is free for anything (screenshot here).
        // topB gets the same action on every layer — unlike topA (the actual toggle-back
        // control), it isn't part of the HyperShift-navigation convention, so "each layer stands
        // on its own" would otherwise silently swallow a topB press made while topA had shifted
        // into hyperA/hyperB (confirmed live 2026-09-11: screenshot fired once on base, then
        // nothing after a topA press changed the active layer).
        "topA": ButtonEntry(base: .layerToggle(.hyperA)),
        "topB": ButtonEntry(base: .launch("Screenshot"), hyperA: .launch("Screenshot"), hyperB: .launch("Screenshot")),
        // "bottomButton" (usage 0x09/0x02) removed 2026-09-11 — see NagaHIDManager's
        // dpiUsageToRawCode comment. It wasn't a distinct physical control; it was this mouse's
        // ordinary secondary click, and mapping it to Mission Control was hijacking every click
        // system-wide, including clicks made to operate this app's own UI.
    ]
}
