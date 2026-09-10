import Foundation

struct ButtonPosition: Identifiable {
    let number: Int
    let rawCode: String
    let x: Double
    let y: Double
    var id: Int { number }
}

struct TopButtonPosition: Identifiable {
    let number: Int
    let x: Double
    let y: Double
    var id: Int { number }
}

/// Hardcoded from src/devices/naga-left-handed.json — a single-device app has no reason to parse
/// JSON for data that never changes at runtime.
enum Device {
    static let id = "naga-left-handed"
    static let displayName = "Razer Naga Left-Handed Edition"
    static let vendorID: UInt32 = 5426
    static let productID: UInt32 = 141

    static let buttons: [ButtonPosition] = [
        .init(number: 1, rawCode: "1", x: 57.4, y: 33),
        .init(number: 2, rawCode: "2", x: 73.7, y: 33),
        .init(number: 3, rawCode: "3", x: 90.0, y: 34),
        .init(number: 4, rawCode: "4", x: 55.1, y: 42),
        .init(number: 5, rawCode: "5", x: 71.4, y: 42),
        .init(number: 6, rawCode: "6", x: 90.0, y: 43),
        .init(number: 7, rawCode: "7", x: 52.8, y: 51),
        .init(number: 8, rawCode: "8", x: 71.4, y: 51),
        .init(number: 9, rawCode: "9", x: 90.0, y: 52),
        .init(number: 10, rawCode: "0", x: 50.5, y: 61),
        .init(number: 11, rawCode: "-", x: 69.1, y: 61),
        .init(number: 12, rawCode: "=", x: 87.7, y: 62),
    ]

    static let topButtons: [TopButtonPosition] = [
        .init(number: 1, x: 80, y: 45.8),
        .init(number: 2, x: 86, y: 45.8),
        .init(number: 3, x: 92, y: 45.8),
        .init(number: 4, x: 80, y: 49.8),
        .init(number: 5, x: 86, y: 49.8),
        .init(number: 6, x: 92, y: 49.8),
        .init(number: 7, x: 80, y: 53.2),
        .init(number: 8, x: 86, y: 53.2),
        .init(number: 9, x: 92, y: 53.2),
        .init(number: 10, x: 80, y: 57.2),
        .init(number: 11, x: 86, y: 57.2),
        .init(number: 12, x: 92, y: 57.2),
    ]

    static func button(for rawCode: String) -> ButtonPosition? {
        buttons.first { $0.rawCode == rawCode }
    }
}
