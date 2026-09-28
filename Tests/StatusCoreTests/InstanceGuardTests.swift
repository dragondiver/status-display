import XCTest
@testable import StatusCore

final class EndpointOwnershipTests: XCTestCase {
    func testMayRemoveOwnPid() {
        XCTAssertTrue(EndpointOwnership.mayRemove(endpoint: Endpoint(port: 1, pid: 111), ownPid: 111))
    }

    func testMayNotRemoveForeignPid() {
        XCTAssertFalse(EndpointOwnership.mayRemove(endpoint: Endpoint(port: 1, pid: 111), ownPid: 222))
    }

    /// Alte Datei ohne `pid` (vor #27 geschrieben): gehört niemandem nachweislich.
    func testMayNotRemoveEndpointWithoutPid() {
        XCTAssertFalse(EndpointOwnership.mayRemove(endpoint: Endpoint(port: 1), ownPid: 111))
    }

    func testMayNotRemoveMissingEndpoint() {
        XCTAssertFalse(EndpointOwnership.mayRemove(endpoint: nil, ownPid: 111))
    }
}

final class SingleInstanceTests: XCTestCase {
    func testKeepsRunningWhenAlone() {
        XCTAssertFalse(SingleInstance.shouldQuit(runningPids: [111], ownPid: 111))
    }

    func testKeepsRunningWhenNoOtherInstanceListed() {
        XCTAssertFalse(SingleInstance.shouldQuit(runningPids: [], ownPid: 111))
    }

    func testQuitsWhenAnotherInstanceIsRunning() {
        XCTAssertTrue(SingleInstance.shouldQuit(runningPids: [111, 999], ownPid: 111))
    }

    /// Reihenfolge/Wiederholung egal, solange irgendeine fremde PID dabei ist.
    func testQuitsRegardlessOfOrder() {
        XCTAssertTrue(SingleInstance.shouldQuit(runningPids: [999, 111], ownPid: 111))
    }
}
