import SwiftUI

enum AppStyle {
    static let cardRadius: CGFloat = 14
    static let card = Color.primary.opacity(0.045)
    static let cardStroke = Color.primary.opacity(0.06)
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.82)
}

/// Rounded LockDay-style surface.
struct CardBackground: ViewModifier {
    var padding: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: AppStyle.cardRadius, style: .continuous)
                    .fill(AppStyle.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppStyle.cardRadius, style: .continuous)
                    .strokeBorder(AppStyle.cardStroke)
            )
    }
}

extension View {
    func card(padding: CGFloat = 12) -> some View { modifier(CardBackground(padding: padding)) }
}

struct CountBadge: View {
    let count: Int
    let accent: Color

    var body: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .contentTransition(.numericText(value: Double(count)))
            .padding(.horizontal, 6)
            .frame(minWidth: 20, minHeight: 20)
            .background(Capsule().fill(accent))
            .animation(AppStyle.spring, value: count)
    }
}

struct SectionHeaderView: View {
    let section: TaskListSection

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: section.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(section.accent)
            Text(section.title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(section.accent == .gray ? Color.primary : section.accent)
            Spacer()
            CountBadge(count: section.tasks.count, accent: section.accent)
        }
        .padding(.horizontal, 4)
    }
}

/// Small capsule label: project name, due date, etc.
struct Chip: View {
    let text: String
    var icon: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 3) {
            if let icon { Image(systemName: icon).font(.system(size: 9, weight: .semibold)) }
            Text(Self.shortened(text)).lineLimit(1)
        }
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(tint.opacity(0.13)))
    }

    /// Caps long labels (e.g. project names) so chips never force rows wider.
    private static func shortened(_ text: String, limit: Int = 22) -> String {
        text.count > limit ? String(text.prefix(limit - 1)) + "…" : text
    }
}

/// Animated check ring tinted by priority.
struct CheckCircle: View {
    let isOn: Bool
    let tint: Color
    var size: CGFloat = 17

    var body: some View {
        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(isOn ? Palette.done : tint)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, value: isOn)
            .frame(width: size + 3, height: size + 3)
            .contentShape(Circle())
    }
}

struct PriorityLabel: View {
    let priority: Priority

    var body: some View {
        Label {
            Text(priority.displayName)
        } icon: {
            Image(systemName: "flag.fill").foregroundStyle(Palette.color(for: priority))
        }
    }
}

/// Shared quick choices for due dates.
enum DueChoice: CaseIterable, Identifiable {
    case today, tomorrow, nextWeek, none

    var id: Self { self }

    var title: String {
        switch self {
        case .today: return "Today"
        case .tomorrow: return "Tomorrow"
        case .nextWeek: return "Next Week"
        case .none: return "No Date"
        }
    }

    var icon: String {
        switch self {
        case .today: return "sun.max"
        case .tomorrow: return "sunrise"
        case .nextWeek: return "calendar.badge.clock"
        case .none: return "xmark.circle"
        }
    }

    var date: Date? {
        switch self {
        case .today: return TaskDate.day(offset: 0)
        case .tomorrow: return TaskDate.day(offset: 1)
        case .nextWeek: return TaskDate.day(offset: 7)
        case .none: return nil
        }
    }
}
