import SwiftUI

private enum AppPreferences {
    static var defaults: UserDefaults {
        CommandLine.arguments.contains("--ui-testing")
            ? UserDefaults(suiteName: "com.sonnesolutions.simplekeyboard.uitesting")! : .standard
    }
}

private let practiceLearningNote = "Local learning starts on. It stores words and touch data on this device. Tap the gear in PrivateType to turn off Local learning."

@main
struct SimpleKeyboardApp: App {
    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: support.appendingPathComponent("WhisperDictation"))
        if CommandLine.arguments.contains("--ui-testing") {
            let storage = KeyboardStorage()
            storage.clear()
            storage.clearEmojiUsage()
            storage.language = .english
            storage.learning = false
            storage.autocorrection = true
            storage.neuralPrediction = true
            storage.keyboardSize = .standard
            storage.keyboardHand = .full
            storage.numberRow = false
            storage.cursorSpeed = .standard
            storage.preferredLanguage = .automatic
            storage.largerKeyLabels = false
            storage.highContrast = false
            if !CommandLine.arguments.contains("--keep-benchmark-results") {
                AppPreferences.defaults.removeObject(forKey: BenchmarkStore.key)
            }
            if !CommandLine.arguments.contains("--keep-setup-progress") {
                for key in ["setup.enabled", "setup.selected", "setup.typed"] {
                    AppPreferences.defaults.removeObject(forKey: key)
                }
            }
        }
    }
    var body: some Scene {
        WindowGroup { HomeView() }
    }
}

private struct KeyboardPreview: UIViewControllerRepresentable {
    @Binding var text: String
    @Binding var emojiOpen: Bool
    @Binding var size: KeyboardSize
    @Binding var numberRow: Bool
    let typingRequest: Int
    var storageOverride: KeyboardStorage? = nil
    var correctionStateChange: ((Bool) -> Void)? = nil
    final class Coordinator { var typingRequest = 0 }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIViewController(context: Context) -> KeyboardViewController {
        let controller = KeyboardViewController()
        if CommandLine.arguments.contains("--ui-testing") {
            if CommandLine.arguments.contains("--test-accessibility-text") {
                controller.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
            }
            if CommandLine.arguments.contains("--test-dark-appearance") { controller.traitOverrides.userInterfaceStyle = .dark }
        }
        if let storageOverride { controller.storage = storageOverride }
        controller.demoMode = true
        controller.demoText = text
        controller.onDemoTextChange = { text = $0 }
        controller.onDemoCorrectionChange = { available in
            DispatchQueue.main.async { correctionStateChange?(available) }
        }
        controller.onEmojiSearchVisibilityChange = { visible in
            DispatchQueue.main.async { emojiOpen = visible }
        }
        controller.onLayoutOptionsChange = { newSize, newNumberRow in
            DispatchQueue.main.async {
                if size != newSize { size = newSize }
                if numberRow != newNumberRow { numberRow = newNumberRow }
            }
        }
        if CommandLine.arguments.contains("--ui-testing"), CommandLine.arguments.contains("--test-dark-appearance") {
            controller.view.traitOverrides.userInterfaceStyle = .dark
            controller.view.updateTraitsIfNeeded()
        }
        return controller
    }
    func updateUIViewController(_ controller: KeyboardViewController, context: Context) {
        if context.coordinator.typingRequest != typingRequest {
            context.coordinator.typingRequest = typingRequest
            controller.hideEmoji()
        }
        if controller.demoText != text {
            controller.demoText = text
            controller.textDidChange(nil)
        }
    }
}

private struct DictionaryLicensesView: View {
    private var notices: String {
        let files = ["README_af_ZA.txt", "README_de_DE_frami.txt", "COPYING_GPLv2", "COPYING_GPLv3"]
        let resources = files.map { ("Dictionaries/Source", $0) } +
            ["Wordfreq-credits.txt", "Wordfreq-code-license.txt", "CC-BY-SA-4.0.txt"].map { ("Dictionaries/Western", $0) } +
            [("", "FUTO-LICENSE.md")]
        return resources.compactMap { folder, name in
            guard let url = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: folder.isEmpty ? nil : folder),
                  let data = try? Data(contentsOf: url) else { return nil }
            return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        }.joined(separator: "\n\n")
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Offline dictionary sources and licenses").font(.headline)
                Text("Afrikaans uses Translate.org.za and Puzzlefoundry data. German uses the igerman98 and frami data.")
                Text(notices).font(.footnote).textSelection(.enabled)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
        }.navigationTitle("Dictionary licenses").navigationBarTitleDisplayMode(.inline)
    }
}

private struct HomeView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @AppStorage("setup.enabled", store: AppPreferences.defaults) private var setupEnabled = false
    @AppStorage("setup.selected", store: AppPreferences.defaults) private var setupSelected = false
    @AppStorage("setup.typed", store: AppPreferences.defaults) private var setupTyped = false
    @State private var previewText = ""
    @State private var showPreview = false
    @State private var note = ""
    @State private var previewEmojiOpen = false
    @State private var previewSize = KeyboardSize.standard
    @State private var previewNumberRow = false
    @State private var previewTypingRequest = 0
    @State private var showPreviewPractice = false

    private var setupProgress: Int { [setupEnabled, setupSelected, setupTyped].filter { $0 }.count }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        Image("PrivateTypeLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Offline. Multilingual.").font(.headline)
                            Text("Prediction and correction. On your device.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    NavigationLink {
                        SetupChecklistView(enabled: $setupEnabled, selected: $setupSelected, typed: $setupTyped)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(setupProgress == 3 ? "Review setup" : "Set up PrivateType")
                                .font(.headline)
                                .foregroundStyle(setupProgress == 3 ? Color.primary : Color.accentColor)
                            Text("\(setupProgress) of 3 steps (self-reported)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("setupChecklistLink")
                    Button("Try the demo") { showPreview = true }
                }
                Section("Test typing") {
                    if setupProgress < 3 {
                        Text(practiceLearningNote).font(.footnote).foregroundStyle(.secondary)
                    }
                    TextField("Test the installed keyboard here", text: $note, axis: .vertical)
                        .autocorrectionDisabled(CommandLine.arguments.contains("--test-no-autocorrection"))
                        .keyboardType(CommandLine.arguments.contains("--test-url-field") ? .URL :
                            CommandLine.arguments.contains("--test-email-field") ? .emailAddress : .default)
                        .textInputAutocapitalization(CommandLine.arguments.contains("--test-url-field") ? .never : .sentences)
                        .lineLimit(2...4)
                        .accessibilityIdentifier("keyboardTestField")
                    NavigationLink("Typing test") { TypingBenchmarkView(defaults: AppPreferences.defaults) }
                        .accessibilityIdentifier("typingBenchmarkLink")
                }
                Section {
                    NavigationLink {
                        KeyboardSettingsHelpView()
                    } label: {
                        Label("Keyboard settings", systemImage: "gearshape")
                    }
                    NavigationLink {
                        List {
                            Label("Settings: choose QWERTY or QWERTZ", systemImage: "character.bubble")
                            Label("Smile button: emoji and search", systemImage: "face.smiling")
                            Label("Tap a suggestion to insert it", systemImage: "text.cursor")
                            Label("Delete: undo a correction", systemImage: "delete.left")
                            Label("Hold a suggestion: word options", systemImage: "text.word.spacing")
                            Label("Drag from 123: insert one symbol", systemImage: "hand.draw")
                            Label("Drag Space: move the cursor", systemImage: "arrow.left.and.right")
                            Label("Drag Delete left: remove words", systemImage: "delete.left")
                            Label("Double-tap Shift: caps lock", systemImage: "capslock")
                            Section {
                                Text("All supported languages work with either layout.")
                                Text("The preview does not move the cursor.")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .navigationTitle("Typing tips")
                        .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Label("Typing tips", systemImage: "keyboard")
                    }
                    NavigationLink {
                        List {
                            Section {
                                Label("No Full Access required", systemImage: "lock")
                                Label("No typing uploads or analytics", systemImage: "wifi.slash")
                                Text("PrivateType does not send your typing or usage data to servers.")
                            }
                            Section("Local learning") {
                                Text("On by default. Turn off in keyboard settings.")
                                Text("Stores word counts, word pairs, and touch statistics.")
                                Text("Word pairs can reveal parts of messages.")
                                Text("Delete learned data in keyboard settings.")
                            }
                            Section("Private typing") {
                                Text("Pauses personal history until the keyboard closes.")
                                Text("The receiving app still gets your text.")
                            }
                            Section("Emoji history") {
                                Text("Stores emoji counts on this device.")
                                Text("Tap Clear in the emoji grid to delete.")
                            }
                            Section {
                                Text("Device backups can include stored data.")
                                Text("Preview and keyboard data are separate.")
                            }
                        }
                        .navigationTitle("Privacy")
                        .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Label("Privacy", systemImage: "hand.raised")
                    }
                    NavigationLink {
                        List {
                            Section("On-device prediction") {
                                Text("Multilingual prediction and correction")
                                Text("Choose QWERTY or QWERTZ in keyboard settings.")
                                Text("Supported languages stay active on either layout.")
                                if Bundle.main.url(forResource: "English", withExtension: "pte") != nil,
                                   Bundle.main.url(forResource: "EnglishVocabulary", withExtension: "txt") != nil {
                                    Text("Powered by FUTO Swipe technology.")
                                    Text("English also uses a bundled neural model.")
                                }
                                Text("Supported languages use word tables and phrase predictions.")
                            }
                            Section("Supported languages") {
                                ForEach(TypingLanguage.allCases, id: \.self) { language in
                                    Text(language == .norwegian ? "Norwegian (Bokmal)" : language.title)
                                }
                            }
                            Section("iOS limits") {
                                Text("Apple's keyboard handles passwords and some phone fields.")
                                Text("Some apps block custom keyboards.")
                            }
                            Section {
                                NavigationLink("Dictionary sources and licenses") { DictionaryLicensesView() }
                            }
                        }
                        .navigationTitle("About")
                        .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Label("About", systemImage: "info.circle")
                    }
                }
            }
            .accessibilityHidden(showPreview)
            .navigationTitle("PrivateType")
            .fullScreenCover(isPresented: $showPreview) {
                if showPreviewPractice {
                    CorrectionPracticeView { showPreviewPractice = false }
                } else {
                    demo
                }
            }
        }
        .tint(Color("AccentColor"))
    }

    private var demo: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Keyboard preview").font(.headline)
                Spacer()
                Button("Close preview") { showPreview = false }
                    .frame(minWidth: 44, minHeight: 44)
            }.padding(.horizontal, 16).padding(.vertical, 4)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(previewText.isEmpty ? "Type with the keys below." : previewText)
                        .foregroundStyle(previewText.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .accessibilityIdentifier("previewText")
                        .contentShape(Rectangle())
                        .onTapGesture { previewTypingRequest += 1 }
                    if !previewEmojiOpen {
                        if previewText.isEmpty { Text("Hold E for accents.").foregroundStyle(.secondary) }
                        Button("Practice correction and Undo") { showPreviewPractice = true }
                            .frame(minHeight: 44)
                        Text("Preview settings apply here only.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
            }
            KeyboardPreview(text: $previewText, emojiOpen: $previewEmojiOpen, size: $previewSize,
                            numberRow: $previewNumberRow, typingRequest: previewTypingRequest)
                .frame(height: KeyboardLayout.height(compact: verticalSizeClass == .compact, emoji: previewEmojiOpen,
                                                    size: previewSize, numberRow: previewNumberRow))
                .ignoresSafeArea(.container, edges: .horizontal)
                .background(Color(uiColor: .systemGroupedBackground))
        }
    }
}

private struct KeyboardSettingsHelpView: View {
    @State private var sample = ""

    var body: some View {
        List {
            Section {
                Text("Tap the field below. Hold the globe key and select PrivateType.")
                Label("Tap the gear above the keys", systemImage: "gearshape")
                Text(practiceLearningNote).font(.footnote).foregroundStyle(.secondary)
                TextField("Type a sample", text: $sample)
                    .accessibilityIdentifier("settingsTypingField")
            }
            Section("Options") {
                Text("Predictions and correction")
                Text("Local learning and temporary private typing")
                Text("Touch zones and statistics")
                Text("Size, one-hand layout, number row, and cursor speed")
                Text("Larger key labels and high contrast")
            }
        }
        .navigationTitle("Keyboard settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SetupChecklistView: View {
    @Binding var enabled: Bool
    @Binding var selected: Bool
    @Binding var typed: Bool
    @State private var sample = ""
    @State private var cursorSample = "Move the cursor here."
    @State private var cursorConfirmed = false
    @State private var showPractice = false

    var body: some View {
        List {
            Section("Enable") {
                Text("Settings > General > Keyboard > Keyboards > Add New Keyboard > PrivateType")
                confirmation("I enabled PrivateType", value: $enabled)
            }
            Section("Select") {
                Text("Tap the sample field to open the keyboard. Hold the globe key and select PrivateType.")
                confirmation("I selected PrivateType", value: $selected)
            }
            Section {
                Text(practiceLearningNote).font(.footnote).foregroundStyle(.secondary)
                TextField("Type a short sample", text: $sample)
                    .accessibilityIdentifier("setupTypingField")
                    .onChange(of: sample) { _, value in
                        if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { typed = true }
                    }
                if typed { Label("Text entered", systemImage: "checkmark") }
                Button("Retry typing") { sample = ""; typed = false }
            } header: {
                Text("Type")
            } footer: {
                Text("Text entry counts as practice with any keyboard.")
            }
            Section("Optional practice") {
                Button("Practice correction and Undo") { showPractice = true }
                Text("Hold Space. Drag left or right to move the cursor.")
                TextField("Cursor practice", text: $cursorSample)
                    .accessibilityIdentifier("cursorPracticeField")
                confirmation("I tried Space dragging", value: $cursorConfirmed)
            }
            Section {
                Button("Reset checklist") {
                    enabled = false
                    selected = false
                    typed = false
                    sample = ""
                    cursorConfirmed = false
                    cursorSample = "Move the cursor here."
                }
            }
        }
        .navigationTitle("Setup checklist")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { sample = ""; cursorSample = "Move the cursor here." }
        .fullScreenCover(isPresented: $showPractice) { CorrectionPracticeView { showPractice = false } }
    }

    private func confirmation(_ title: String, value: Binding<Bool>) -> some View {
        Button { value.wrappedValue.toggle() } label: {
            HStack {
                Text(title)
                Spacer()
                if value.wrappedValue { Image(systemName: "checkmark").accessibilityHidden(true) }
            }
        }
        .accessibilityValue(value.wrappedValue ? "Confirmed" : "Not confirmed")
    }
}

private struct CorrectionPracticeView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    let onClose: () -> Void
    @StateObject private var session = PracticeSession()
    @State private var text = "Send "
    @State private var corrected = false
    @State private var undoAvailable = false
    @State private var restored = false
    @State private var emoji = false
    @State private var size = KeyboardSize.standard
    @State private var numbers = false
    @State private var typingRequest = 0

    private var instruction: String {
        if restored { return "Original restored. Try again when ready." }
        if undoAvailable && text == "Send the " { return "Tap Undo to restore teh." }
        if text.hasSuffix(" ") && text != "Send " { return "Tap Try again. Then type teh." }
        return "Type teh. Tap Space to correct it."
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Correction practice").font(.headline)
                Spacer()
                Button("Close practice", action: onClose).frame(minWidth: 44, minHeight: 44)
            }.padding(.horizontal, 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(instruction).accessibilityIdentifier("practiceInstruction")
                    Text(text).accessibilityIdentifier("practiceText")
                    Button("Try again") {
                        text = "Send "
                        corrected = false
                        undoAvailable = false
                        restored = false
                        typingRequest += 1
                    }
                    Text("Practice uses temporary settings. Normal settings stay unchanged.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding()
            }
            KeyboardPreview(text: $text, emojiOpen: $emoji, size: $size, numberRow: $numbers,
                            typingRequest: typingRequest, storageOverride: session.storage,
                            correctionStateChange: { undoAvailable = $0 })
                .frame(height: KeyboardLayout.height(compact: verticalSizeClass == .compact, emoji: emoji,
                                                    size: size, numberRow: numbers))
                .ignoresSafeArea(.container, edges: .horizontal)
                .background(Color(uiColor: .systemGroupedBackground))
        }
        .onChange(of: undoAvailable) { _, available in
            if available && text == "Send the " { corrected = true }
            if !available && corrected && text == "Send teh" { restored = true }
        }
    }
}

final class PracticeSession: ObservableObject {
    private let suite = "com.sonnesolutions.simplekeyboard.practice." + UUID().uuidString
    let storage: KeyboardStorage
    init() {
        storage = KeyboardStorage(defaults: UserDefaults(suiteName: suite)!)
        storage.learning = false
        storage.neuralPrediction = false
    }
    deinit { UserDefaults.standard.removePersistentDomain(forName: suite) }
}
