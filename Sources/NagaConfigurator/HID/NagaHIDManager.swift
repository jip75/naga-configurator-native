import Foundation
import IOKit
import IOKit.hid
import CoreGraphics
import AppKit
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
    // Previously a dispatch failure (e.g. the Mission Control button's `open -a` call failing)
    // only went to the debug log file — invisible in the actual running app, so a real failure
    // looked identical to a button silently doing nothing. Surfaced to the UI instead.
    @Published var lastError: String?

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

    // Rear top button ("topB"): isolated live 2026-09-10 to a fixed-usage array report on this
    // composite device's third HID interface (907 elements) — reportID=5, cookie 891, usagePage 0x01,
    // usage 0xFFFFFFFF (an undefined/array slot per the device's own descriptor). That interface never
    // reports anything else (confirmed: every single element event captured off it across 5 isolated
    // presses fell inside reportID=5's cookie range 891-896) — cookie 891 fires exactly once per raw
    // report, one per burst, so it's used as the single per-press marker. The report's byte VALUES
    // are NOT usable here — they cycle unpredictably between presses (garbage int-cast on cookie 891
    // itself, and a rotating small set of raw bytes on 893-896) — only the report firing at all, on
    // this cookie, is the stable signal. Debounced because a single physical press can emit this
    // report more than once (observed ~1.6x per press across 5 test presses).
    private var lastRearButtonFire: CFAbsoluteTime = 0
    private let rearButtonDebounce: CFAbsoluteTime = 0.2
    // Front top button ("topA", physically the HyperShift button) lives on the same shared
    // array report as the rear button — same discriminator pattern, different payload and its
    // own debounce clock so a HyperShift press can't eat the rear button's debounce window.
    private var lastTopAFire: CFAbsoluteTime = 0
    private let topADebounce: CFAbsoluteTime = 0.2
    // Scroll Click ("scrollClick") shares the exact same array report/cookie/debounce-worthy
    // repeat behavior as topA/topB above — own clock so it can't eat their debounce window either.
    private var lastScrollClickFire: CFAbsoluteTime = 0
    private let scrollClickDebounce: CFAbsoluteTime = 0.2
    // Wheel tilt ("tiltLeft"/"tiltRight"): isolated live 2026-09-18 via NAGA_DISCOVER on
    // usagePage=0xFF00 usage=0x40 reportID=0 cookie=102 — an encoder-style vendor channel that
    // re-fires repeatedly in ~256-step increments for as long as the wheel stays tilted (confirmed:
    // an isolated right-only capture produced purely negative values -255..-512; a left-heavy
    // capture produced the positive counterpart), unlike topA/topB/scrollClick's single-report-
    // per-press array. Sign gives direction; magnitude is not used. This device is opened non-
    // exclusively, so the OS's own default HID handling processes the same raw report in parallel
    // and drives native horizontal scroll — that's expected, not a conflict, and out of this app's
    // control (same caveat as scrollClick's system middle-click, see below). Not yet pinned to a
    // specific interface the way rearButtonDevice is for cookie 891 — only one device was observed
    // emitting this cookie during capture, but per this file's cookie-891 lesson, cookie 102 may not
    // be globally unique on this composite device either; revisit if a false-fire is ever reported.
    private var lastTiltLeftFire: CFAbsoluteTime = 0
    private var lastTiltRightFire: CFAbsoluteTime = 0
    private let tiltDebounce: CFAbsoluteTime = 0.35
    // reportID=5/cookie=891 is NOT globally unique on this composite device — cookies are assigned
    // per-interface, so the DPI-shift buttons flanking the wheel (their own, still-unmapped
    // interface) can independently land on the same reportID/cookie pair and falsely fire topB
    // (confirmed live 2026-09-11: the DPI-speed button next to the wheel launched Screenshot too).
    // Pin the discriminator to the specific 907-element interface it was isolated on, the same way
    // startDiscoveryManager already scopes its prints by device identity via CFEqual.
    private var rearButtonDevice: IOHIDDevice?

    private static let usageToLabel: [UInt32: String] = [
        0x1E: "1", 0x1F: "2", 0x20: "3", 0x21: "4", 0x22: "5", 0x23: "6",
        0x24: "7", 0x25: "8", 0x26: "9", 0x27: "0", 0x2D: "-", 0x2E: "=",
    ]
    private static let usageToKeyCode: [UInt32: CGKeyCode] = [
        0x1E: 0x12, 0x1F: 0x13, 0x20: 0x14, 0x21: 0x15, 0x22: 0x17, 0x23: 0x16,
        0x24: 0x1A, 0x25: 0x1C, 0x26: 0x19, 0x27: 0x1D, 0x2D: 0x1B, 0x2E: 0x18,
    ]
    // There is no separate DPI-speed button pair. 2026-09-11 isolated NAGA_DISCOVER capture (reset
    // to a known array state via one rear-button press, then one clean press of each target,
    // repeated for both) showed the "cursor slows down" / "cursor speeds up" presses produce the
    // EXACT SAME reportID=5/cookie=891 payloads as topB (0C 80) and topA (19 00) respectively — no
    // third usage-page/reportID signal appeared in either capture despite the discovery manager
    // matching the whole device with no usage filter. The cursor-speed change is this mouse's own
    // onboard DPI-stage firmware reacting to those two physical buttons independently of the HID
    // report this app reads — it fires alongside topA/topB's dispatch, not instead of it, and
    // cannot be intercepted, remapped, or disabled from software.
    //
    // CORRECTION 2026-09-11: usage 0x02 was previously identified as a distinct "bottom-mounted
    // button" (separate cookie from usage 0x01) and wired to launch Mission Control. Live evidence
    // this session disproves that — usage 0x02 fires at completely ordinary human clicking cadence,
    // hundreds of times during normal mouse use (including clicks made to operate this app's own
    // UI), not the rare firing pattern an obscure underside button would show. UsagePage 0x09 is
    // the standard HID Button page — usage 1/2/3 are simply this mouse's left/right/middle buttons
    // (sequential usage codes, each with its own cookie, exactly as any multi-button mouse reports
    // them — the distinct-cookie observation that grounded the old theory doesn't imply a distinct
    // physical control). Dispatching Mission Control on it was hijacking ordinary clicks system-wide,
    // including inside this app's own hotspot selection. Left empty — do not remap usage 0x02
    // without new isolated-capture evidence that it's actually a separate control.
    private static let dpiUsageToRawCode: [UInt32: String] = [:]

    func start() {
        guard manager == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager

        // No usagePage/usage restriction here — the Front top button ("topA") is still unmapped and
        // its real collection is unknown (page 0x09 was ruled out — that's this mouse's own right-
        // click), and the Rear top button ("topB") lives on a distinct top-level collection (array
        // report, reportID=5, usagePage 0x01) from the keyboard-page one (0x01/0x06 fixed-usage) — a
        // device-level usage filter would drop whichever collection it doesn't name before handleInput
        // ever sees it. Matching vendor+product only (same as the NAGA_DISCOVER manager below) lets
        // every collection through; handleInput already discriminates by usagePage/reportID/cookie
        // per-element, so this is safe.
        let matchDict: [String: Any] = [
            kIOHIDVendorIDKey: Int(Device.vendorID),
            kIOHIDProductIDKey: Int(Device.productID),
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

        if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
            rearButtonDevice = devices.first { d in
                let elements = IOHIDDeviceCopyMatchingElements(d, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] ?? []
                return elements.count == 907
            }
            if rearButtonDevice == nil {
                NSLog("NagaHIDManager: could not identify the 907-element rear-button interface — topB will not fire")
            }
        }

        if ProcessInfo.processInfo.environment["NAGA_DISCOVER"] != nil {
            setvbuf(stdout, nil, _IONBF, 0) // print() is fully buffered off a real tty; a kill loses everything unflushed
        }

        setupEventTap()

        if ProcessInfo.processInfo.environment["NAGA_DISCOVER"] != nil {
            startDiscoveryManager()
        }
    }

    private var discoveryManager: IOHIDManager?
    // All 4 interfaces of this composite device report the SAME kIOHIDLocationIDKey (confirmed live
    // 2026-09-10 — locationID is useless as a discriminator here), so device identity is tracked by
    // CFEqual against the enumeration-order array instead. Only valid within one capture run — Set's
    // iteration order isn't guaranteed stable across launches, so index-to-device-kind (which one is
    // the 907-element interface, etc.) must be re-read from the "DISCOVER: devN primaryUsage..." dump
    // at the top of each new log, never assumed from a prior run.
    private var discoveryDevices: [IOHIDDevice] = []
    private func startDiscoveryManager() {
        let disco = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        discoveryManager = disco
        let matchDict: [String: Any] = [
            kIOHIDVendorIDKey: Int(Device.vendorID),
            kIOHIDProductIDKey: Int(Device.productID),
        ]
        IOHIDManagerSetDeviceMatching(disco, matchDict as CFDictionary)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(disco, { context, _, _, value in
            guard let context else { return }
            let this = Unmanaged<NagaHIDManager>.fromOpaque(context).takeUnretainedValue()
            let element = IOHIDValueGetElement(value)
            let up = IOHIDElementGetUsagePage(element)
            let u = IOHIDElementGetUsage(element)
            // Skip continuous X/Y motion (0x01/0x30,0x31) — pure noise for button discovery.
            // 0xFF00 (vendor page) is NOT filtered: the top buttons are believed to report there.
            if up == 0x01 && (u == 0x30 || u == 0x31) { return }
            let reportID = IOHIDElementGetReportID(element)
            let cookie = IOHIDElementGetCookie(element)
            let device = IOHIDElementGetDevice(element)
            let index = this.discoveryDevices.firstIndex(where: { CFEqual($0, device) })
            let devTag = index.map { "dev\($0)" } ?? "dev?"
            if reportID == 5 {
                // Array-report slot (rear button's isolated signal) — the naive int cast has proven
                // unreliable here (misreads element bit-width, garbage on cookie 891), so dump the
                // actual bytes instead of trusting IOHIDValueGetIntegerValue.
                let length = IOHIDValueGetLength(value)
                let ptr = IOHIDValueGetBytePtr(value)
                let hex = (0..<length).map { String(format: "%02X", ptr[$0]) }.joined(separator: " ")
                print("DISCOVER[\(devTag)] reportID=5 cookie=\(cookie) usagePage=\(String(format: "0x%02X", up)) usage=\(String(format: "0x%02X", u)) length=\(length) bytes=[\(hex)]")
                return
            }
            let v = IOHIDValueGetIntegerValue(value)
            print("DISCOVER[\(devTag)] usagePage=\(String(format: "0x%02X", up)) usage=\(String(format: "0x%02X", u)) reportID=\(reportID) cookie=\(cookie) value=\(v)")
        }, selfPtr)
        IOHIDManagerScheduleWithRunLoop(disco, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let r = IOHIDManagerOpen(disco, IOOptionBits(kIOHIDOptionsTypeNone))
        print("DISCOVER: open result \(r)")
        if let devices = IOHIDManagerCopyDevices(disco) as? Set<IOHIDDevice> {
            print("DISCOVER: \(devices.count) device(s) enumerated")
            let orderedDevices = Array(devices)
            discoveryDevices = orderedDevices
            for (index, d) in orderedDevices.enumerated() {
                let up = IOHIDDeviceGetProperty(d, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? -1
                let u = IOHIDDeviceGetProperty(d, kIOHIDPrimaryUsageKey as CFString) as? Int ?? -1
                let elements = IOHIDDeviceCopyMatchingElements(d, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] ?? []
                print("DISCOVER: dev\(index) primaryUsagePage=\(String(format: "0x%02X", up)) primaryUsage=\(String(format: "0x%02X", u)) elementCount=\(elements.count)")
                for e in elements {
                    let eup = IOHIDElementGetUsagePage(e)
                    let eu = IOHIDElementGetUsage(e)
                    print("DISCOVER:   dev\(index) element usagePage=\(String(format: "0x%02X", eup)) usage=\(String(format: "0x%02X", eu)) reportID=\(IOHIDElementGetReportID(e)) cookie=\(IOHIDElementGetCookie(e))")
                }
            }
        }
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

    func debugLog(_ message: String) { dbg(message) }

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
        // Continuous X/Y motion (0x01/0x30,0x31), the scroll wheel (0x01/0x38), and a vendor
        // telemetry channel (0xFF00/0x40) never match any branch below — pure noise here, same as
        // the discovery manager already filters motion. But dbg() below does synchronous file I/O
        // (open/seek/write/close) per call, and all three report at a high rate — logging every
        // sample flooded disk I/O on the main run loop (139MB/2M lines observed 2026-09-11),
        // dragging cursor movement and risking the CGEventTap's timeout-triggered auto-disable.
        // Bail before that call for all three; every other usage page is low-frequency enough
        // (button presses, not continuous) to log safely.
        if usagePage == 0x01 && (usage == 0x30 || usage == 0x31 || usage == 0x38) { return }
        if usagePage == 0xFF00 && usage == 0x40 {
            guard IOHIDElementGetCookie(element) == 102 else { return }
            let tiltValue = IOHIDValueGetIntegerValue(value)
            let now = CFAbsoluteTimeGetCurrent()
            if tiltValue < 0 {
                guard now - lastTiltRightFire > tiltDebounce else { return }
                lastTiltRightFire = now
                dbg("handleInput: wheel tilt right (cookie=102 value=\(tiltValue))")
                DispatchQueue.main.async { self.onButtonPressed?("tiltRight") }
            } else if tiltValue > 0 {
                guard now - lastTiltLeftFire > tiltDebounce else { return }
                lastTiltLeftFire = now
                dbg("handleInput: wheel tilt left (cookie=102 value=\(tiltValue))")
                DispatchQueue.main.async { self.onButtonPressed?("tiltLeft") }
            }
            return
        }
        let intValue = IOHIDValueGetIntegerValue(value)
        dbg("handleInput: usagePage=\(String(format: "0x%02X", usagePage)) usage=\(String(format: "0x%02X", usage)) intValue=\(intValue)")

        // This 3-button top cluster (Scroll Click / HyperShift / rear button) shares ONE array
        // report (reportID=5, cookie=891) on the 907-element interface — cookie 891 firing at all
        // is NOT unique to the rear button, it fires on every value CHANGE across the whole cluster
        // (confirmed live 2026-09-11: HyperShift and Scroll Click both land on the same cookie, each
        // with their own fixed 2-byte payload; the array only reports a fresh value on a transition,
        // which is also why repeat-pressing the same one of these three does nothing until a
        // different one is pressed in between). The payload itself IS the real per-button
        // discriminator — isolated single-press capture identified: rear button = [0C 80],
        // HyperShift = [19 00], Scroll Click = [06 40].
        if usagePage == 0x01, IOHIDElementGetReportID(element) == 5, IOHIDElementGetCookie(element) == 891,
           let rearButtonDevice, CFEqual(IOHIDElementGetDevice(element), rearButtonDevice) {
            let length = IOHIDValueGetLength(value)
            let ptr = IOHIDValueGetBytePtr(value)
            guard length >= 3 else { return }
            if ptr[1] == 0x0C, ptr[2] == 0x80 {
                let now = CFAbsoluteTimeGetCurrent()
                guard now - lastRearButtonFire > rearButtonDebounce else { return }
                lastRearButtonFire = now
                dbg("handleInput: rear button fired (reportID=5 cookie=891 payload=0C80)")
                DispatchQueue.main.async { self.onButtonPressed?("topB") }
            } else if ptr[1] == 0x19, ptr[2] == 0x00 {
                let now = CFAbsoluteTimeGetCurrent()
                guard now - lastTopAFire > topADebounce else { return }
                lastTopAFire = now
                dbg("handleInput: front top button fired (reportID=5 cookie=891 payload=1900)")
                DispatchQueue.main.async { self.onButtonPressed?("topA") }
            } else if ptr[1] == 0x06, ptr[2] == 0x40 {
                // payload 06 40 is Scroll Click. Dispatched the same as topA/topB now that it's
                // customizable — but this fires ALONGSIDE the wheel's standard system middle-click
                // (usagePage 0x09, usage 3), never instead of it: that's a separate HID report this
                // app doesn't own, and exclusive device access to suppress it is a confirmed dead
                // end on this OS (see this file's header comment). See MouseDiagramView's
                // systemHotspots comment for the user-facing version of this caveat.
                let now = CFAbsoluteTimeGetCurrent()
                guard now - lastScrollClickFire > scrollClickDebounce else { return }
                lastScrollClickFire = now
                dbg("handleInput: scroll click fired (reportID=5 cookie=891 payload=0640)")
                DispatchQueue.main.async { self.onButtonPressed?("scrollClick") }
            }
            return
        }

        if usagePage == 0x09 {
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
        // NX_SYSDEFINED (14) is included for NAGA_DISCOVER only: media/consumer-page button presses
        // (like the Naga's top buttons, if they route through the OS's HID Consumer/System event path
        // rather than a raw HID report) surface here, not as keyDown/keyUp.
        let discoverMode = ProcessInfo.processInfo.environment["NAGA_DISCOVER"] != nil
        var mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        if discoverMode { mask |= (1 << 14) }
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
        if type.rawValue == 14 {
            if ProcessInfo.processInfo.environment["NAGA_DISCOVER"] != nil, let ns = NSEvent(cgEvent: event) {
                print("DISCOVER systemDefined subtype=\(ns.subtype.rawValue) data1=\(ns.data1) data2=\(ns.data2)")
            }
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
        dbg("dispatch: kind=\(action.kind) keyCode=\(String(describing: action.keyCode)) appName=\(String(describing: action.appName))")
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
            guard let appName = action.appName else { dbg("dispatch: .launch had no appName"); return }
            let process = Process()
            if appName == "Screenshot" {
                // `open -a Screenshot` only re-focuses the toolbar if it's already running,
                // producing no visible effect on repeat presses. screencapture -i fires a
                // fresh interactive capture every time regardless of prior state.
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-i"]
            } else {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = ["-a", appName]
            }
            do {
                try process.run()
                dbg("dispatch: launched '\(process.executableURL!.path) \(process.arguments!.joined(separator: " "))' pid=\(process.processIdentifier)")
            } catch {
                dbg("dispatch: FAILED to launch '\(appName)': \(error)")
                lastError = "Couldn't open \"\(appName)\": \(error.localizedDescription)"
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
