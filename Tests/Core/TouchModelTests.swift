import XCTest
#if SWIFT_PACKAGE
@testable import KeyboardCore
#else
@testable import SimpleKeyboard
#endif

final class TouchModelTests: XCTestCase {
    func testAggregateStatisticsMeasureSpreadAndNeighborConfusions() throws {
        var model = TouchModel()
        for (x, y) in [(-0.1, -0.2), (0.1, 0.2), (0.3, 0.6)] {
            model.learn(key: "a", x: x, y: y, observedKey: "s")
        }
        let stats = try XCTUnwrap(model.offsets["a"])
        XCTAssertEqual(stats.x, 0.1, accuracy: 0.0001)
        XCTAssertEqual(stats.y, 0.2, accuracy: 0.0001)
        XCTAssertEqual(stats.varianceX, 0.0266667, accuracy: 0.0001)
        XCTAssertEqual(stats.varianceY, 0.1066667, accuracy: 0.0001)
        XCTAssertEqual(stats.covariance, 0.0533333, accuracy: 0.0001)
        XCTAssertEqual(stats.histogram.reduce(0, +), 3)
        XCTAssertEqual(stats.confusions["s"], 3)
        XCTAssertEqual(model.offset(for: "a"), TouchOffset())
        XCTAssertLessThanOrEqual(model.offset(for: "a").y, 0.12)
        XCTAssertTrue(model.score(key: "a", x: 0.2, y: 0.1).isFinite)
        XCTAssertEqual(try JSONDecoder().decode(TouchModel.self, from: JSONEncoder().encode(model)), model)
    }
    private func evaluate(_ model: inout TouchModel, baseline: Bool, active: Bool, candidate: Bool) {
        let previous = model.promotions + model.rejections
        for _ in 0..<120 {
            if model.shouldValidateNext {
                let count = model.offsets["a"]?.count
                model.validate(baselineCorrect: baseline, activeCorrect: active, candidateCorrect: candidate)
                XCTAssertEqual(model.offsets["a"]?.count, count)
            } else { model.learn(key: "a", x: 0.4, y: 0) }
            if model.promotions + model.rejections > previous { return }
        }
        XCTFail("The validation window did not finish.")
    }
    func testLargerZonesNeedHeldOutImprovementAndCanRollBack() throws {
        var model = TouchModel()
        for _ in 0..<20 { model.learn(key: "a", x: 0.4, y: 0) }
        XCTAssertFalse(model.hasApprovedModel)
        XCTAssertEqual(model.offset(for: "a"), TouchOffset())
        evaluate(&model, baseline: false, active: false, candidate: true)
        XCTAssertTrue(model.hasApprovedModel)
        XCTAssertEqual(model.promotions, 1)
        XCTAssertEqual(model.offset(for: "a").x, 0.2, accuracy: 0.0001)
        XCTAssertEqual(model.lastValidation?.samples, 20)
        let approved = model.offset(for: "a")
        for _ in 0..<20 { model.learn(key: "a", x: -0.4, y: 0) }
        XCTAssertEqual(model.offset(for: "a"), approved)
        for _ in 0..<3 { model.learn(key: "z", x: 0.4, y: 0) }
        XCTAssertEqual(model.offset(for: "z").count, 0)
        evaluate(&model, baseline: true, active: false, candidate: false)
        XCTAssertFalse(model.hasApprovedModel)
        XCTAssertTrue(model.suspended)
        XCTAssertEqual(model.rollbacks, 1)
        XCTAssertEqual(model.offset(for: "a").count, 0)
    }
    func testEqualAccuracyDoesNotEnableLargerZones() {
        var model = TouchModel()
        evaluate(&model, baseline: true, active: true, candidate: true)
        XCTAssertEqual(model.rejections, 1)
        XCTAssertFalse(model.hasApprovedModel)
        XCTAssertEqual(model.offset(for: "a"), TouchOffset())
    }
    func testPromotionRequiresSixteenCorrectAndNoLossAgainstActiveZones() {
        for (candidateCount, baselineCount, activeCount, approved) in [(15, 0, 0, false), (16, 15, 15, true), (16, 16, 15, false), (16, 15, 17, false)] {
            var model = TouchModel()
            for _ in 0..<20 { model.learn(key: "a", x: 0.4, y: 0) }
            for _ in 0..<110 where model.lastValidation == nil {
                if model.shouldValidateNext {
                    let index = model.validation.samples
                    model.validate(baselineCorrect: index < baselineCount, activeCorrect: index < activeCount,
                                   candidateCorrect: index < candidateCount)
                } else { model.learn(key: "a", x: 0.4, y: 0) }
            }
            XCTAssertEqual(model.lastValidation?.samples, 20)
            XCTAssertEqual(model.hasApprovedModel, approved)
        }
    }
    func testApprovedZonesAndPartialValidationSurviveStorage() throws {
        var model = TouchModel()
        evaluate(&model, baseline: false, active: false, candidate: true)
        while model.validation.samples < 3 {
            if model.shouldValidateNext { model.validate(baselineCorrect: false, activeCorrect: true, candidateCorrect: true) }
            else { model.learn(key: "a", x: 0.1, y: 0.1) }
        }
        let restored = try JSONDecoder().decode(TouchModel.self, from: JSONEncoder().encode(model))
        XCTAssertEqual(restored, model)
        XCTAssertTrue(restored.hasApprovedModel)
        XCTAssertEqual(restored.validation.samples, 3)
        XCTAssertEqual(restored.offset(for: "a"), model.offset(for: "a"))
    }

    func testValidationContinuesAfterTheObservationCounterSaturates() throws {
        var model = TouchModel()
        for _ in 0..<24 { model.learn(key: "a", x: 0.1, y: 0) }
        let data = try JSONEncoder().encode(model)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["observations"] = 1_000_000
        json["validationPhase"] = 4
        model = try JSONDecoder().decode(TouchModel.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(model.shouldValidateNext)
        model.validate(baselineCorrect: true, activeCorrect: true, candidateCorrect: true)
        for _ in 0..<4 { model.learn(key: "a", x: 0.1, y: 0) }
        XCTAssertTrue(model.shouldValidateNext)
    }

    func testLegacyOffsetsLoadAndInvalidStatisticsFail() throws {
        let legacy = Data(#"{"offsets":{"a":{"x":0.1,"y":0,"count":3}}}"#.utf8)
        let model = try JSONDecoder().decode(TouchModel.self, from: legacy)
        XCTAssertEqual(model.offsets["a"]?.count, 3)
        XCTAssertEqual(model.offsets["a"]?.histogram.count, 25)
        for json in [#"{"offsets":{"a":{"x":99,"y":0,"count":3}}}"#,
                     #"{"offsets":{"delete":{"x":0,"y":0,"count":3}}}"#,
                     #"{"offsets":{},"validation":{"samples":21,"baselineCorrect":0,"activeCorrect":0,"candidateCorrect":0}}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(TouchModel.self, from: Data(json.utf8)))
        }
    }
    func testAlignmentUsesOnlyUnambiguousLettersAndSkipsTranspositions() {
        let inserted = TouchAlignment.assignments(original: "helo", replacement: "hello")
        XCTAssertEqual(inserted.map(\.intended), ["h", "e", "l", "o"])
        let removed = TouchAlignment.assignments(original: "helllo", replacement: "hello")
        XCTAssertEqual(removed.map(\.sourceIndex), [0, 1, 5])
        XCTAssertEqual(TouchAlignment.assignments(original: "teh", replacement: "the").map(\.intended), ["t"])
        XCTAssertEqual(TouchAlignment.assignments(original: "g", replacement: "f").first?.intended, "f")
        XCTAssertTrue(TouchAlignment.assignments(original: "x", replacement: "hello").isEmpty)
        XCTAssertTrue(TouchAlignment.assignments(original: "", replacement: "hello").isEmpty)
        XCTAssertTrue(TouchAlignment.assignments(original: String(repeating: "a", count: 100), replacement: "a").isEmpty)
    }
    func testUnapprovedOffsetsStayInactiveAndSurviveStorage() throws {
        var model = TouchModel()
        for _ in 0..<24 { model.learn(key: "a", x: 0.4, y: 0.2) }
        XCTAssertEqual(model.offsets["a"]?.count, 24)
        XCTAssertFalse(model.hasApprovedModel)
        XCTAssertEqual(model.offset(for: "a"), TouchOffset())
        XCTAssertGreaterThan(model.offset(for: "a", variant: .candidate).count, 0)
        for (x, y) in [(0.0, 0.0), (0.4, 0.2), (-0.3, -0.1)] {
            XCTAssertEqual(model.score(key: "a", x: x, y: y),
                model.score(key: "a", x: x, y: y, variant: .baseline))
        }
        let restored = try JSONDecoder().decode(TouchModel.self, from: JSONEncoder().encode(model))
        XCTAssertEqual(restored.offsets, model.offsets)
        XCTAssertEqual(restored.offset(for: "a"), TouchOffset())
        XCTAssertEqual(restored.offset(for: "a", variant: .candidate), model.offset(for: "a", variant: .candidate))
        let legacy = Data(#"{"offsets":{"a":{"x":0.4,"y":0,"count":24}}}"#.utf8)
        let migrated = try JSONDecoder().decode(TouchModel.self, from: legacy)
        XCTAssertEqual(migrated.offsets["a"]?.count, 24)
        XCTAssertEqual(migrated.offset(for: "a"), TouchOffset())
    }

    func testRejectedAndRolledBackZonesNeedValidationBeforeRecovery() {
        var model = TouchModel()
        evaluate(&model, baseline: true, active: true, candidate: false)
        XCTAssertFalse(model.hasApprovedModel)
        XCTAssertEqual(model.offset(for: "a"), TouchOffset())
        evaluate(&model, baseline: false, active: false, candidate: true)
        XCTAssertTrue(model.hasApprovedModel)
        evaluate(&model, baseline: true, active: false, candidate: false)
        XCTAssertTrue(model.suspended)
        for _ in 0..<20 { model.learn(key: "a", x: 0.4, y: 0) }
        XCTAssertFalse(model.hasApprovedModel)
        XCTAssertEqual(model.offset(for: "a"), TouchOffset())
        evaluate(&model, baseline: false, active: false, candidate: true)
        XCTAssertTrue(model.hasApprovedModel)
        XCTAssertFalse(model.suspended)
        XCTAssertEqual(model.promotions, 2)
        XCTAssertEqual(model.rollbacks, 1)
    }

}
