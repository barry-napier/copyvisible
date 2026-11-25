import SwiftUI

/// Past captures: search by words or app, filter by date, copy, reopen or delete.
struct HistoryView: View {
    let store: HistoryStore
    let open: (HistoryItem) -> Void

    @State private var query = ""
    @State private var when: HistoryWhen = .any
    @State private var items: [HistoryItem] = []
    @State private var selection: HistoryItem.ID?
    @State private var confirmDelete = false

    private var selected: HistoryItem? { items.first { $0.id == selection } }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    TextField("Search text or app", text: $query)
                        .textFieldStyle(.roundedBorder)
                    Picker("", selection: $when) {
                        ForEach(HistoryWhen.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                .padding(10)
                if items.isEmpty {
                    ContentUnavailableView(
                        query.isEmpty ? "No captures yet" : "Nothing found",
                        systemImage: "clock.arrow.circlepath",
                        description: Text(Prefs.shared.keepHistory
                            ? "Captures show up here."
                            : "History is off. Turn it on in Settings."))
                } else {
                    List(items, selection: $selection) { item in
                        row(item).tag(item.id)
                    }
                }
                Divider()
                HStack {
                    Text("\(items.count) shown").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Delete All…", role: .destructive) { confirmDelete = true }
                        .controlSize(.small)
                }
                .padding(8)
            }
            .frame(minWidth: 300, idealWidth: 340)

            detail
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear(perform: reload)
        .onChange(of: query) { reload() }
        .onChange(of: when) { reload() }
        .onChange(of: store.version) { reload() }
        .confirmationDialog("Delete all history?", isPresented: $confirmDelete) {
            Button("Delete All", role: .destructive) { store.deleteAll() }
        } message: {
            Text("This removes every saved capture from this Mac. You cannot undo it.")
        }
    }

    private func row(_ item: HistoryItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: item.kind.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.text.replacingOccurrences(of: "\n", with: " "))
                    .lineLimit(2)
                Text([item.appName, item.date.formatted(date: .abbreviated, time: .shortened)]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var detail: some View {
        if let item = selected {
            VStack(alignment: .leading, spacing: 12) {
                if let data = item.thumbnail, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                }
                ScrollView {
                    Text(item.text)
                        .font(item.kind.keepsLayout || item.kind == .table ? .system(size: 12, design: .monospaced) : .body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Button("Copy") { Clipboard.copy(item.text) }
                        .keyboardShortcut("c", modifiers: [.command, .shift])
                    Button("Open in Panel") { open(item) }
                    Spacer()
                    Button("Delete", role: .destructive) {
                        store.delete(item.id)
                        selection = nil
                    }
                }
            }
            .padding(14)
        } else {
            ContentUnavailableView("Pick a capture", systemImage: "text.viewfinder")
        }
    }

    private func reload() {
        items = store.search(query, when: when)
        if let selection, !items.contains(where: { $0.id == selection }) { self.selection = nil }
    }
}
