import Foundation
import IOKit
import IOKit.hid

// LOG-ONLY prototype. Do not add dispatch/CGEventPost here — the whole point is proving
// IOHIDEventGetSenderID can tell devices apart BEFORE anything is wired to an action again.
// See Razer-Naga-LeftHanded/2026-09-10_2103_CrossDeviceMisfire-RevertedRecovered/DELTA.md.

setvbuf(stdout, nil, _IONBF, 0)

guard let handle = dlopen(nil, RTLD_NOW) else {
    print("dlopen(nil) failed — cannot search process image for private symbols.")
    exit(1)
}

guard
    let scheduleRunLoop = resolveSymbol(handle, "IOHIDEventSystemClientScheduleWithRunLoop", as: FnScheduleRunLoop.self),
    let setMatching = resolveSymbol(handle, "IOHIDEventSystemClientSetMatching", as: FnSetMatching.self),
    let registerCallback = resolveSymbol(handle, "IOHIDEventSystemClientRegisterEventCallback", as: FnRegisterCallback.self),
    let getSenderID = resolveSymbol(handle, "IOHIDEventGetSenderID", as: FnGetSenderID.self),
    let getType = resolveSymbol(handle, "IOHIDEventGetType", as: FnGetType.self),
    let serviceCopyProperty = resolveSymbol(handle, "IOHIDServiceClientCopyProperty", as: FnServiceCopyProperty.self)
else {
    print("Missing one or more private IOHIDEventSystemClient symbols on this OS build (see stderr) — aborting.")
    exit(1)
}

g_getSenderID = getSenderID
g_getType = getType
g_serviceCopyProperty = serviceCopyProperty

// Plain IOHIDEventSystemClientCreate() seemed to only surface one narrow, ~1Hz heartbeat-looking
// sender no matter what buttons were pressed — that smells like a restricted default client type,
// not a permissions block (no TCC popup fired). IOHIDEventSystemClientCreateWithType lets a client
// ask for a specific type (Monitor/Admin/Passive/etc in leaked headers, exact ordinals undocumented
// and version-dependent) — run several candidate ordinals CONCURRENTLY, each tagged via refcon, so
// one human button-mashing pass tests all of them instead of needing a capture round per candidate.
let create = resolveSymbol(handle, "IOHIDEventSystemClientCreate", as: FnCreate.self)
let createWithType = resolveSymbol(handle, "IOHIDEventSystemClientCreateWithType", as: FnCreateWithType.self)

var started = 0
if let create, let plain = create(nil) {
    setMatching(plain, nil)
    registerCallback(plain, hidEventCallback, nil, UnsafeMutableRawPointer(bitPattern: 999))
    scheduleRunLoop(plain, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    print("phase=999 -> plain IOHIDEventSystemClientCreate() [[known: heartbeat-only]]")
    started += 1
} else {
    print("phase=999 -> plain Create() unavailable")
}

if let createWithType {
    for t: Int32 in 0...4 {
        guard let client = createWithType(nil, t) else {
            print("phase=\(t) -> CreateWithType(\(t)) returned nil")
            continue
        }
        setMatching(client, nil)
        registerCallback(client, hidEventCallback, nil, UnsafeMutableRawPointer(bitPattern: Int(t)))
        scheduleRunLoop(client, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        print("phase=\(t) -> CreateWithType(\(t)) started")
        started += 1
    }
} else {
    print("IOHIDEventSystemClientCreateWithType symbol not found on this OS build.")
}

guard started > 0 else {
    print("No client variant started — aborting.")
    exit(1)
}

print("\nHIDSenderProbe running \(started) client variant(s) concurrently — log-only, no dispatch.")
print("Keep cycling ALL THREE buttons on a loop for the whole window: Naga rear -> MX thumb -> MX top-right -> repeat.")
print("Each line's 'phase=' tags which client variant saw it.\n")

CFRunLoopRun()
