import SimpleLoginKit
import SwiftUI

struct AllAliasesView: View {
    @Bindable var model: AllAliasesModel
    let appModel: AppModel
    let openNewAlias: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.sections) { section in
                    Section(section.title) {
                        ForEach(section.aliases) { alias in
                            AliasRow(alias: alias, status: model.status(of: alias))
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(model.accessibilityLabel(for: alias))
                                .contextMenu { AliasRowActions(alias: alias, model: model) }
                                .onAppear { Task { await model.loadMore(after: alias) } }
                        }
                    }
                    .listRowSeparator(.hidden)
                    .listSectionSeparator(.hidden)
                }
                if model.isLoading, !model.aliases.isEmpty {
                    loadingMore
                }
            }
            .listStyle(.inset)
            .overlay { placeholder }
            .safeAreaInset(edge: .bottom, spacing: 0) { problemBar }
        }
        .navigationSubtitle(model.subtitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ToolbarSearchField(text: $model.searchText, prompt: "Search aliases")
                    .frame(width: 220)
            }
        }
        .onChange(of: model.searchText) { model.scheduleSearch() }
        .task(id: appModel.session) { await model.reload() }
        .frame(minWidth: 420, minHeight: 320)
    }

    private var loadingMore: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Loading more aliases…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder private var placeholder: some View {
        switch model.emptyState {
        case .noAliases:
            ContentUnavailableView {
                Label("No Aliases", systemImage: "envelope.open")
            } description: {
                Text("Aliases you create in SimpleLogin or with Ajour show up here.")
            } actions: {
                Button("New Alias…", action: openNewAlias)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
            }
        case .noMatches(let query):
            ContentUnavailableView {
                Label("No Matching Aliases", systemImage: "magnifyingglass")
            } description: {
                Text("No address or note contains “\(query)”. Check the spelling or try another search.")
            }
        case nil:
            if model.isLoading, model.aliases.isEmpty {
                ProgressView()
            }
        }
    }

    /// Loading problems offer to try again; a failed action on a row explains itself with the app's message.
    @ViewBuilder private var problemBar: some View {
        if let errorMessage = model.errorMessage {
            ProblemBar(title: "Could not load aliases.", detail: errorMessage) {
                Button("Try Again") { Task { await model.loadNextPage() } }
                    .buttonBorderShape(.capsule)
            }
        } else if let lastError = appModel.lastError {
            let message = ProblemMessage(lastError)
            ProblemBar(title: message.title, detail: message.detail) { EmptyView() }
        }
    }
}

private struct AliasRow: View {
    let alias: Alias
    let status: AliasStatus

    var body: some View {
        HStack(spacing: 10) {
            StateSymbolView(kind: status.kind)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(alias.email)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if alias.pinned {
                        Image(systemName: "pin")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                if let note = alias.note, !note.isEmpty {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text(status.words)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Palette.color(StateSymbol.tint(for: status.kind)))
                if let turnsOff = status.turnsOff {
                    Text(turnsOff)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}

private struct ProblemBar<Action: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder let action: Action

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title3)
                .foregroundStyle(Palette.color(Palette.danger))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.semibold)
                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            action
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

/// Mirrors the menu bar's alias submenu, plus pinning and enabling without a timer.
private struct AliasRowActions: View {
    let alias: Alias
    let model: AllAliasesModel

    var body: some View {
        let isBusy = model.isBusy(alias)
        Button(alias.pinned ? "Unpin" : "Pin", systemImage: alias.pinned ? "pin.slash" : "pin") {
            Task { await model.togglePin(alias) }
        }
        .disabled(isBusy)
        Button("Copy Address", systemImage: "doc.on.doc") { model.copy(alias) }
        Divider()
        Group {
            switch model.state(of: alias) {
            case .disabled:
                Menu("Enable for", systemImage: "timer") {
                    durationButtons { await model.enable(alias, for: $0) }
                }
                Button("Enable Permanently", systemImage: "checkmark.circle") {
                    Task { await model.enablePermanently(alias) }
                }
            case .timed:
                keepEnabledButton
                extendMenu
                Divider()
                disableButton
            case .disableFailing:
                Button("Try Again", systemImage: "arrow.clockwise") {
                    Task { await model.retryDisable(alias) }
                }
                keepEnabledButton
                extendMenu
            case .disableRefused:
                keepEnabledButton
                Button("Replace API Key…", systemImage: "key") { model.onReplaceAPIKey() }
            case .enabled:
                Menu("Disable After", systemImage: "timer") {
                    durationButtons { await model.disableAfter(alias, duration: $0) }
                }
                Divider()
                disableButton
            }
        }
        .disabled(isBusy)
    }

    private var keepEnabledButton: some View {
        Button("Keep Enabled", systemImage: "infinity") {
            Task { await model.keepEnabled(alias) }
        }
    }

    private var extendMenu: some View {
        Menu("Extend", systemImage: "goforward.plus") {
            durationButtons { await model.enable(alias, for: $0) }
        }
    }

    private var disableButton: some View {
        Button("Disable", systemImage: "poweroff") {
            Task { await model.disable(alias) }
        }
    }

    private func durationButtons(action: @escaping @MainActor (AliasDuration) async -> Void) -> some View {
        ForEach(AliasDuration.allCases, id: \.self) { duration in
            Button(duration.title) {
                Task { await action(duration) }
            }
        }
    }
}
