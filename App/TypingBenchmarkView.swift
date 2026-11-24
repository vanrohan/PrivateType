import SwiftUI
import UIKit
import UniformTypeIdentifiers

private struct BenchmarkCSV: Transferable {
    let text: String
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { Data($0.text.utf8) }
            .suggestedFileName("typing-results.csv")
    }
}

final class BenchmarkInputCoordinator: NSObject, UITextViewDelegate {
    var onChange: (String) -> Void = { _ in }
    var onFinish: (String) -> Void = { _ in }
    private(set) var alive = true
    private var finishing = false

    func textViewDidChange(_ textView: UITextView) {
        guard alive else { return }
        onChange(textView.text ?? "")
    }
    func finish(_ textView: UITextView) {
        guard alive, !finishing else { return }
        finishing = true
        textView.unmarkText()
        textView.resignFirstResponder()
        DispatchQueue.main.async { [weak self, weak textView] in
            guard let self, self.alive, let textView else { return }
            self.onFinish(textView.text ?? "")
        }
    }
    func cancel(_ textView: UITextView) {
        alive = false
        textView.delegate = nil
        textView.resignFirstResponder()
        textView.text = ""
        onChange = { _ in }
        onFinish = { _ in }
    }
}

private struct BenchmarkInput: UIViewRepresentable {
    let initialText: String
    let finishRequested: Bool
    let onChange: (String) -> Void
    let onFinish: (String) -> Void

    func makeCoordinator() -> BenchmarkInputCoordinator { BenchmarkInputCoordinator() }
    func makeUIView(context: Context) -> UITextView {
        let field = UITextView()
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.backgroundColor = .secondarySystemGroupedBackground
        field.text = initialText
        field.accessibilityIdentifier = "benchmarkInput"
        field.accessibilityLabel = "Typing sample"
        field.delegate = context.coordinator
        return field
    }
    func updateUIView(_ field: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onChange = onChange
        coordinator.onFinish = onFinish
        if finishRequested {
            DispatchQueue.main.async { [weak field] in
                if let field { coordinator.finish(field) }
            }
        }
    }
    static func dismantleUIView(_ field: UITextView, coordinator: BenchmarkInputCoordinator) {
        coordinator.cancel(field)
    }
}

struct TypingBenchmarkView: View {
    let defaults: UserDefaults
    @Environment(\.scenePhase) private var scenePhase
    @State private var task = BenchmarkTask.english
    @State private var sampleIndex = 0
    private var selectedSample: BenchmarkSample { task.samples[sampleIndex % task.samples.count] }
    @State private var conditions = Dictionary(uniqueKeysWithValues:
        BenchmarkCondition.allCases.map { ($0.rawValue, "Not recorded") })
    @State private var session: BenchmarkSession?
    @State private var trialID = UUID()
    @State private var finishRequested = false
    @State private var result: BenchmarkResult?
    @State private var results: [BenchmarkResult] = []
    @State private var error: String?
    @State private var saved = false
    @State private var showDeleteAll = false

    var body: some View {
        VStack(spacing: 0) {
            if session != nil { trialContent }
            else { formContent }
        }
        .navigationTitle("Typing test")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(session != nil)
        .toolbar {
            if session != nil {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel", action: cancel) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Finish") { finishRequested = true }.disabled(finishRequested)
                        .accessibilityIdentifier("benchmarkFinish")
                }
            }
        }
        .onAppear(perform: reload)
        .onChange(of: task) { _, _ in sampleIndex = 0 }
        .onDisappear(perform: cancel)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, session != nil { cancel(); error = BenchmarkError.interrupted.localizedDescription }
        }
    }

    private var trialContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session?.sample.text ?? selectedSample.text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("benchmarkTarget")
            BenchmarkInput(initialText: session?.sample.initialText ?? selectedSample.initialText, finishRequested: finishRequested,
                onChange: change, onFinish: finish)
                .id(trialID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var formContent: some View {
        Form {
            if let error {
                Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("benchmarkError") }
            }
            if let result {
                Section("\(result.task.title), sample \(result.sampleNumber)") {
                    Button(saved ? "Result saved" : "Save result", action: save)
                        .disabled(saved).accessibilityIdentifier("benchmarkSave")
                    LabeledContent("Characters", value: String(result.characters))
                    LabeledContent("Remaining errors", value: String(result.errors))
                    LabeledContent("Time", value: result.seconds.map { String(format: "%.2f s", $0) } ?? "Untimed")
                    if let wpm = result.wordsPerMinute {
                        LabeledContent("Words per minute", value: String(format: "%.1f", wpm))
                    }
                    Text(result.task == .repair ? "Time includes keyboard opening." : "Time runs from the first text change to the last.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if result.seconds == nil { Text("Too few timed changes. Type the sample without pasting.").font(.footnote) }
                    Button("Try again") { self.result = nil; error = nil; saved = false }
                }
            } else {
                Section {
                    Picker("Task", selection: $task) {
                        ForEach(BenchmarkTask.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.accessibilityIdentifier("benchmarkTask")
                    Text("Sample \(sampleIndex + 1) of \(task.samples.count)")
                        .accessibilityIdentifier("benchmarkSampleNumber")
                    Text(selectedSample.text).accessibilityIdentifier("benchmarkTarget")
                    Button("Next sample") { sampleIndex = (sampleIndex + 1) % task.samples.count }
                        .accessibilityIdentifier("benchmarkNextSample")
                    conditionPicker(.keyboard)
                    DisclosureGroup("Reported settings") {
                        ForEach(BenchmarkCondition.allCases.filter { $0 != .keyboard }, id: \.self) { conditionPicker($0) }
                    }
                    Text("Select your keyboard in the typing field. Start again after changing its settings.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Start", action: start).accessibilityIdentifier("benchmarkStart")
                } footer: {
                    Text("Type without pasting. Keyboard learning can store practice words.")
                }
            }
            if session == nil {
                Section {
                    NavigationLink("Saved results (\(results.count))") { savedResults }
                        .accessibilityIdentifier("benchmarkResults")
                } footer: {
                    Text("Save up to 50 results on this device. Results contain metrics, not typed text.")
                }
            }
        }
    }

    private func conditionPicker(_ condition: BenchmarkCondition) -> some View {
        Picker(condition.title, selection: Binding(
            get: { conditions[condition.rawValue] ?? "Not recorded" },
            set: { conditions[condition.rawValue] = $0 })) {
            ForEach(condition.options, id: \.self) { Text($0).tag($0) }
        }
    }

    private var savedResults: some View {
        List {
            if results.isEmpty { Text("No saved results") }
            ForEach(results.reversed()) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.task.title).font(.headline)
                    Text("Sample \(item.sampleNumber)").font(.subheadline)
                    Text(item.date, style: .date).font(.subheadline).foregroundStyle(.secondary)
                    Text("\(item.errors) errors, \(item.characters) characters")
                    Text(item.seconds.map { String(format: "%.2f seconds", $0) } ?? "Untimed")
                    if item.environment.automated { Text("Automated check").font(.caption) }
                }
                .swipeActions { Button("Delete", role: .destructive) { delete(item.id) } }
            }
            if !results.isEmpty {
                Section {
                    ShareLink(item: BenchmarkCSV(text: BenchmarkStore(defaults: defaults).csv),
                        preview: SharePreview("Typing results")) {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                    }
                    Button("Delete all results", role: .destructive) { showDeleteAll = true }
                }
            }
        }
        .navigationTitle("Saved results")
        .confirmationDialog("Delete all saved results?", isPresented: $showDeleteAll, titleVisibility: .visible) {
            Button("Delete all results", role: .destructive) {
                do { try BenchmarkStore(defaults: defaults).deleteAll(); reload(); error = nil }
                catch { self.error = error.localizedDescription }
            }.accessibilityIdentifier("benchmarkConfirmDeleteAll")
        }
    }

    private func start() {
        error = nil
        result = nil
        saved = false
        finishRequested = false
        trialID = UUID()
        let orientation = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?.interfaceOrientation ?? .unknown
        let environment = BenchmarkEnvironment(device: UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone",
            os: UIDevice.current.systemVersion,
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            orientation: orientation.isLandscape ? "landscape" : (orientation.isPortrait ? "portrait" : "unknown"),
            automated: CommandLine.arguments.contains("--ui-testing"))
        session = BenchmarkSession(task: task, sampleID: selectedSample.id, conditions: conditions,
            environment: environment, now: ProcessInfo.processInfo.systemUptime)
    }

    private func change(_ text: String) {
        guard session != nil else { return }
        session?.change(text, now: ProcessInfo.processInfo.systemUptime)
        if let failure = session?.failure { cancel(); error = failure.localizedDescription }
    }
    private func finish(_ text: String) {
        guard var current = session else { return }
        current.change(text, now: ProcessInfo.processInfo.systemUptime)
        session = nil
        finishRequested = false
        do { result = try current.finish() }
        catch { self.error = error.localizedDescription }
    }
    private func cancel() {
        session?.invalidate()
        session = nil
        finishRequested = false
    }
    private func save() {
        guard let result else { return }
        do { try BenchmarkStore(defaults: defaults).save(result); saved = true; error = nil; reload() }
        catch { self.error = error.localizedDescription }
    }
    private func delete(_ id: UUID) {
        do { try BenchmarkStore(defaults: defaults).delete([id]); reload() }
        catch { self.error = error.localizedDescription }
    }
    private func reload() {
        let store = BenchmarkStore(defaults: defaults)
        results = store.results
        if store.loadFailed { error = "Saved results cannot be read. Saving a result replaces the unreadable data." }
    }
}
