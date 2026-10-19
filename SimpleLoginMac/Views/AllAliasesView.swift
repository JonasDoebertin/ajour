import SimpleLoginKit
import SwiftUI

struct AllAliasesView: View {
    static let windowID = "all-aliases"

    @Bindable var model: AllAliasesModel
    let appModel: AppModel

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.aliases) { alias in
                    AliasRow(alias: alias, stateLabel: model.stateLabel(for: alias))
                        .contextMenu { AliasRowActions(alias: alias, model: model) }
                        .onAppear { Task { await model.loadMore(after: alias) } }
                }
                listFooter
            }
            .overlay {
                if model.showsEmptyState {
                    ContentUnavailableView(
                        model.searchText.isEmpty ? "No Aliases" : "No Matching Aliases",
                        systemImage: "envelope"
                    )
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let lastError = appModel.lastError {
                    Text(lastError)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(.bar)
                }
            }
        }
        .searchable(text: $model.searchText, prompt: "Search aliases")
        .onChange(of: model.searchText) { model.scheduleSearch() }
        .task(id: appModel.session) { await model.reload() }
        .frame(minWidth: 420, minHeight: 320)
    }

    @ViewBuilder private var listFooter: some View {
        if model.isLoading {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
        } else if let errorMessage = model.errorMessage {
            HStack {
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Try Again") { Task { await model.loadNextPage() } }
            }
        }
    }
}

private struct AliasRow: View {
    let alias: Alias
    let stateLabel: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(alias.email)
                if let note = alias.note, !note.isEmpty {
                    Text(note)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if alias.pinned {
                Image(systemName: "pin.fill")
                    .foregroundStyle(.secondary)
                    .help("Pinned")
                    .accessibilityLabel("Pinned")
            }
            Text(stateLabel)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

/// Mirrors the menu bar's alias submenu, plus pinning and enabling without a timer.
private struct AliasRowActions: View {
    let alias: Alias
    let model: AllAliasesModel

    var body: some View {
        Group {
            Button(alias.pinned ? "Unpin" : "Pin") {
                Task { await model.togglePin(alias) }
            }
            Button("Copy Address") { model.copy(alias) }
            Divider()
            switch model.state(of: alias) {
            case .disabled:
                durationButtons(title: { "Enable for \($0)" })
                Button("Enable Permanently") {
                    Task { await model.enablePermanently(alias) }
                }
            case .timed:
                disableButton
                Button("Keep Enabled") {
                    Task { await model.keepEnabled(alias) }
                }
                Menu("Extend") {
                    durationButtons(title: { $0 })
                }
            case .enabled:
                disableButton
                durationButtons(title: { "Disable After \($0)" })
            }
        }
        .disabled(model.isBusy(alias))
    }

    private var disableButton: some View {
        Button("Disable") {
            Task { await model.disable(alias) }
        }
    }

    private func durationButtons(title: @escaping (String) -> String) -> some View {
        ForEach(AliasDuration.allCases, id: \.self) { duration in
            Button(title(duration.title)) {
                Task { await model.enable(alias, for: duration) }
            }
        }
    }
}
