// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Protokoll portiert aus deonspengler/akp02 v2.0.0 (akp02/__init__.py),
// reverse-engineered von Deon Spengler. Nur Vollbilder; Teilbilder mit
// ihrer Farbausrichtungsregel werden bewusst nicht unterstützt.

import Foundation

public enum AKP02Protocol {
    public static let vendorID = 0x0300
    public static let productID = 0x3017
    public static let reportSize = 1024
    public static let longSide = 1920
    public static let shortSide = 462

    public static func screenOn() -> [UInt8] { command("DIS") }
    public static func heartbeat() -> [UInt8] { command("CONNECT") }
    public static func commit() -> [UInt8] { command("STP") }

    public static func brightness(_ percent: Int) -> [UInt8] {
        command("LIG", params: [UInt8(min(max(percent, 0), 100))])
    }

    /// 32-Byte-Header einer Bildübertragung; alle Koordinaten 0 = ganzes Panel.
    public static func fullFrameHeader(jpegLength: Int) -> [UInt8] {
        var h = [UInt8](repeating: 0, count: 32)
        h.replaceSubrange(0..<3, with: Array("CRT".utf8))
        h.replaceSubrange(5..<8, with: Array("DRA".utf8))
        let total = UInt32(jpegLength + 0x20)
        h[8] = UInt8((total >> 24) & 0xFF)
        h[9] = UInt8((total >> 16) & 0xFF)
        h[10] = UInt8((total >> 8) & 0xFF)
        h[11] = UInt8(total & 0xFF)
        h[12] = 0xB1
        return h
    }

    /// Header + JPEG in 1024-Byte-Reports, danach der Commit (`STP`).
    public static func fullFrameReports(jpeg: [UInt8]) -> [[UInt8]] {
        let payload = fullFrameHeader(jpegLength: jpeg.count) + jpeg
        var reports: [[UInt8]] = []
        var offset = 0
        while offset < payload.count {
            let end = min(offset + reportSize, payload.count)
            reports.append(pad(Array(payload[offset..<end])))
            offset = end
        }
        reports.append(commit())
        return reports
    }

    static func command(_ mnemonic: String, params: [UInt8] = []) -> [UInt8] {
        pad(Array("CRT".utf8) + [0, 0] + Array(mnemonic.utf8) + [0, 0] + params)
    }

    static func pad(_ bytes: [UInt8]) -> [UInt8] {
        precondition(bytes.count <= reportSize, "Report zu lang")
        return bytes + [UInt8](repeating: 0, count: reportSize - bytes.count)
    }
}
