import XCTest
import UIKit
@testable import SimpleKeyboard

@MainActor
private final class CommitTextView: UITextView {
    override func resignFirstResponder() -> Bool {
        text = "Final committed text"
        return true
    }
}

@MainActor
final class TypingBenchmarkInputTests: XCTestCase {
    func testFinishReadsTextAfterKeyboardCommit() async {
        let field = CommitTextView()
        field.text = "Before commit"
        let coordinator = BenchmarkInputCoordinator()
        let finished = expectation(description: "Final text")
        coordinator.onFinish = { text in
            XCTAssertEqual(text, "Final committed text")
            finished.fulfill()
        }
        coordinator.finish(field)
        await fulfillment(of: [finished], timeout: 2)
    }

    func testCancelClearsTextAndRejectsPendingFinishAndLateChanges() async {
        let field = CommitTextView()
        let coordinator = BenchmarkInputCoordinator()
        let callback = expectation(description: "No callbacks after cancellation")
        callback.isInverted = true
        coordinator.onChange = { _ in callback.fulfill() }
        coordinator.onFinish = { _ in callback.fulfill() }
        coordinator.finish(field)
        coordinator.cancel(field)
        coordinator.textViewDidChange(field)
        XCTAssertEqual(field.text, "")
        await fulfillment(of: [callback], timeout: 0.1)
    }
}
