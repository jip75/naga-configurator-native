import Foundation
import IOKit
import IOKit.hid

// MARK: - Razer vendor HID protocol (DPI write)
//
// SOURCE OF TRUTH: github.com/openrazer/openrazer (GPLv2 Linux kernel HID driver) — read for
// protocol/byte-layout only, nothing copied verbatim; this is a from-scratch Swift
// reimplementation of the wire format. Verified line-by-line against the driver source
// (fetched 2026-09-09):
//   driver/razermouse_driver.h   → `#define USB_DEVICE_ID_RAZER_NAGA_LEFT_HANDED_2020 0x008D`
//                                   This is an EXACT match to this app's own
//                                   `Device.productID` (141 decimal == 0x8D) — not a
//                                   "close sibling" guess, this is the literal device.
//   driver/razercommon.h / .c    → `struct razer_report` is 90 bytes: status(1) +
//                                   transaction_id(1) + remaining_packets(2, BE) +
//                                   protocol_type(1) + data_size(1) + command_class(1) +
//                                   command_id(1) + arguments(80) + crc(1) + reserved(1).
//                                   CRC = XOR of bytes[2..<88] (0-based, half-open).
//                                   Transport: `usb_control_msg_send` with bRequest
//                                   HID_REQ_SET_REPORT (0x09), bmRequestType
//                                   USB_TYPE_CLASS|RECIP_INTERFACE|DIR_OUT (0x21), wValue
//                                   0x0300 (report type 3 = Feature, report ID 0) — i.e. a
//                                   plain HID SET_REPORT(Feature, id 0). Read-back is the
//                                   GET_REPORT mirror (bmRequestType 0xA1, bRequest 0x01,
//                                   same wValue), and a response status byte of 0x02
//                                   (RAZER_CMD_SUCCESSFUL) or 0x01 (RAZER_CMD_BUSY, treated
//                                   as success) means the device accepted the command.
//   driver/razerchromacommon.c   → `razer_chroma_misc_set_dpi_xy()`: command_class 0x04,
//                                   command_id 0x05, data_size 0x07, arguments =
//                                   [varstore, dpiX_hi, dpiX_lo, dpiY_hi, dpiY_lo, 0x00, 0x00].
//                                   Device-side DPI is clamped to 100...45000.
//   driver/razermouse_driver.c   → `razer_attr_write_dpi()`'s switch confirms, specifically
//                                   for `USB_DEVICE_ID_RAZER_NAGA_LEFT_HANDED_2020`, that
//                                   `varstore = VARSTORE` (0x01, i.e. persist to onboard
//                                   memory) and `request.transaction_id.id = 0x1f`.
//
// WHAT IS **NOT** VERIFIED: nothing here has been tried against the real mouse. OpenRazer
// issues that SET_REPORT/GET_REPORT pair as a raw USB control transfer addressed to a specific
// USB interface (wIndex = interface number). On macOS, `IOHIDDeviceSetReport`/
// `IOHIDDeviceGetReport` with `kIOHIDReportTypeFeature` should produce the identical control
// transfer for whichever IOHIDDevice service you call it on — but this app's existing
// NagaHIDManager only ever opens the Generic-Desktop/Mouse collection (usage page 0x01, usage
// 0x06) for *input*. The Feature report used for DPI writes may live on that same interface, or
// on Razer's separate vendor-defined control interface (the Naga exposes several HID
// interfaces). Rather than guess which one, `RazerDPIWriter.setDPI` opens a scoped,
// non-persistent IOHIDManager matched on VID/PID only (no usage filter) so it sees every
// interface the mouse exposes, tries the write + read-back on each one, and reports back exactly
// what happened per interface — so a real result (or a real, honest failure) comes back instead
// of a report that silently vanished into the wrong interface.
enum RazerDPIProtocol {
    static let reportLength = 90
    static let commandClassMisc: UInt8 = 0x04
    static let commandIDSetDPIXY: UInt8 = 0x05
    static let dpiArgLength: UInt8 = 0x07
    /// VARSTORE: persist the DPI to the mouse's onboard memory (vs. NOSTORE/volatile).
    static let varstore: UInt8 = 0x01
    /// Transaction id OpenRazer uses specifically for USB_DEVICE_ID_RAZER_NAGA_LEFT_HANDED_2020
    /// (see razermouse_driver.c's razer_attr_write_dpi). Other Razer mice use 0x3f or 0xff here —
    /// this value is NOT generic across the product line.
    static let transactionID: UInt8 = 0x1F

    static let statusBusy: UInt8 = 0x01
    static let statusSuccessful: UInt8 = 0x02
    static let statusFailure: UInt8 = 0x03

    static let dpiRange: ClosedRange<Int> = 100...45000

    /// Builds the 90-byte razer_report for a "set DPI X/Y" command. `dpiX`/`dpiY` are clamped to
    /// the device's documented range before encoding.
    static func buildSetDPIReport(dpiX: Int, dpiY: Int) -> [UInt8] {
        let x = UInt16(clamping: min(max(dpiX, dpiRange.lowerBound), dpiRange.upperBound))
        let y = UInt16(clamping: min(max(dpiY, dpiRange.lowerBound), dpiRange.upperBound))

        var report = [UInt8](repeating: 0, count: reportLength)
        report[1] = transactionID              // transaction_id.id
        // report[2...3] remaining_packets = 0 (default)
        // report[4] protocol_type = 0 (default)
        report[5] = dpiArgLength                // data_size
        report[6] = commandClassMisc            // command_class
        report[7] = commandIDSetDPIXY           // command_id.id
        report[8] = varstore                    // arguments[0]
        report[9] = UInt8((x >> 8) & 0xFF)      // arguments[1] dpi_x high byte
        report[10] = UInt8(x & 0xFF)            // arguments[2] dpi_x low byte
        report[11] = UInt8((y >> 8) & 0xFF)     // arguments[3] dpi_y high byte
        report[12] = UInt8(y & 0xFF)            // arguments[4] dpi_y low byte
        // arguments[5], arguments[6] = 0 (default)
        report[88] = crc(report)                // crc
        // report[89] reserved = 0 (default)
        return report
    }

    /// XOR of bytes[2..<88] — matches razer_calculate_crc() exactly.
    static func crc(_ report: [UInt8]) -> UInt8 {
        var value: UInt8 = 0
        for i in 2..<88 { value ^= report[i] }
        return value
    }
}

/// Result of trying the DPI-set command against one matched HID interface.
struct DPIWriteAttempt {
    let product: String?
    let usagePage: Int
    let usage: Int
    let setReportResult: IOReturn
    /// Status byte read back from the device's response report (offset 0), if the read-back
    /// itself succeeded. 0x02 = RAZER_CMD_SUCCESSFUL, 0x01 = RAZER_CMD_BUSY (also treated as
    /// success by OpenRazer), 0x03 = RAZER_CMD_FAILURE, nil = read-back failed or wasn't attempted.
    let readBackStatus: UInt8?
    var accepted: Bool {
        setReportResult == kIOReturnSuccess &&
            (readBackStatus == RazerDPIProtocol.statusSuccessful || readBackStatus == RazerDPIProtocol.statusBusy)
    }

    var description: String {
        let statusDesc = readBackStatus.map { String(format: "0x%02X", $0) } ?? "none"
        return "product=\(product ?? "?") usagePage=0x\(String(usagePage, radix: 16)) " +
            "usage=0x\(String(usage, radix: 16)) setReport=\(setReportResult) readBackStatus=\(statusDesc) " +
            "accepted=\(accepted)"
    }
}

/// Sends the DPI-set command to every HID interface the Naga exposes and reports what happened
/// on each one. See the protocol notes above for exactly what is and isn't verified here.
enum RazerDPIWriter {
    /// Synchronous — does real IOKit I/O, call off the main thread.
    static func setDPI(x: Int, y: Int) -> [DPIWriteAttempt] {
        let report = RazerDPIProtocol.buildSetDPIReport(dpiX: x, dpiY: y)

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matchDict: [String: Any] = [
            kIOHIDVendorIDKey: Int(Device.vendorID),
            kIOHIDProductIDKey: Int(Device.productID),
        ]
        IOHIDManagerSetDeviceMatching(manager, matchDict as CFDictionary)

        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            NSLog("RazerDPIWriter: failed to open scanning IOHIDManager (IOReturn %d)", openResult)
            return []
        }
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

        guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !deviceSet.isEmpty else {
            NSLog("RazerDPIWriter: no matching HID interfaces found for VID=%d PID=%d", Device.vendorID, Device.productID)
            return []
        }

        return deviceSet.map { tryWrite(report, to: $0) }
    }

    private static func tryWrite(_ report: [UInt8], to device: IOHIDDevice) -> DPIWriteAttempt {
        let usagePage = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int) ?? 0
        let usage = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int) ?? 0
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String

        let setResult = report.withUnsafeBufferPointer { buf -> IOReturn in
            guard let base = buf.baseAddress else { return kIOReturnError }
            return IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0, base, buf.count)
        }

        guard setResult == kIOReturnSuccess else {
            return DPIWriteAttempt(product: product, usagePage: usagePage, usage: usage,
                                    setReportResult: setResult, readBackStatus: nil)
        }

        var readBuffer = [UInt8](repeating: 0, count: RazerDPIProtocol.reportLength)
        var readLength: CFIndex = readBuffer.count
        let getResult = readBuffer.withUnsafeMutableBufferPointer { buf -> IOReturn in
            guard let base = buf.baseAddress else { return kIOReturnError }
            return IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0, base, &readLength)
        }

        let status: UInt8? = getResult == kIOReturnSuccess ? readBuffer[0] : nil
        return DPIWriteAttempt(product: product, usagePage: usagePage, usage: usage,
                                setReportResult: setResult, readBackStatus: status)
    }
}
