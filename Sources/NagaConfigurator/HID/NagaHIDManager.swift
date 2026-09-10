import Foundation
import IOKit
import IOKit.hid
import CoreGraphics
import Combine

/// In-process replacement for electron/native/naga-hid-helper.swift + electron/hid-capture.ts's
/// NagaBridge combined — no spawned subprocess, no stdin/stdout JSON protocol, just direct calls.
/// Capture: opens the Naga's keyboard-usage HID interface non-exclusively (Input Monitoring only).
/// Exclusive open (kIOHIDOptionsTypeSeizeDevice) is a confirmed dead end on this OS — fails
/// kIOReturnNotPrivileged, needs a privileged-client entitlement no ad-hoc-signed binary can hold.
/// Inject: synthesizes the mapped output via CGEventPost (Accessibility only).
/// No system/driver extension of any kind — this is what let the whole app leave Electron+Karabiner.
final class NagaHIDManager: ObservableObject {
    @Published private(set) var connected = false
    @Published private(set) var activeLayer: HyperLayer = .base
    @Published var lastFiredButton: Int?

    var onButtonPressed: ((String) -> Void)?

    private var manager: IOHIDManager?
    private var eventTap: CFMachPort?
    private var pendingSwallow: [CGKeyCode: CFAbsoluteTime] = [:]
    private var swallowedKeyUp: Set<CGKeyCode> = []
    private let swallowTTL: CFAbsoluteTime = 0.3
    private var clearFiredWorkItem: DispatchWorkItem?
    // The device re-sends intValue=1 continuously for a usage while its button stays physically
    // held (no distinct repeat usage code) — without this, holding a button a beat too long fired
    // dispatch() dozens of times (e.g. relaunching Mission Control in a storm). Track which usages
    // are already "down" so only the 0->1 edge fires; the matching 1->0 clears it.
    private var heldUsages: Set<UInt32> = []

    private static let usageToLabel: [UInt32: String] = [
        0x1E: "1", 0x1F: "2", 0x20: "3", 0x21: "4", 0x22: "5", 0x23: "6",
        0x24: "7", 0x25: "8", 0x26: "9", 0x27: "0", 0x2D: "-", 0x2E: "=",
    ]
    private static let usageToKeyCode: [UInt32: CGKeyCode] = [
        0x1E: 0x12, 0x1F: 0x13, 0x20: 0x14, 0x21: 0x15, 0x22: 0x17, 0x23: 0x16,
        0x24: 0x1A, 0x25: 0x1C, 0x26: 0x19, 0x27: 0x1D, 0x2D: 0x1B, 0x2E: 0x18,
    ]
    // The two buttons flanking the wheel — customizable now, same as buttons 1-12.
    private static let dpiUsageToRawCode: [UInt32: String] = [0x19: "topA", 0x0C: "topB"]

    func start() {
        guard manager == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager

        let matchDict: [String: Any] = [
            kIOHIDVendorIDKey: Int(Device.vendorID),
            kIOHIDProductIDKey: Int(Device.productID),
            kIOHIDDeviceUsagePageKey: 0x01,
            kIOHIDDeviceUsageKey: 0x06,
        ]
        IOHIDManagerSetDeviceMatching(manager, matchDict as CFDictionary)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            guard let context else { return }
            let this = Unmanaged<NagaHIDManager>.fromOpaque(context).takeUnretainedValue()
            this.handleInput(value)
        }, selfPtr)

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, _ in
            guard let context else { return }
            let this = Unmanaged<NagaHIDManager>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { this.connected = true }
        }, selfPtr)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, _ in
            guard let context else { return }
            let this = Unmanaged<NagaHIDManager>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { this.connected = false }
        }, selfPtr)

        // Must match the event tap's mode below — defaultMode vs commonModes let the tap see the
        // real keyDown before this callback marks it for swallowing, whenever the run loop is
        // servicing a mode outside plain defaultMode (menu tracking, modal panels, etc).
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if openResult != kIOReturnSuccess {
            NSLog("NagaHIDManager: failed to open device (IOReturn %d) — is Input Monitoring granted?", openResult)
        }

        setupEventTap()

        if ProcessInfo.processInfo.environment["NAGA_DISCOVER"] != nil {
            startDiscoveryManager()
        }
    }

    private var discoveryManager: IOHIDManager?
    private func startDiscoveryManager() {
        let disco = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        discoveryManager = disco
        let matchDict: [String: Any] = [
            kIOHIDVendorIDKey: Int(Device.vendorID),
            kIOHIDProductIDKey: Int(Device.productID),
        ]
        IOHIDManagerSetDeviceMatching(disco, matchDict as CFDictionary)
        IOHIDManagerRegisterInputValueCallback(disco, { _, _, _, value in
            let element = IOHIDValueGetElement(value)
            let up = IOHIDElementGetUsagePage(element)
            let u = IOHIDElementGetUsage(element)
            // Skip continuous X/Y motion (0x01/0x30,0x31) and vendor telemetry (0xFF00) — pure noise for button discovery.
            if up == 0x01 && (u == 0x30 || u == 0x31) { return }
            if up == 0xFF00 { return }
            let v = IOHIDValueGetIntegerValue(value)
            let reportID = IOHIDElementGetReportID(element)
            let cookie = IOHIDElementGetCookie(element)
            print("DISCOVER usagePage=\(String(format: "0x%02X", up)) usage=\(String(format: "0x%02X", u)) reportID=\(reportID) cookie=\(cookie) value=\(v)")
        }, nil)
        IOHIDManagerScheduleWithRunLoop(disco, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let r = IOHIDManagerOpen(disco, IOOptionBits(kIOHIDOptionsTypeNone))
        print("DISCOVER: open result \(r)")
    }

    func stop() {
        if let manager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        eventTap = nil
    }

    private func dbg(_ message: String) {
        let line = "\(CFAbsoluteTimeGetCurrent()) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let path = "/tmp/naga-debug.log"
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: path, contents: data)
        }
    }

    private func handleInput(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(value)
        dbg("handleInput: usagePage=\(String(format: "0x%02X", usagePage)) usage=\(String(format: "0x%02X", usage)) intValue=\(intValue)")

        if usagePage == 0x01 {
            // One-shot pulses (no held-state) — routed through the same onButtonPressed/mapping
            // pipeline as every other button now that these two are customizable instead of a
            // hardwired layer toggle.
            guard intValue == 1, let rawCode = Self.dpiUsageToRawCode[usage] else { return }
            DispatchQueue.main.async { self.onButtonPressed?(rawCode) }
            return
        }

        guard usagePage == 0x07, let label = Self.usageToLabel[usage] else { return }
        if intValue == 1 {
            guard !heldUsages.contains(usage) else { return } // already down — swallow the repeat
            heldUsages.insert(usage)
        } else {
            heldUsages.remove(usage)
            return
        }
        dbg("handleInput: matched label=\(label)")
        if let keyCode = Self.usageToKeyCode[usage] { markForSwallow(keyCode) }
        DispatchQueue.main.async {
            if let number = Device.button(for: label)?.number {
                self.clearFiredWorkItem?.cancel()
                self.lastFiredButton = number
                let work = DispatchWorkItem { [weak self] in self?.lastFiredButton = nil }
                self.clearFiredWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
            }
            self.onButtonPressed?(label)
        }
    }

    // MARK: - Swallow stray keystrokes
    // Non-exclusive open means the OS keyboard stack independently turns these same usage codes
    // into real keydown/keyup CGEvents on whatever app has focus. We already know a button fired
    // (handleInput above), so mark its virtual keycode and swallow the very next matching CGEvent
    // pair here instead of letting it leak into the focused app.

    private func markForSwallow(_ keyCode: CGKeyCode) {
        pendingSwallow[keyCode] = CFAbsoluteTimeGetCurrent()
    }

    private func takeSwallow(_ keyCode: CGKeyCode) -> Bool {
        guard let markedAt = pendingSwallow[keyCode] else { return false }
        pendingSwallow.removeValue(forKey: keyCode)
        return CFAbsoluteTimeGetCurrent() - markedAt <= swallowTTL
    }

    private func setupEventTap() {
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passRetained(event) }
                let this = Unmanaged<NagaHIDManager>.fromOpaque(context).takeUnretainedValue()
                return this.handleTap(type: type, event: event)
            },
            userInfo: selfPtr
        ) else {
            NSLog("NagaHIDManager: failed to create CGEventTap — is Accessibility granted?")
            return
        }
        eventTap = tap
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handleTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type.rawValue == CGEventType.tapDisabledByTimeout.rawValue || type.rawValue == CGEventType.tapDisabledByUserInput.rawValue {
            dbg("handleTap: tap disabled (type=\(type.rawValue)) — re-enabling")
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passRetained(event)
        }
        guard type == .keyDown || type == .keyUp else { return Unmanaged.passRetained(event) }
        let keyCode = CGKeyCode(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        dbg("handleTap: type=\(type == .keyDown ? "down" : "up") keyCode=\(keyCode) pendingSwallow=\(pendingSwallow.keys) swallowedKeyUp=\(swallowedKeyUp)")
        if type == .keyDown {
            if takeSwallow(keyCode) {
                swallowedKeyUp.insert(keyCode)
                dbg("handleTap: SWALLOWED keydown \(keyCode)")
                return nil
            }
        } else if swallowedKeyUp.remove(keyCode) != nil {
            dbg("handleTap: SWALLOWED keyup \(keyCode)")
            return nil
        }
        return Unmanaged.passRetained(event)
    }

    // MARK: - Inject

    private func flagMask(_ names: [ModifierFlag]?) -> CGEventFlags {
        var mask: CGEventFlags = []
        for name in names ?? [] {
            switch name {
            case .cmd: mask.insert(.maskCommand)
            case .shift: mask.insert(.maskShift)
            case .ctrl: mask.insert(.maskControl)
            case .option: mask.insert(.maskAlternate)
            }
        }
        return mask
    }

    private func post(_ keyCode: Int, down: Bool, flags: CGEventFlags) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: down) else { return }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    private func postMouse(_ type: CGEventType, button: CGMouseButton, buttonNumber: Int64? = nil) {
        let loc = CGEvent(source: nil)?.location ?? .zero
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: loc, mouseButton: button) else { return }
        if let n = buttonNumber { event.setIntegerValueField(.mouseEventButtonNumber, value: n) }
        event.post(tap: .cghidEventTap)
    }

    func dispatch(_ action: Action) {
        NSLog("DEBUG dispatch: kind=\(action.kind) keyCode=\(String(describing: action.keyCode)) appName=\(String(describing: action.appName))")
        switch action.kind {
        case .key:
            guard let keyCode = action.keyCode else { return }
            let flags = flagMask(action.flags)
            if let extra = action.extraKeyDown { post(extra, down: true, flags: []) }
            post(keyCode, down: true, flags: flags)
            post(keyCode, down: false, flags: flags)
            if let extra = action.extraKeyUp { post(extra, down: false, flags: []) }
        case .mouse:
            guard let button = action.button else { return }
            switch button {
            case .left:
                postMouse(.leftMouseDown, button: .left); postMouse(.leftMouseUp, button: .left)
            case .right:
                postMouse(.rightMouseDown, button: .right); postMouse(.rightMouseUp, button: .right)
            case .middle:
                postMouse(.otherMouseDown, button: .center, buttonNumber: 2); postMouse(.otherMouseUp, button: .center, buttonNumber: 2)
            case .back:
                postMouse(.otherMouseDown, button: .center, buttonNumber: 3); postMouse(.otherMouseUp, button: .center, buttonNumber: 3)
            case .forward:
                postMouse(.otherMouseDown, button: .center, buttonNumber: 4); postMouse(.otherMouseUp, button: .center, buttonNumber: 4)
            }
        case .macro:
            runMacro(action.steps ?? [], index: 0)
        case .launch:
            guard let appName = action.appName else { NSLog("DEBUG dispatch: .launch had no appName"); return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", appName]
            do {
                try process.run()
                NSLog("DEBUG dispatch: launched 'open -a \(appName)' pid=\(process.processIdentifier)")
            } catch {
                NSLog("DEBUG dispatch: FAILED to launch 'open -a \(appName)': \(error)")
            }
        case .layerToggle:
            guard let target = action.targetLayer else { return }
            activeLayer = activeLayer == target ? .base : target
        }
    }

    private func runMacro(_ steps: [MacroStep], index: Int) {
        guard index < steps.count else { return }
        let step = steps[index]
        post(step.keyCode, down: true, flags: flagMask(step.flags))
        post(step.keyCode, down: false, flags: flagMask(step.flags))
        let delay = Double(step.delayMs ?? 60) / 1000.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.runMacro(steps, index: index + 1)
        }
    }
}
