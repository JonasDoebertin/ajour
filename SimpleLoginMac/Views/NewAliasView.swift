import SimpleLoginKit
import SwiftUI

struct NewAliasView: View {
    static let windowID = "new-alias"

    @Bindable var model: NewAliasModel
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Form {
                TextField("Prefix", text: $model.prefix, prompt: Text("shop"))
                    .onSubmit { submit() }
                if model.suffixes.isEmpty {
                    LabeledContent("Suffix") {
                        if model.isLoading {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                } else {
                    Picker("Suffix", selection: $model.suffix) {
                        ForEach(model.suffixes, id: \.self) { suffix in
                            Text(suffix.suffix).tag(Optional(suffix))
                        }
                    }
                }
                Picker("Disable after", selection: $model.expiry) {
                    Text("Never").tag(AliasDuration?.none)
                    ForEach(AliasDuration.allCases, id: \.self) { duration in
                        Text(duration.title).tag(Optional(duration))
                    }
                }
            }
            if !model.canCreate {
                Text("Alias limit reached")
                    .foregroundStyle(.secondary)
            }
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
            HStack {
                if model.isCreating {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                Button("Create") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canSubmit)
            }
        }
        .padding(24)
        .frame(width: 420, alignment: .leading)
        .task { await model.load() }
        .onChange(of: model.isComplete) { _, isComplete in
            if isComplete { dismissWindow(id: Self.windowID) }
        }
        .onDisappear { model.reset() }
    }

    private func submit() {
        guard model.canSubmit else { return }
        Task { await model.create() }
    }
}
