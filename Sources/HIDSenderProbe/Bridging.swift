import Foundation
import IOKit
import IOKit.hid

// Private IOHIDEventSystemClient bridging via dlsym — no public header ships for this API (it's
// what lets BetterTouchTool/Hammerspoon-style tools attribute a HID event to a specific device,
// unlike the public IOHIDManager path our main app uses, which is not device-scoped for the
// NX_SYSDEFINED-style button events we care about). Resolved at runtime against the process's own
// loaded images rather than a bridging header, since a bare SwiftPM executable target has no slot
// for a C shim target.

typealias EventSystemClientRef = UnsafeMutableRawPointer
typealias ServiceClientRef = UnsafeMutableRawPointer
typealias HIDEventRef = UnsafeMutableRawPointer

typealias FnCreate = @convention(c) (CFAllocator?) -> EventSystemClientRef?
typealias FnCreateWithType = @convention(c) (CFAllocator?, Int32) -> EventSystemClientRef?
typealias FnScheduleRunLoop = @convention(c) (EventSystemClientRef, CFRunLoop, CFString) -> Void
typealias FnSetMatching = @convention(c) (EventSystemClientRef, CFDictionary?) -> Void
typealias FnCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, ServiceClientRef?, HIDEventRef?) -> Void
typealias FnRegisterCallback = @convention(c) (EventSystemClientRef, FnCallback?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
typealias FnGetSenderID = @convention(c) (HIDEventRef) -> UInt64
typealias FnGetType = @convention(c) (HIDEventRef) -> Int32
typealias FnServiceCopyProperty = @convention(c) (ServiceClientRef, CFString) -> Unmanaged<CFTypeRef>?

func resolveSymbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String, as type: T.Type) -> T? {
    guard let ptr = dlsym(handle, name) else {
        FileHandle.standardError.write("MISSING SYMBOL: \(name)\n".data(using: .utf8)!)
        return nil
    }
    return unsafeBitCast(ptr, to: type)
}

// Assigned once in main.swift before the client is scheduled — genuine module-level globals so the
// @convention(c) callback below (which cannot capture local state) can reach them.
var g_getSenderID: FnGetSenderID!
var g_getType: FnGetType!
var g_serviceCopyProperty: FnServiceCopyProperty!

let hidEventCallback: FnCallback = { _, refcon, service, event in
    guard let event else { return }
    let senderID = g_getSenderID(event)
    let type = g_getType(event)
    let phase = refcon.map { Int(bitPattern: $0) } ?? -1
    var product = "?"
    if let service, let cf = g_serviceCopyProperty(service, kIOHIDProductKey as CFString) {
        product = (cf.takeRetainedValue() as? String) ?? "?"
    }
    print(String(format: "%.3f  phase=%d  sender=0x%016llX  type=%2d  product=%@",
                 Date().timeIntervalSince1970, phase, senderID, type, product))
}
