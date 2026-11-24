import XCTest
import UIKit
@testable import SimpleKeyboard

@MainActor
final class KeyboardStartupTests: XCTestCase {
    func testStartupStagesAndImmediateCorrection() throws {
        try checkStartup(neural: false)
    }

    func testStartupWithDefaultPredictionsAndImmediateCorrection() throws {
        try checkStartup(neural: true)
    }

    private func checkStartup(neural: Bool) throws {
        for trial in 0..<3 {
            let defaults = UserDefaults(suiteName: "startup-" + UUID().uuidString)!
            let storage = KeyboardStorage(defaults: defaults)
            storage.learning = false
            storage.neuralPrediction = neural
            let start = ProcessInfo.processInfo.systemUptime
            let controller = KeyboardViewController()
            let created = ProcessInfo.processInfo.systemUptime
            controller.storage = storage
            controller.demoMode = true
            controller.demoText = "Please send "
            controller.loadViewIfNeeded()
            let loaded = ProcessInfo.processInfo.systemUptime
            controller.beginAppearanceTransition(true, animated: false)
            let prepared = ProcessInfo.processInfo.systemUptime
            controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: KeyboardLayout.height(compact: false))
            controller.view.layoutIfNeeded()
            controller.endAppearanceTransition()
            let visible = ProcessInfo.processInfo.systemUptime
            controller.type(KeyHit(key: "t", point: .zero, frame: .zero, physical: false))
            let firstKey = ProcessInfo.processInfo.systemUptime
            for value in ["e", "h"] { controller.type(KeyHit(key: value, point: .zero, frame: .zero, physical: false)) }
            let beforeSpace = ProcessInfo.processInfo.systemUptime
            controller.type(KeyHit(key: "space", point: .zero, frame: .zero, physical: false))
            let afterSpace = ProcessInfo.processInfo.systemUptime
            XCTAssertEqual(controller.context, "Please send the ")
            XCTAssertFalse(controller.plane.isHidden)
            print(String(format: "STARTUP neural=%d trial=%d create=%.2f load=%.2f prepare=%.2f layout=%.2f visible=%.2f firstKey=%.2f space=%.2f ms",
                neural ? 1 : 0, trial, (created-start)*1000, (loaded-created)*1000, (prepared-loaded)*1000,
                (visible-prepared)*1000, (visible-start)*1000, (firstKey-visible)*1000, (afterSpace-beforeSpace)*1000))
            controller.beginAppearanceTransition(false, animated: false)
            controller.endAppearanceTransition()
            if neural {
                controller.demoText = "Please send "
                controller.beginAppearanceTransition(true, animated: false)
                controller.view.layoutIfNeeded()
                controller.endAppearanceTransition()
                for value in ["t", "e", "h", "space"] {
                    controller.type(KeyHit(key: value, point: .zero, frame: .zero, physical: false))
                }
                XCTAssertEqual(controller.context, "Please send the ")
                controller.beginAppearanceTransition(false, animated: false)
                controller.endAppearanceTransition()
            }
        }
    }
}
