import XCTest
@testable import StatusCore

final class AKP02ProtocolTests: XCTestCase {
    private func ascii(_ s: String) -> [UInt8] { Array(s.utf8) }

    func testCommandsArePaddedTo1024() {
        for report in [AKP02Protocol.screenOn(), AKP02Protocol.heartbeat(),
                       AKP02Protocol.commit(), AKP02Protocol.brightness(50)] {
            XCTAssertEqual(report.count, 1024)
        }
    }

    func testScreenOnLayout() {
        let r = AKP02Protocol.screenOn()
        let expected: [UInt8] = ascii("CRT") + [0, 0] + ascii("DIS") + [0, 0]
        XCTAssertEqual(Array(r[0..<10]), expected)
        XCTAssertTrue(r[10...].allSatisfy { $0 == 0 })
    }

    func testHeartbeatLayout() {
        let r = AKP02Protocol.heartbeat()
        let expected: [UInt8] = ascii("CRT") + [0, 0] + ascii("CONNECT") + [0, 0]
        XCTAssertEqual(Array(r[0..<14]), expected)
    }

    func testBrightnessParamAndClamp() {
        // Explizit typisiert: ältere Compiler (Xcode 16 in CI) scheitern sonst an der Typinferenz.
        let expected: [UInt8] = ascii("CRT") + [0, 0] + ascii("LIG") + [0, 0] + [60]
        XCTAssertEqual(Array(AKP02Protocol.brightness(60)[0..<11]), expected)
        XCTAssertEqual(AKP02Protocol.brightness(150)[10], 100)
        XCTAssertEqual(AKP02Protocol.brightness(-5)[10], 0)
    }

    func testFullFrameHeader() {
        let h = AKP02Protocol.fullFrameHeader(jpegLength: 1000)
        XCTAssertEqual(h.count, 32)
        XCTAssertEqual(Array(h[0..<3]), ascii("CRT"))
        XCTAssertEqual(Array(h[3..<5]), [0, 0])
        XCTAssertEqual(Array(h[5..<8]), ascii("DRA"))
        XCTAssertEqual(Array(h[8..<12]), [0x00, 0x00, 0x04, 0x08]) // 1000 + 0x20, big endian
        XCTAssertEqual(h[12], 0xB1)
        XCTAssertTrue(h[13...].allSatisfy { $0 == 0 }) // Vollbild: w/h/x/y = 0
    }

    func testFullFrameReportsChunkAndCommit() {
        let jpeg = (0..<2000).map { UInt8($0 % 251) }
        let reports = AKP02Protocol.fullFrameReports(jpeg: jpeg)
        XCTAssertEqual(reports.count, 3) // 2032 Byte Nutzlast → 2 Reports + Commit
        XCTAssertTrue(reports.allSatisfy { $0.count == 1024 })
        XCTAssertEqual(Array(reports[0][0..<32]), AKP02Protocol.fullFrameHeader(jpegLength: 2000))
        XCTAssertEqual(Array(reports[0][32..<1024]), Array(jpeg[0..<992]))
        XCTAssertEqual(Array(reports[1][0..<1008]), Array(jpeg[992..<2000]))
        XCTAssertTrue(reports[1][1008...].allSatisfy { $0 == 0 })
        XCTAssertEqual(reports[2], AKP02Protocol.commit())
    }
}
