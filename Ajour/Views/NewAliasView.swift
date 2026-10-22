import SimpleLoginKit
import SwiftUI

struct NewAliasView: View {
    @Bindable var model: NewAliasModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            FormGroup {
                FormRow("Prefix") {
                    TextField("Prefix", text: $model.prefix, prompt: Text("shop"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { submit() }
                }
                Divider()
                FormRow("Suffix") {
                    suffixControl
                }
                Divider()
                FormRow("Disable after") {
                    Picker("Disable after", selection: $model.expiry) {
                        Text("Never").tag(AliasDuration?.none)
                        ForEach(AliasDuration.allCases, id: \.self) { duration in
                            Text(duration.title).tag(Optional(duration))
                        }
                    }
                    .labelsHidden()
                }
            }
            .disabled(model.isCreating)
            preview
            if !model.canCreate {
                Text("Alias limit reached")
                    .foregroundStyle(.secondary)
            }
            if let errorMessage = model.errorMessage {
                InlineError(message: errorMessage)
            }
            HStack(spacing: 8) {
                Spacer()
                if model.isCreating {
                    ProgressView()
                        .controlSize(.small)
                }
                Button(model.submitTitle) { submit() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canSubmit)
            }
            .controlSize(.large)
        }
        .padding(24)
        .frame(width: 420, alignment: .leading)
        .task { await model.load() }
        .onChange(of: model.isComplete) { _, isComplete in
            if isComplete { close() }
        }
        .onDisappear { model.reset() }
    }

    @ViewBuilder private var suffixControl: some View {
        if model.suffixes.isEmpty {
            if model.errorMessage == nil {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading suffixes…")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .frame(minHeight: 24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: Capsule())
                .accessibilityElement(children: .combine)
            }
        } else {
            Picker("Suffix", selection: $model.suffix) {
                if !model.customSuffixes.isEmpty {
                    Section("Your Domains") { suffixOptions(model.customSuffixes) }
                }
                if !model.sharedSuffixes.isEmpty {
                    Section("SimpleLogin Domains") { suffixOptions(model.sharedSuffixes) }
                }
            }
            .labelsHidden()
        }
    }

    private func suffixOptions(_ suffixes: [AliasSuffix]) -> some View {
        ForEach(suffixes, id: \.self) { suffix in
            Text(suffix.suffix).tag(Optional(suffix))
        }
    }

    private var preview: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let address = model.previewAddress {
                previewSymbol
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        Text(address)
                            .fontWeight(.semibold)
                            .fixedSize()
                        expiryNote
                            .fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(address)
                            .fontWeight(.semibold)
                        expiryNote
                    }
                }
                .textSelection(.enabled)
            } else if model.suffixes.isEmpty && model.errorMessage == nil {
                previewSymbol
                Text("The address preview appears once suffixes are loaded.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var previewSymbol: some View {
        Image(systemName: "at")
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var expiryNote: some View {
        if let note = model.expiryNote {
            Text(note)
                .foregroundStyle(.secondary)
        }
    }

    private func submit() {
        guard model.canSubmit else { return }
        Task { await model.create() }
    }
}

private struct FormRow<Control: View>: View {
    private static var controlWidth: CGFloat { 224 }

    let title: LocalizedStringKey
    let control: Control

    init(_ title: LocalizedStringKey, @ViewBuilder control: () -> Control) {
        self.title = title
        self.control = control()
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            control
                .buttonSizing(.flexible)
                .frame(width: Self.controlWidth)
        }
        .padding(.vertical, 4)
    }
}
