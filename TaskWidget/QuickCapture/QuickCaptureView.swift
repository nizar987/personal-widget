import SwiftUI

private struct QuickCaptureSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

struct QuickCaptureView: View {
    let session: QuickCaptureSession
    /// Returns true when saved. `keepOpen` is ⇧↵ ("add another").
    let onSave: (QuickCaptureDraft, _ keepOpen: Bool) async -> Bool
    let onClose: () -> Void
    /// Reports the content size so the panel can grow/shrink (e.g. when an error appears).
    var onSizeChange: (CGSize) -> Void = { _ in }

    @FocusState private var focused: Bool
    @State private var isSaving = false
    @State private var savedPulse = 0

    private var draft: QuickCaptureDraft {
        QuickCaptureParser.parse(session.text, projects: session.projects)
    }

    var body: some View {
        @Bindable var session = session
        let draft = draft
        let suggestions = session.suggestions
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: savedPulse > 0 && !isSaving ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(savedPulse > 0 && !isSaving ? Palette.done : Color.accentColor)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: savedPulse)
                TextField("New task…", text: $session.text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .focused($focused)
                    .onSubmit { submit(keepOpen: NSEvent.modifierFlags.contains(.shift)) }
                    .disabled(isSaving)
                if isSaving {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            if !suggestions.isEmpty {
                SuggestionList(suggestions: suggestions,
                               selectedIndex: min(session.selectedIndex, suggestions.count - 1),
                               onHover: { session.selectedIndex = $0 },
                               onPick: { pick in
                                   session.accept(pick)
                                   focused = true
                               })
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider().opacity(0.5)

            HStack(spacing: 6) {
                if session.text.isEmpty {
                    syntaxHint
                } else {
                    Chip(text: draft.project ?? session.defaultProject, icon: "folder",
                         tint: draft.project == nil ? .secondary : Palette.project)
                    Chip(text: (draft.priority ?? .medium).displayName, icon: "flag.fill",
                         tint: draft.priority.map(Palette.color(for:)) ?? .secondary)
                    Chip(text: dueText(draft.due), icon: "calendar",
                         tint: draft.due == nil ? .secondary : Palette.upcoming)
                }
                Spacer(minLength: 8)
                keyHint(completing: !suggestions.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .animation(AppStyle.spring, value: draft)
            .animation(.easeOut(duration: 0.12), value: suggestions.map(\.id))

            if let error = session.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Palette.today)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                    .transition(.opacity)
            }
        }
        .frame(width: QuickCaptureLayout.width)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .background(GeometryReader { geo in
            Color.clear.preference(key: QuickCaptureSizeKey.self, value: geo.size)
        })
        .onPreferenceChange(QuickCaptureSizeKey.self) { onSizeChange($0) }
        .onExitCommand(perform: onClose)
        .onAppear { focused = true }
        .onChange(of: session.presentation) {
            savedPulse = 0
            focused = true
        }
    }

    private var syntaxHint: some View {
        HStack(spacing: 10) {
            hintToken("#project")
            hintToken("!high")
            hintToken("besok · fri · 12/10")
        }
    }

    private func hintToken(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
    }

    private func keyHint(completing: Bool) -> some View {
        Text(completing ? "⇥ complete   ↑↓ choose   ↵ add" : "↵ add   ⇧↵ add another   esc close")
            .font(.system(size: 11, design: .rounded))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .fixedSize()
    }

    private func dueText(_ due: Date?) -> String {
        guard let due else { return "No date" }
        if due == TaskDate.day(offset: 0) { return "Today" }
        if due == TaskDate.day(offset: 1) { return "Tomorrow" }
        return due.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private func submit(keepOpen: Bool) {
        let current = draft
        guard !current.title.trimmingCharacters(in: .whitespaces).isEmpty, !isSaving else {
            session.errorMessage = session.text.isEmpty ? nil : "Add a title, not just #project / !priority / date."
            return
        }
        session.errorMessage = nil
        isSaving = true
        _Concurrency.Task {
            let saved = await onSave(current, keepOpen)
            isSaving = false
            if saved {
                savedPulse += 1
                session.text = ""
                focused = true
            }
        }
    }
}

/// Autocomplete rows under the text field. Hover highlights, click accepts.
private struct SuggestionList: View {
    let suggestions: [QuickCaptureSuggestion]
    let selectedIndex: Int
    let onHover: (Int) -> Void
    let onPick: (QuickCaptureSuggestion) -> Void

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                Button { onPick(suggestion) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: icon(for: suggestion.kind))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(tint(for: suggestion.kind))
                            .frame(width: 18)
                        Text(suggestion.label)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(suggestion.detail)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if index == selectedIndex {
                            Text("⇥")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(index == selectedIndex ? Color.accentColor.opacity(0.18) : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { if $0 { onHover(index) } }
            }
        }
    }

    private func icon(for kind: QuickCaptureSuggestion.Kind) -> String {
        switch kind {
        case .project: return "folder.fill"
        case .priority: return "flag.fill"
        case .date: return "calendar"
        case .title: return "clock.arrow.circlepath"
        }
    }

    private func tint(for kind: QuickCaptureSuggestion.Kind) -> Color {
        switch kind {
        case .project: return Palette.project
        case .priority: return Palette.today
        case .date: return Palette.upcoming
        case .title: return .secondary
        }
    }
}
