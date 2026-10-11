// switch2-sample — minimal user-space "driver" for the Switch 2 Pro Controller.
//
//  1. Find the USB device in the IORegistry and its vendor interface (#1)
//  2. Open that interface with IOUSBHost and send the init sequence (bulk OUT)
//  3. The controller then streams HID input report 0x09 on interface #0,
//     which macOS' built-in HID driver already owns -> read it non-exclusively
//     with IOHIDManager and print buttons / sticks.
//
// Protocol: https://github.com/ndeadly/switch2_controller_research
// Init sequence follows SDL3 src/joystick/hidapi/SDL_hidapi_switch2.c (zlib).

import Foundation
import IOKit
import IOKit.hid
import USBBulk

let vendorID = 0x057E          // Nintendo
let productID = 0x2069         // Pro Controller 2
let commandInterface = 1       // vendor class (0xFF) interface
let bulkOut: UInt8 = 0x02
let bulkIn: UInt8 = 0x82

// MARK: - IORegistry helpers

func intProperty(_ entry: io_registry_entry_t, _ key: String) -> Int? {
    IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
        .takeRetainedValue() as? Int
}

func next(_ iterator: io_iterator_t) -> io_object_t? {
    let obj = IOIteratorNext(iterator)
    return obj == 0 ? nil : obj
}

/// Returns the IOUSBHostInterface #1 of the first connected Pro Controller 2.
/// NOTE: match by class only and compare VID/PID in code. Putting numeric
/// idVendor/idProduct into the matching dictionary did not match in practice
/// (the registry compares the OSNumber size as well).
func findCommandInterface() -> io_service_t? {
    var devices: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"),
                                       &devices) == KERN_SUCCESS else { return nil }
    defer { IOObjectRelease(devices) }

    while let device = next(devices) {
        defer { IOObjectRelease(device) }
        guard intProperty(device, "idVendor") == vendorID,
              intProperty(device, "idProduct") == productID else { continue }

        var children: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(device, kIOServicePlane, &children) == KERN_SUCCESS else { continue }
        defer { IOObjectRelease(children) }
        while let child = next(children) {
            if IOObjectConformsTo(child, "IOUSBHostInterface") != 0,
               intProperty(child, "bInterfaceNumber") == commandInterface {
                return child  // caller releases
            }
            IOObjectRelease(child)
        }
    }
    return nil
}

// MARK: - Commands

/// 8-byte header: [cmd, 0x91 (host->device), 0x00 (USB), subcmd, 0x00, dataLen, 0x00, 0x00] + data
func command(_ cmd: UInt8, _ sub: UInt8, _ data: [UInt8] = []) -> [UInt8] {
    [cmd, 0x91, 0x00, sub, 0x00, UInt8(data.count), 0x00, 0x00] + data
}

let initSequence: [(String, [UInt8])] = [
    ("07/01",                command(0x07, 0x01)),
    ("feature mask",         command(0x0C, 0x02, [0x27, 0, 0, 0])),
    ("11/01",                command(0x11, 0x01)),
    ("vibration data",       command(0x0A, 0x08, [0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
                                                  0xFF, 0x35, 0x00, 0x46, 0x00, 0x00, 0x00, 0x00,
                                                  0x00, 0x00, 0x00, 0x00])),
    ("enable features",      command(0x0C, 0x04, [0x27, 0, 0, 0])),
    ("01/0C",                command(0x01, 0x0C)),
    ("01/01",                command(0x01, 0x01)),
    // Report 0x09 is described by the HID report descriptor as a standard
    // Game Pad, so macOS' HID stack can parse it as-is.
    ("select report 0x09",   command(0x03, 0x0A, [0x09, 0, 0, 0])),
    ("initialise USB",       command(0x03, 0x0D, [0x01, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])),
    ("player LED 1",         command(0x09, 0x07, [0x01, 0, 0, 0, 0, 0, 0, 0])),
]

func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined(separator: " ") }

func initialiseController() -> Bool {
    // Interfaces are published a little after the device; retry for ~5 s.
    var service: io_service_t?
    for _ in 0..<20 {
        service = findCommandInterface()
        if service != nil { break }
        Thread.sleep(forTimeInterval: 0.25)
    }
    guard let service else {
        print("Pro Controller 2 (057E:2069) が見つかりません。USB-C で接続してください。")
        return false
    }
    defer { IOObjectRelease(service) }

    let iface: USBBulkInterface
    do {
        iface = try USBBulkInterface(service: service, outEndpoint: bulkOut, inEndpoint: bulkIn)
    } catch {
        print("インターフェース #1 を開けません: \(error.localizedDescription)")
        return false
    }
    defer { iface.close() }

    for (label, bytes) in initSequence {
        do {
            let response = [UInt8](try iface.sendCommand(Data(bytes), maxResponseLength: 64, timeout: 0.3))
            print("→ \(label.padding(toLength: 20, withPad: " ", startingAt: 0)) ← \(hex(Array(response.prefix(8))))")
        } catch {
            print("→ \(label) 送信失敗: \(error.localizedDescription)")
            return false
        }
    }
    return true
}

// MARK: - HID input (report 0x09)

let buttonNames = [
    "B", "A", "Y", "X", "R", "ZR", "+", "RS",            // byte 2
    "↓", "→", "←", "↑", "L", "ZL", "−", "LS",            // byte 3
    "HOME", "CAP", "GR", "GL", "C", "", "", "",           // byte 4
]
var lastButtons: UInt32 = .max

func handleReport(_ r: [UInt8]) {
    // USB HID delivers the report ID first: [0x09, counter, power, b0, b1, b2, LX/LY(3), RX/RY(3), ...]
    guard r.count >= 12, r[0] == 0x09 else { return }
    let buttons = UInt32(r[3]) | UInt32(r[4]) << 8 | UInt32(r[5]) << 16
    guard buttons != lastButtons else { return }   // print on change only
    lastButtons = buttons

    // Two 12-bit values packed into 3 bytes.
    func stick(_ i: Int) -> (Int, Int) {
        (Int(r[i]) | Int(r[i + 1] & 0x0F) << 8, Int(r[i + 1] >> 4) | Int(r[i + 2]) << 4)
    }
    let pressed = buttonNames.enumerated()
        .filter { buttons & (1 << UInt32($0.offset)) != 0 && !$0.element.isEmpty }
        .map(\.element)
    let (lx, ly) = stick(6), (rx, ry) = stick(9)
    print("buttons: \(pressed.isEmpty ? "-" : pressed.joined(separator: " "))  L(\(lx),\(ly)) R(\(rx),\(ry))")
}

let reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 128)
// Keep a strong reference for the lifetime of the process.
let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

func startHID() {
    IOHIDManagerSetDeviceMatching(manager, [
        kIOHIDVendorIDKey: vendorID,
        kIOHIDProductIDKey: productID,
        kIOHIDPrimaryUsagePageKey: kHIDPage_GenericDesktop,
        kIOHIDPrimaryUsageKey: kHIDUsage_GD_GamePad,
    ] as CFDictionary)

    IOHIDManagerRegisterDeviceMatchingCallback(manager, { _, _, _, device in
        print("HID ゲームパッドを検出")
        IOHIDDeviceRegisterInputReportCallback(device, reportBuffer, 128, { _, _, _, _, _, report, length in
            handleReport(Array(UnsafeBufferPointer(start: report, count: length)))
        }, nil)
    }, nil)

    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    // Non-exclusive open: other apps (games, Steam) can still read the device.
    let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    if result != kIOReturnSuccess {
        print(String(format: "IOHIDManagerOpen 失敗 0x%08X", result))
    }
}

// MARK: - main

startHID()
guard initialiseController() else { exit(1) }
print("初期化完了。ボタンを押すと表示されます（Ctrl-C で終了）")
CFRunLoopRun()
