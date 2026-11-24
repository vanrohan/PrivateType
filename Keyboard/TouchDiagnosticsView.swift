import UIKit

final class TouchZoneCanvas: UIView {
    var model = TouchModel()
    var keys: [(String, CGRect)] = []
    var sourceBounds = CGRect.zero
    var page = 0
    func resolvedKey(at point: CGPoint, variant: TouchModel.Variant = .active) -> (String, CGRect)? {
        KeyboardPlane.resolvedKey(at: point, keys: keys, bounds: sourceBounds, page: page, model: model, variant: variant)
    }
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 8
        clipsToBounds = true
        isAccessibilityElement = true
        accessibilityLabel = "Touch zone map"
        accessibilityHint = "The statistics below describe each learned key."
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    override func draw(_ rect: CGRect) {
        guard sourceBounds.width > 0, sourceBounds.height > 0, let context = UIGraphicsGetCurrentContext() else { return }
        let sx = bounds.width / sourceBounds.width, sy = bounds.height / sourceBounds.height
        func winner(_ point: CGPoint, variant: TouchModel.Variant) -> Int? {
            guard let selected = resolvedKey(at: point, variant: variant) else { return nil }
            return keys.firstIndex { $0.0 == selected.0 && $0.1 == selected.1 }
        }
        let step: CGFloat = 5
        var previousRow: [Int?] = []
        for y in stride(from: CGFloat(0), to: bounds.height, by: step) {
            var row: [Int?] = []
            for x in stride(from: CGFloat(0), to: bounds.width, by: step) {
                let point = CGPoint(x: sourceBounds.minX + (x + step / 2) / sx, y: sourceBounds.minY + (y + step / 2) / sy)
                let selected = winner(point, variant: .active)
                if selected != winner(point, variant: .baseline) {
                    UIColor.systemBlue.withAlphaComponent(0.18).setFill()
                    context.fill(CGRect(x: x, y: y, width: step, height: step))
                }
                UIColor.systemBlue.withAlphaComponent(0.7).setStroke()
                context.setLineWidth(0.7)
                if !row.isEmpty && row.last! != selected {
                    context.move(to: CGPoint(x: x, y: y)); context.addLine(to: CGPoint(x: x, y: y + step)); context.strokePath()
                }
                if previousRow.indices.contains(row.count) && previousRow[row.count] != selected {
                    context.move(to: CGPoint(x: x, y: y)); context.addLine(to: CGPoint(x: x + step, y: y)); context.strokePath()
                }
                row.append(selected)
            }
            previousRow = row
        }
        for (key, frame) in keys {
            let scaled = CGRect(x: (frame.minX - sourceBounds.minX) * sx, y: (frame.minY - sourceBounds.minY) * sy,
                                width: frame.width * sx, height: frame.height * sy)
            UIColor.separator.setStroke()
            UIBezierPath(rect: scaled.insetBy(dx: 1, dy: 1)).stroke()
            if let stats = model.offsets[key], let maximum = stats.histogram.max(), maximum > 0 {
                for index in stats.histogram.indices where stats.histogram[index] > 0 {
                    let tile = CGRect(x: (frame.midX - sourceBounds.minX + (CGFloat(index % 5) * 0.5 - 1.25) * frame.width) * sx,
                                      y: (frame.midY - sourceBounds.minY + (CGFloat(index / 5) * 0.5 - 1.25) * frame.height) * sy,
                                      width: frame.width * 0.5 * sx, height: frame.height * 0.5 * sy)
                    UIColor.systemOrange.withAlphaComponent(0.35 * CGFloat(stats.histogram[index]) / CGFloat(maximum)).setFill()
                    context.fill(tile)
                }
                let offset = model.offset(for: key)
                let center = CGPoint(x: (frame.midX - sourceBounds.minX + offset.x * frame.width) * sx,
                                     y: (frame.midY - sourceBounds.minY + offset.y * frame.height) * sy)
                UIColor.systemBlue.setFill()
                context.fillEllipse(in: CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4))
            }
            if key.count == 1 && key.first?.isLetter == true {
                (AlternateCharacters.cased(key, uppercase: true) as NSString).draw(at: CGPoint(x: scaled.minX + 3, y: scaled.minY + 2),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.label])
            }
        }
    }
}

final class TouchDiagnosticsView: UIScrollView {
    private let summary = UILabel()
    private let canvas = TouchZoneCanvas()
    private let details = UILabel()
    private var canvasHeight: NSLayoutConstraint?
    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "touchDiagnostics"
        let legend = UILabel()
        legend.text = "Gray: key edges. Blue: touch zones and centers. Orange: confirmed touches."
        let stack = UIStackView(arrangedSubviews: [summary, canvas, legend, details])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        for label in [summary, legend, details] {
            label.numberOfLines = 0
            label.font = .systemFont(ofSize: 11)
        }
        summary.font = .systemFont(ofSize: 12)
        details.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        details.accessibilityIdentifier = "touchStatistics"
        let height = canvas.heightAnchor.constraint(equalToConstant: 120)
        canvasHeight = height
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor, constant: -8),
            stack.widthAnchor.constraint(equalTo: frameLayoutGuide.widthAnchor, constant: -12),
            height
        ])
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    func configure(profile: TouchProfile?, model: TouchModel, plane: KeyboardPlane, learning: Bool) {
        plane.refreshGeometry()
        let name = profile.map { $0.layout.badge + ($0.landscape ? " landscape " : " portrait ") + String($0.width) + " pt" } ?? "Current layout"
        let state = model.hasApprovedModel ? "Validated zones active." : "Default zones active."
        summary.text = name + "\n" + (learning ? state : "Learning is off. No samples are collected.")
        canvasHeight?.constant = plane.compact ? 72 : 120
        canvas.model = model
        canvas.keys = plane.keys
        canvas.sourceBounds = plane.bounds
        canvas.page = plane.page
        canvas.accessibilityValue = "\(model.observations) confirmed samples"
        canvas.setNeedsDisplay()
        var lines = ["Local aggregate statistics. No message log.", "Confirmed samples: \(model.observations)",
                     "Validation: \(model.validation.samples)/20", "Approved: \(model.promotions). Rejected: \(model.rejections). Rolled back: \(model.rollbacks)."]
        if let validation = model.lastValidation {
            lines.append("Last check /\(validation.samples): default \(validation.baselineCorrect), active \(validation.activeCorrect), candidate \(validation.candidateCorrect).")
        }
        if model.offsets.isEmpty { lines.append("No confirmed touch samples yet.") }
        for key in model.offsets.keys.sorted() {
            guard let stats = model.offsets[key] else { continue }
            let applied = model.offset(for: key)
            lines.append(String(format: "%@: n=%d, shift %.0f%%/%.0f%%, spread %.0f%%/%.0f%%", AlternateCharacters.cased(key, uppercase: true), stats.count,
                                applied.x * 100, applied.y * 100, sqrt(stats.varianceX) * 100, sqrt(stats.varianceY) * 100))
            if !stats.confusions.isEmpty {
                lines.append("  Corrected from: " + stats.confusions.keys.sorted().map { AlternateCharacters.cased($0, uppercase: true) + ":" + String(stats.confusions[$0] ?? 0) }.joined(separator: ", "))
            }
        }
        details.text = lines.joined(separator: "\n")
    }
}
