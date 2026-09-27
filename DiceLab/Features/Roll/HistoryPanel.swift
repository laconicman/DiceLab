import SwiftUI

/// The session roll list — M9c's replacement for the horizontal chip
/// strip. A material-background panel above the Roll button: collapsed it
/// caps at a quarter of the screen; tapping the header expands it toward
/// the safe area. Rows are scrollable in either state.
struct HistoryPanel: View {
    /// Settled rolls, oldest first — the controller's `history` contract.
    let rolls: [RollResult]
    /// Height caps measured by the caller against the screen geometry —
    /// the panel itself stays layout-agnostic.
    var collapsedHeight: CGFloat
    var expandedHeight: CGFloat

    @State private var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack {
                    Text("History")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.up")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(expanded ? .degrees(180) : .zero)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? "Collapse roll history"
                                         : "Expand roll history")

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(rolls.reversed()) { roll in
                        // Same shape as the banner but compact ("5+1+3 = 9") —
                        // its own explicit key, since the formats differ.
                        Text(String(localized: "history.equation",
                                    defaultValue: "\(roll.faces.map(String.init).joined(separator: "+")) = \(roll.total)",
                                    comment: "History row — faces joined by '+', then the total"))
                            .font(.callout.monospacedDigit())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(rowTint(roll)?.opacity(0.18) ?? .clear,
                                        in: .rect(cornerRadius: 6))
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxHeight: expanded ? expandedHeight : collapsedHeight,
               alignment: .top)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
    }

    /// Scaffold for per-player row colors: settings will later map a
    /// roll's owner to a tint (board-game turns — each player's figure
    /// moves by their roll). `nil` keeps the row on plain material until
    /// that setting exists.
    private func rowTint(_ roll: RollResult) -> Color? { nil }
}
