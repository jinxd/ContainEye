import Foundation
import Testing
@testable import ContainEye

struct XTermBridgeEventTests {
    @Test
    func parsesTerminalDataEvent() {
        let body: [String: Any] = [
            "type": "terminal_data",
            "payload": ["data": "ls -la\n"],
        ]

        let event = XTermBridgeEvent(body: body)

        #expect(event != nil)
        #expect(event?.type == .terminalData)
        #expect(event?.data == "ls -la\n")
    }

    @Test
    func parsesResizeAndCwdEvents() {
        let resizeBody: [String: Any] = [
            "type": "terminal_resized",
            "payload": ["cols": 120, "rows": 40],
        ]
        let cwdBody: [String: Any] = [
            "type": "cwd_changed",
            "payload": ["cwd": "/var/log"],
        ]

        let resize = XTermBridgeEvent(body: resizeBody)
        let cwd = XTermBridgeEvent(body: cwdBody)

        #expect(resize?.type == .terminalResized)
        #expect(resize?.cols == 120)
        #expect(resize?.rows == 40)
        #expect(cwd?.type == .cwdChanged)
        #expect(cwd?.cwd == "/var/log")
    }

    @Test
    func parsesCommandLifecycleEvents() {
        let startedBody: [String: Any] = [
            "type": "command_started",
            "payload": ["cmd": "git status"],
        ]
        let exitedBody: [String: Any] = [
            "type": "command_exited",
            "payload": ["exitCode": "0"],
        ]

        let started = XTermBridgeEvent(body: startedBody)
        let exited = XTermBridgeEvent(body: exitedBody)

        #expect(started?.type == .commandStarted)
        #expect(started?.command == "git status")
        #expect(exited?.type == .commandExited)
        #expect(exited?.exitCode == "0")
    }

    @Test
    func rejectsMalformedBridgeBodies() {
        #expect(XTermBridgeEvent(body: "bad") == nil)
        #expect(XTermBridgeEvent(body: ["payload": [:]]) == nil)
        #expect(XTermBridgeEvent(body: ["type": "unknown_type", "payload": [:]]) == nil)
    }
}
