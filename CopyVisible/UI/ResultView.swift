import SwiftUI

/// The result panel: the captured text, ways to copy it, quick links and
/// smart actions.
struct ResultView: View {
    @Bindable var model: PanelModel
    var close: () -> Void
    @FocusState private var askFocused: Bool
    @FocusState private var customFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    editor
                    formatRow
                    if let capture = model.capture { QuickLinks(model: model, capture: capture) }
                    smartActions
                    if model.aiAction != nil { answer }
                    ask
                    if let status = model.status {
                        Label(status, systemImage: "info.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(minWidth: 380, minHeight: 300)
        .background(.regularMaterial)
        .ignoresSafeArea(.container, edges: .top)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            if let capture = model.capture {
                Image(systemName: capture.kind.symbol)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 0) {
                    Text(capture.kind.title).font(.headline)
                    if let lines = model.watchLineCount {
                        Text("Watching · \(lines) line\(lines == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                    } else if let app = capture.appName {
                        Text("From \(app)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            CopiedBadge(copiedAt: model.copiedAt)
            Button { model.speak() } label: {
                Image(systemName: model.speaking ? "stop.circle" : "speaker.wave.2")
            }
            .help(model.speaking ? "Stop reading" : "Read aloud")
            Button { model.copy() } label: { Image(systemName: "doc.on.doc") }
                .help("Copy (⌘⇧C)")
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button(action: close) { Image(systemName: "xmark") }
                .help("Close (Esc)")
        }
        .buttonStyle(.borderless)
        .imageScale(.large)
    }

    // MARK: - Text

    private var editor: some View {
        let monospaced = model.capture?.kind.keepsLayout == true || model.capture?.kind == .table
            || model.format != .plain
        let lines = model.text.reduce(1) { $1 == "\n" ? $0 + 1 : $0 } + model.text.count / 52
        return TextEditor(text: $model.text)
            .font(monospaced ? .system(size: 12, design: .monospaced) : .system(size: 13))
            .scrollContentBackground(.hidden)
            .padding(6)
            .frame(height: min(240, max(70, CGFloat(lines) * 17 + 16)))
            .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
    }

    private var formatRow: some View {
        HStack(spacing: 10) {
            Picker("Copy as", selection: Binding(get: { model.format }, set: { model.setFormat($0) })) {
                ForEach(PasteFormat.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .fixedSize()
            if model.canJoin {
                Toggle("Join broken lines", isOn: Binding(get: { model.joined }, set: { _ in model.toggleJoin() }))
                    .toggleStyle(.checkbox)
            }
            Spacer()
        }
        .font(.callout)
    }

    // MARK: - Smart actions

    @ViewBuilder
    private var smartActions: some View {
        if let capture = model.capture {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("Smart actions", symbol: "sparkles")
                if let message = model.aiUnavailable {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(AIAction.actions(for: capture.kind)) { action in
                            actionButton(action)
                        }
                    }
                    if model.customOpen {
                        HStack {
                            TextField("Tell it what to do, like “turn this into a to-do list”", text: $model.customInstruction)
                                .textFieldStyle(.roundedBorder)
                                .focused($customFocused)
                                .onSubmit { model.runCustom() }
                                .onAppear { customFocused = true }
                            Button("Go") { model.runCustom() }
                                .disabled(model.customInstruction.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func actionButton(_ action: AIAction) -> some View {
        switch action {
        case .translate:
            Menu {
                ForEach(Prefs.languages, id: \.self) { language in
                    Button(language) {
                        Prefs.shared.translateTo = language
                        model.run(.translate, option: language)
                    }
                }
            } label: {
                Label("Translate to \(Prefs.shared.translateTo)", systemImage: action.symbol)
            } primaryAction: {
                model.run(.translate, option: Prefs.shared.translateTo)
            }
            .menuStyle(.button)
            .fixedSize()
        case .changeLanguage:
            Menu {
                ForEach(Prefs.codeLanguages, id: \.self) { language in
                    Button(language) {
                        Prefs.shared.codeLanguage = language
                        model.run(.changeLanguage, option: language)
                    }
                }
            } label: {
                Label("Change to \(Prefs.shared.codeLanguage)", systemImage: action.symbol)
            } primaryAction: {
                model.run(.changeLanguage, option: Prefs.shared.codeLanguage)
            }
            .menuStyle(.button)
            .fixedSize()
        case .custom:
            Button { model.customOpen.toggle() } label: { Label(action.title, systemImage: action.symbol) }
        default:
            Button { model.run(action) } label: { Label(action.title, systemImage: action.symbol) }
        }
    }

    private var answer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle(model.aiAction?.title ?? "", symbol: model.aiAction?.symbol ?? "sparkles")
                if model.aiRunning { ProgressView().controlSize(.small) }
                Spacer()
                Button { model.closeAnswer() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
            if let error = model.aiError {
                Text(error).foregroundStyle(.red).font(.callout)
            } else {
                Text(model.aiOutput.isEmpty ? AttributedString("Thinking…")
                     : model.aiAction?.makesText == true ? AttributedString(model.aiOutput) : rich(model.aiOutput))
                    .font(model.aiAction?.makesText == true && model.capture?.kind == .code
                          ? .system(size: 12, design: .monospaced) : .body)
                    .foregroundStyle(model.aiOutput.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                if model.aiRunning {
                    Button("Stop") { model.stopAI() }
                } else if !model.aiOutput.isEmpty {
                    Button("Copy Answer") { model.copyAnswer() }
                    if model.aiAction?.makesText == true {
                        Button("Use This Text") { model.useAnswer() }
                    }
                }
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(.tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Ask about it

    @ViewBuilder
    private var ask: some View {
        if model.aiUnavailable == nil, model.capture != nil {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("Ask about it", symbol: "bubble.left.and.bubble.right")
                ForEach(model.chat) { line in
                    Text(line.text.isEmpty ? AttributedString("Thinking…") : rich(line.text))
                        .textSelection(.enabled)
                        .foregroundStyle(line.text.isEmpty ? .secondary : .primary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: line.role == .user ? .trailing : .leading)
                        .background(
                            line.role == .user ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.quaternary.opacity(0.5)),
                            in: RoundedRectangle(cornerRadius: 8))
                }
                HStack {
                    TextField("Ask a question, like “what does this error mean?”", text: $model.question)
                        .textFieldStyle(.roundedBorder)
                        .focused($askFocused)
                        .onSubmit { model.ask() }
                    Button { model.ask() } label: { Image(systemName: "arrow.up.circle.fill").imageScale(.large) }
                        .buttonStyle(.borderless)
                        .disabled(model.question.trimmingCharacters(in: .whitespaces).isEmpty || model.aiRunning)
                }
            }
        }
    }
}

/// Shows the model's light formatting (`code`, **bold**) and turns "* "
/// list marks into bullets. Text that is new code stays as it is.
private func rich(_ text: String) -> AttributedString {
    let bulleted = text.replacing(#/(?m)^(\s*)[*-]\s/#) { "\($0.1)• " }
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    return (try? AttributedString(markdown: bulleted, options: options)) ?? AttributedString(text)
}

/// Buttons for links, emails, phone numbers, dates, contacts and QR codes.
private struct QuickLinks: View {
    let model: PanelModel
    let capture: Capture

    var body: some View {
        let found = capture.detected
        let hasAny = !found.isEmpty || capture.kind == .contact || capture.kind == .qr
        if hasAny {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("Quick links", symbol: "link")
                FlowLayout(spacing: 6) {
                    if capture.kind == .contact {
                        Button { model.addContact() } label: { Label("Add to Contacts", systemImage: "person.crop.circle.badge.plus") }
                    }
                    ForEach(found.links.prefix(4), id: \.self) { url in
                        Button { model.open(url) } label: {
                            Label(url.host() ?? url.absoluteString, systemImage: "safari")
                        }
                        .help(url.absoluteString)
                    }
                    ForEach(found.emails.prefix(3), id: \.self) { email in
                        Button { model.open(URL(string: "mailto:\(email)")!) } label: { Label(email, systemImage: "envelope") }
                    }
                    ForEach(found.phones.prefix(3), id: \.self) { phone in
                        Button {
                            let digits = phone.filter { $0.isNumber || $0 == "+" }
                            if let url = URL(string: "tel:\(digits)") { model.open(url) }
                        } label: { Label(phone, systemImage: "phone") }
                    }
                    ForEach(found.addresses.prefix(2), id: \.self) { address in
                        Button {
                            var parts = URLComponents(string: "maps://")!
                            parts.queryItems = [URLQueryItem(name: "q", value: address)]
                            if let url = parts.url { model.open(url) }
                        } label: { Label(address, systemImage: "map") }
                    }
                    ForEach(found.dates.prefix(3), id: \.self) { date in
                        Menu {
                            Button("Add to Calendar") { model.addEvent(date) }
                            Button("Add to Reminders") { model.addReminder(date) }
                        } label: {
                            Label(date.date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar.badge.plus")
                        }
                        .menuStyle(.button)
                        .fixedSize()
                    }
                }
                .lineLimit(1)
            }
        }
    }
}

private struct SectionTitle: View {
    let title: String
    let symbol: String

    init(_ title: String, symbol: String) {
        self.title = title
        self.symbol = symbol
    }

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

/// Shows "Copied" for two seconds after each copy.
private struct CopiedBadge: View {
    let copiedAt: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            if let copiedAt, context.date.timeIntervalSince(copiedAt) < 2 {
                Label("Copied", systemImage: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }
        }
    }
}

/// Lays out views in rows, wrapping to the next row when one is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0, x + size.width > width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(widest, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
