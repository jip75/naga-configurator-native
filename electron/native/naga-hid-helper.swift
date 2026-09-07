import Foundation
import IOKit
import IOKit.hid
import CoreGraphics

// Naga Configurator's own HID bridge — replaces Karabiner-Elements entirely.
// Capture: opens the Naga's keyboard-usage HID interface non-exclusively (Input Monitoring only).
// Non-exclusive because kIOHIDOptionsTypeSeizeDevice on current macOS additionally requires a
// privileged-client entitlement that an ad-hoc-signed binary can never hold (fails
// kIOReturnNotPrivileged regardless of TCC state) — confirmed via the unified log's
// "Entitlements 0 privilegedClient: No" kernel line. Non-exclusive means the OS keyboard stack
// also sees these raw number-row codes (0x1E-0x2E); if that causes stray digits to type into
// whatever has focus, add a CGEventTap to swallow them at injection time.
// Inject: synthesizes the mapped output via CGEventPost (Accessibility only).
// No system/driver extension of any kind is required for either half.

let vendorID: Int = 0x1532
let productID: Int = 0x8D

// USB HID keyboard usage page (0x07) usage IDs for the 12 confirmed button codes.
let usageToLabel: [UInt32: String] = [
    0x1E: "1", 0x1F: "2", 0x20: "3", 0x21: "4", 0x22: "5", 0x23: "6",
    0x24: "7", 0x25: "8", 0x26: "9", 0x27: "0", 0x2D: "-", 0x2E: "=",
]

func emit(_ dict: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
}

func logErr(_ message: String) {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
}

// MARK: - Capture

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

let matchDict: [String: Any] = [
    kIOHIDVendorIDKey: vendorID,
    kIOHIDProductIDKey: productID,
    kIOHIDDeviceUsagePageKey: 0x01,
    kIOHIDDeviceUsageKey: 0x06,
]
IOHIDManagerSetDeviceMatching(manager, matchDict as CFDictionary)

let inputCallback: IOHIDValueCallback = { _, _, _, value in
    let element = IOHIDValueGetElement(value)
    guard IOHIDElementGetUsagePage(element) == 0x07 else { return }
    guard IOHIDValueGetIntegerValue(value) == 1 else { return } // key-down transition only
    let usage = IOHIDElementGetUsage(element)
    guard let label = usageToLabel[usage] else { return }
    if let keyCode = usageToKeyCode[usage] { markForSwallow(keyCode) }
    emit(["type": "button", "code": label])
}
IOHIDManagerRegisterInputValueCallback(manager, inputCallback, nil)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
guard openResult == kIOReturnSuccess else {
    logErr("naga-hid-helper: failed to open device (IOReturn \(openResult)) — is Input Monitoring granted?")
    exit(1)
}

emit(["type": "ready", "vendorId": vendorID, "productId": productID])

// MARK: - Swallow stray keystrokes
// Non-exclusive open (see note above) means the OS keyboard stack independently turns these same
// usage codes into real keydown/keyup CGEvents on whatever app has focus — confirmed live: Razer's
// own Synapse app (RazerAppEngine) is also installed with its own DriverKit HID extensions, so the
// leak may originate there rather than from this helper's open mode, but the fix is the same either
// way. We already know a button fired (inputCallback above), so mark its virtual keycode and swallow
// the very next matching CGEvent pair here instead of letting it reach the focused app. A short TTL
// drops the mark if no matching CGEvent shows up, so real typing on the physical keyboard is untouched.

let usageToKeyCode: [UInt32: CGKeyCode] = [
    0x1E: 0x12, 0x1F: 0x13, 0x20: 0x14, 0x21: 0x15, 0x22: 0x17, 0x23: 0x16,
    0x24: 0x1A, 0x25: 0x1C, 0x26: 0x19, 0x27: 0x1D, 0x2D: 0x1B, 0x2E: 0x18,
]

var pendingSwallow: [CGKeyCode: CFAbsoluteTime] = [:]
var swallowedKeyUp: Set<CGKeyCode> = []
let swallowTTL: CFAbsoluteTime = 0.3

func markForSwallow(_ keyCode: CGKeyCode) {
    pendingSwallow[keyCode] = CFAbsoluteTimeGetCurrent()
}

func takeSwallow(_ keyCode: CGKeyCode) -> Bool {
    guard let markedAt = pendingSwallow[keyCode] else { return false }
    pendingSwallow.removeValue(forKey: keyCode)
    return CFAbsoluteTimeGetCurrent() - markedAt <= swallowTTL
}

let tapCallback: CGEventTapCallBack = { _, type, event, _ in
    guard type == .keyDown || type == .keyUp else { return Unmanaged.passRetained(event) }
    let keyCode = CGKeyCode(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
    if type == .keyDown {
        if takeSwallow(keyCode) {
            swallowedKeyUp.insert(keyCode)
            return nil
        }
    } else if swallowedKeyUp.remove(keyCode) != nil {
        return nil
    }
    return Unmanaged.passRetained(event)
}

let tapEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
guard let eventTap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: CGEventMask(tapEventMask),
    callback: tapCallback,
    userInfo: nil
) else {
    logErr("naga-hid-helper: failed to create CGEventTap — is Accessibility granted?")
    exit(1)
}
CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0), .commonModes)
CGEvent.tapEnable(tap: eventTap, enable: true)

// MARK: - Inject

struct InjectCommand: Decodable {
    let keyCode: CGKeyCode
    let flags: [String]?
    let extraKeyDown: CGKeyCode?   // e.g. right-shift held down around the main key
    let extraKeyUp: CGKeyCode?
}

func flagMask(_ names: [String]) -> CGEventFlags {
    var mask: CGEventFlags = []
    for name in names {
        switch name {
        case "cmd": mask.insert(.maskCommand)
        case "shift": mask.insert(.maskShift)
        case "ctrl": mask.insert(.maskControl)
        case "alt", "option": mask.insert(.maskAlternate)
        default: break
        }
    }
    return mask
}

// System-reserved shortcuts (Mission Control, Spaces, Show Desktop) need to be injected via
// System Events GUI scripting, not raw CGEventPost (confirmed empirically — see hid-capture.ts).
// That requires Automation/AppleEvents consent, which only prompts correctly for a process
// registered with LaunchServices as a real .app bundle — this bare CLI binary never gets that
// prompt (confirmed: silent NSAppleScriptErrorNumber 1002, no dialog, nothing added to TCC).
// So "system" commands are handled entirely on the Electron main-process side and never reach
// this helper's stdin at all — see NagaBridge.injectSystemShortcut in hid-capture.ts.

func post(_ keyCode: CGKeyCode, down: Bool, flags: CGEventFlags) {
    guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down) else { return }
    event.flags = flags
    event.post(tap: .cghidEventTap)
}

func inject(_ command: InjectCommand) {
    let flags = flagMask(command.flags ?? [])
    if let extra = command.extraKeyDown { post(extra, down: true, flags: []) }
    post(command.keyCode, down: true, flags: flags)
    post(command.keyCode, down: false, flags: flags)
    if let extra = command.extraKeyUp { post(extra, down: false, flags: []) }
}

// Mouse Function: side buttons remapped to standard mouse clicks. Posted at the current
// cursor position (CGEventPost has no notion of a mouse's own physical buttons here — this
// mouse enumerates its extra buttons as a keyboard-usage HID, see capture note above — so we
// synthesize the click macOS itself would have sent for a real mouse-3/4/5 press).
func postMouse(_ type: CGEventType, button: CGMouseButton, buttonNumber: Int64? = nil) {
    let loc = CGEvent(source: nil)?.location ?? .zero
    guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: loc, mouseButton: button) else { return }
    if let n = buttonNumber { event.setIntegerValueField(.mouseEventButtonNumber, value: n) }
    event.post(tap: .cghidEventTap)
}

func injectMouse(_ button: String) {
    switch button {
    case "left":
        postMouse(.leftMouseDown, button: .left)
        postMouse(.leftMouseUp, button: .left)
    case "right":
        postMouse(.rightMouseDown, button: .right)
        postMouse(.rightMouseUp, button: .right)
    case "middle":
        postMouse(.otherMouseDown, button: .center, buttonNumber: 2)
        postMouse(.otherMouseUp, button: .center, buttonNumber: 2)
    case "back":
        postMouse(.otherMouseDown, button: .center, buttonNumber: 3)
        postMouse(.otherMouseUp, button: .center, buttonNumber: 3)
    case "forward":
        postMouse(.otherMouseDown, button: .center, buttonNumber: 4)
        postMouse(.otherMouseUp, button: .center, buttonNumber: 4)
    default:
        break
    }
}

let stdinQueue = DispatchQueue(label: "naga-hid-helper.stdin")
stdinQueue.async {
    while let line = readLine(strippingNewline: true) {
        guard let data = line.data(using: .utf8) else { continue }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let mouseButton = obj["mouse"] as? String {
            injectMouse(mouseButton)
        } else if let command = try? JSONDecoder().decode(InjectCommand.self, from: data) {
            inject(command)
        }
    }
}

CFRunLoopRun()
