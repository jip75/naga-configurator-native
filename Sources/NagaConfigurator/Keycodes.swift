import Foundation

// macOS virtual key codes (stable ANSI layout constants) plus label lookup — same table as
// src/lib/keycodes.ts, extended with the modifier-flag glyphs used across both apps' UI.

enum Keycodes {
    enum VK {
        static let a = 0x00, s = 0x01, d = 0x02, f = 0x03, h = 0x04, g = 0x05
        static let z = 0x06, x = 0x07, c = 0x08, v = 0x09, b = 0x0b, q = 0x0c
        static let w = 0x0d, e = 0x0e, r = 0x0f, y = 0x10, t = 0x11, o = 0x1f
        static let u = 0x20, i = 0x22, p = 0x23, l = 0x25, j = 0x26, k = 0x28
        static let n = 0x2d, m = 0x2e
        static let digit1 = 0x12, digit2 = 0x13, digit3 = 0x14, digit4 = 0x15, digit5 = 0x17
        static let digit6 = 0x16, digit7 = 0x1a, digit8 = 0x1c, digit9 = 0x19, digit0 = 0x1d
        static let space = 0x31, tab = 0x30, delete = 0x33, enter = 0x24, escape = 0x35
        static let left = 0x7b, right = 0x7c, down = 0x7d, up = 0x7e
        static let rightShift = 0x3c
    }

    private static let vkToLabel: [Int: String] = [
        VK.a: "A", VK.s: "S", VK.d: "D", VK.f: "F", VK.h: "H", VK.g: "G",
        VK.z: "Z", VK.x: "X", VK.c: "C", VK.v: "V", VK.b: "B", VK.q: "Q",
        VK.w: "W", VK.e: "E", VK.r: "R", VK.y: "Y", VK.t: "T", VK.o: "O",
        VK.u: "U", VK.i: "I", VK.p: "P", VK.l: "L", VK.j: "J", VK.k: "K",
        VK.n: "N", VK.m: "M",
        VK.digit1: "1", VK.digit2: "2", VK.digit3: "3", VK.digit4: "4", VK.digit5: "5",
        VK.digit6: "6", VK.digit7: "7", VK.digit8: "8", VK.digit9: "9", VK.digit0: "0",
        VK.space: "␣", VK.tab: "Tab", VK.delete: "⌫", VK.enter: "⏎", VK.escape: "Esc",
        VK.left: "←", VK.right: "→", VK.down: "↓", VK.up: "↑",
    ]

    static func vkLabel(_ keyCode: Int) -> String {
        vkToLabel[keyCode] ?? "#\(keyCode)"
    }

    static func flagsLabel(_ flags: [ModifierFlag]?) -> String {
        guard let flags, !flags.isEmpty else { return "" }
        let glyphs: [ModifierFlag: String] = [.cmd: "⌘", .shift: "⇧", .ctrl: "⌃", .option: "⌥"]
        return flags.map { glyphs[$0] ?? $0.rawValue }.joined()
    }

    /// NSEvent.keyCode already IS a macOS virtual key code — no translation table needed going the
    /// other direction (unlike the browser's KeyboardEvent.code the Electron app had to map from).
    static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    /// Maps printable ASCII characters to their keyCode + whether shift is needed on US layout.
    /// Non-ASCII and unmapped characters fall back to character-by-character paste via Accessibility.
    static let charToKeyCode: [Character: (code: Int, needsShift: Bool)] = [
        "a": (VK.a, false), "b": (VK.b, false), "c": (VK.c, false), "d": (VK.d, false),
        "e": (VK.e, false), "f": (VK.f, false), "g": (VK.g, false), "h": (VK.h, false),
        "i": (VK.i, false), "j": (VK.j, false), "k": (VK.k, false), "l": (VK.l, false),
        "m": (VK.m, false), "n": (VK.n, false), "o": (VK.o, false), "p": (VK.p, false),
        "q": (VK.q, false), "r": (VK.r, false), "s": (VK.s, false), "t": (VK.t, false),
        "u": (VK.u, false), "v": (VK.v, false), "w": (VK.w, false), "x": (VK.x, false),
        "y": (VK.y, false), "z": (VK.z, false),
        "A": (VK.a, true), "B": (VK.b, true), "C": (VK.c, true), "D": (VK.d, true),
        "E": (VK.e, true), "F": (VK.f, true), "G": (VK.g, true), "H": (VK.h, true),
        "I": (VK.i, true), "J": (VK.j, true), "K": (VK.k, true), "L": (VK.l, true),
        "M": (VK.m, true), "N": (VK.n, true), "O": (VK.o, true), "P": (VK.p, true),
        "Q": (VK.q, true), "R": (VK.r, true), "S": (VK.s, true), "T": (VK.t, true),
        "U": (VK.u, true), "V": (VK.v, true), "W": (VK.w, true), "X": (VK.x, true),
        "Y": (VK.y, true), "Z": (VK.z, true),
        "0": (VK.digit0, false), "1": (VK.digit1, false), "2": (VK.digit2, false),
        "3": (VK.digit3, false), "4": (VK.digit4, false), "5": (VK.digit5, false),
        "6": (VK.digit6, false), "7": (VK.digit7, false), "8": (VK.digit8, false),
        "9": (VK.digit9, false),
        " ": (VK.space, false),
        "-": (0x2b, false), "=": (0x18, false), "[": (0x21, false), "]": (0x1e, false),
        ";": (0x29, false), "'": (0x27, false), "`": (0x32, false), "\\": (0x2a, false),
        ",": (0x2b, false), ".": (0x2f, false), "/": (0x2c, false),
        "!": (VK.digit1, true), "@": (VK.digit2, true), "#": (VK.digit3, true),
        "$": (VK.digit4, true), "%": (VK.digit5, true), "^": (VK.digit6, true),
        "&": (VK.digit7, true), "*": (VK.digit8, true), "(": (VK.digit9, true),
        ")": (VK.digit0, true), "_": (0x2b, true), "+": (0x18, true), "{": (0x21, true),
        "}": (0x1e, true), ":": (0x29, true), "\"": (0x27, true), "~": (0x32, true),
        "<": (0x2b, true), ">": (0x2f, true), "?": (0x2c, true), "|": (0x2a, true),
    ]
}
