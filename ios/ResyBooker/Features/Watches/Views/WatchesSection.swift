import SwiftUI

/// The Watches half of the Drops tab: standing polls on one venue + date that
/// notify (or auto-book) the moment a cancellation opens up. Rendered under the
/// drops list because both are "get me in" automations you check on at night.
struct WatchesSection: View {
    var viewModel: WatchesViewModel
    @Binding var showingCreate: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: RBSpacing.md) {
            HStack {
                RBSectionLabel(title: "WATCHES")
                Spacer()
                if !viewModel.watches.isEmpty {
                    Button { showingCreate = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(RBColor.accent)
                    }
                    .accessibilityLabel("Add a watch")
                }
            }
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            VStack(spacing: 11) {
                ForEach(0..<2, id: \.self) { _ in
                    SkeletonBlock(width: nil, height: 76, cornerRadius: RBRadius.card)
                }
            }
        case .loaded where viewModel.watches.isEmpty:
            emptyCard
        case .loaded:
            VStack(spacing: 11) {
                ForEach(viewModel.watches) { watch in
                    NavigationLink {
                        WatchDetailView(watch: watch, viewModel: viewModel)
                    } label: {
                        WatchCard(watch: watch)
                    }
                    .buttonStyle(.plain)
                }
            }
        case .failed where viewModel.isAuthError:
            // The drops list above already shows the auth prompt; stay quiet.
            EmptyView()
        case .failed:
            InlineErrorView(
                title: "Couldn't load watches",
                message: viewModel.errorMessage ?? "Your booking server didn't respond.",
                retry: { Task { await viewModel.load() } }
            )
        }
    }

    /// Compact inline empty state — the section shouldn't dominate the tab the
    /// way a full-screen EmptyStateView would.
    private var emptyCard: some View {
        Button { showingCreate = true } label: {
            HStack(spacing: RBSpacing.md) {
                Image(systemName: "binoculars")
                    .font(.system(size: 20))
                    .foregroundStyle(RBColor.textMuted)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Watch a sold-out night")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(RBColor.textPrimary)
                    Text("We re-check a venue and date every minute and tell you the second a table frees up.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(RBColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(RBColor.accent)
            }
            .padding(RBSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .rbCard()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a watch")
    }
}

// MARK: - Status badge

struct WatchStatusBadge: View {
    let watch: WatchDTO

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: watch.statusIcon).font(.system(size: 11))
            Text(watch.statusLabel).font(.system(size: 11.5, weight: .bold)).tracking(0.3)
        }
        .foregroundStyle(watch.statusTint)
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(watch.statusSoft, in: Capsule())
    }
}

// MARK: - Overview card

struct WatchCard: View {
    let watch: WatchDTO

    var body: some View {
        VStack(alignment: .leading, spacing: RBSpacing.sm) {
            HStack(alignment: .center, spacing: RBSpacing.sm) {
                Text(watch.venueName)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(RBColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: RBSpacing.sm)
                WatchStatusBadge(watch: watch)
            }
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 12))
                    .foregroundStyle(RBColor.textMuted)
                Text("\(watch.dayDisplay) · \(watch.summaryLine)")
                    .font(.system(size: 13))
                    .foregroundStyle(RBColor.textSecondary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(RBColor.textMuted)
            }
        }
        .padding(RBSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rbCard()
        .contentShape(Rectangle())
    }
}
