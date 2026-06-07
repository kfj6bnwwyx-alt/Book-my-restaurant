import SwiftUI

/// Drops tab: venues that release tables on a schedule. Overview list of tracked
/// drops, each opening a live countdown. Matches the Pencil Drops screens.
struct DropsView: View {
    @State private var viewModel = DropsViewModel()
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                RBColor.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: RBSpacing.lg) {
                        RBScreenHeader(
                            title: "Drops",
                            subtitle: "Hard-to-get tables that release on a schedule."
                        )
                        content
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .serverSettingsSheet(isPresented: $showingSettings) {
                Task { await viewModel.load() }
            }
            .task {
                if AppConfig.hasAppKey, viewModel.state == .idle {
                    await viewModel.load()
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !AppConfig.hasAppKey {
            ConnectServerPrompt { showingSettings = true }.padding(.top, 40)
        } else {
            switch viewModel.state {
            case .idle, .loading:
                VStack(spacing: 11) {
                    ForEach(0..<3, id: \.self) { _ in SkeletonVenueCard() }
                }
            case .loaded where viewModel.drops.isEmpty:
                EmptyStateView(
                    systemImage: "calendar.badge.clock",
                    title: "No drops tracked yet",
                    message: "Add a venue that releases reservations on a schedule, and the next release lands here."
                )
                .padding(.top, 40)
            case .loaded:
                VStack(spacing: 11) {
                    ForEach(viewModel.drops) { drop in
                        NavigationLink {
                            DropCountdownView(drop: drop)
                        } label: {
                            DropCard(drop: drop)
                        }
                        .buttonStyle(.plain)
                    }
                }
            case .failed where viewModel.isAuthError:
                ConnectServerPrompt { showingSettings = true }.padding(.top, 40)
            case .failed:
                InlineErrorView(
                    title: "Couldn't load drops",
                    message: viewModel.errorMessage ?? "Your booking server didn't respond.",
                    retry: { Task { await viewModel.load() } }
                )
                .padding(.top, 40)
            }
        }
    }
}

// MARK: - Status badge (shared by overview + detail)

/// The drop's headline status. Orange is never used here: a release is a status,
/// not an action — green = open / armed, amber = scheduled-but-not-open.
struct DropStatusBadge: View {
    let drop: DropDTO

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11))
            Text(text).font(.system(size: 11.5, weight: .bold)).tracking(0.3)
        }
        .foregroundStyle(tint)
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(soft, in: Capsule())
    }

    private var isArmed: Bool { drop.autobookEnabled }

    private var text: String {
        if isArmed { return "AUTO-BOOK ON" }
        if drop.open { return "OPEN NOW" }
        return "OPENS IN \(drop.opensInShort)"
    }
    private var icon: String {
        if isArmed { return "bolt.fill" }
        if drop.open { return "circle.fill" }
        return "clock"
    }
    private var tint: Color { drop.open || isArmed ? RBColor.success : RBColor.amber }
    private var soft: Color { drop.open || isArmed ? RBColor.successSoft : RBColor.amberSoft }
}

// MARK: - Overview card

struct DropCard: View {
    let drop: DropDTO

    var body: some View {
        VStack(alignment: .leading, spacing: RBSpacing.sm) {
            HStack(alignment: .center, spacing: RBSpacing.sm) {
                Text(drop.venueName)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(RBColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: RBSpacing.sm)
                DropStatusBadge(drop: drop)
            }
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 12))
                    .foregroundStyle(RBColor.textMuted)
                Text(drop.scheduleLine)
                    .font(.system(size: 13))
                    .foregroundStyle(RBColor.textSecondary)
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

// MARK: - Countdown detail

struct DropCountdownView: View {
    let drop: DropDTO

    var body: some View {
        ZStack {
            RBColor.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: RBSpacing.lg) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(drop.venueName)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(RBColor.textPrimary)
                        DropStatusBadge(drop: drop)
                    }

                    if !drop.open { countdownCard }
                    infoCard
                    autobookCard
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    // Live countdown ticking down to the next release.
    private var countdownCard: some View {
        VStack(spacing: RBSpacing.lg) {
            Text("NEXT RELEASE")
                .font(.system(size: 12, weight: .bold))
                .tracking(1)
                .foregroundStyle(RBColor.amber)

            if let release = drop.nextReleaseDate {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    countdownRow(secondsRemaining: max(0, Int(release.timeIntervalSince(context.date))))
                }
            } else {
                countdownRow(secondsRemaining: drop.opensInSeconds)
            }

            Text(releaseDateText)
                .font(.system(size: 14))
                .foregroundStyle(RBColor.textSecondary)
        }
        .padding(.vertical, RBSpacing.xl)
        .frame(maxWidth: .infinity)
        .rbCard()
    }

    private func countdownRow(secondsRemaining s: Int) -> some View {
        let units: [(String, Int)] = [
            ("DAYS", s / 86_400),
            ("HRS", (s % 86_400) / 3_600),
            ("MIN", (s % 3_600) / 60),
            ("SEC", s % 60),
        ]
        return HStack(spacing: RBSpacing.md) {
            ForEach(Array(units.enumerated()), id: \.offset) { index, unit in
                VStack(spacing: 4) {
                    Text(String(format: "%02d", unit.1))
                        .font(.system(size: 38, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(RBColor.textPrimary)
                    Text(unit.0)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(RBColor.textMuted)
                }
                if index < units.count - 1 {
                    Text(":")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(RBColor.textMuted)
                        .padding(.bottom, 16)
                }
            }
        }
    }

    private var infoCard: some View {
        VStack(spacing: 0) {
            infoRow("Releases", drop.cadenceLabel)
            divider
            infoRow("Window", drop.windowLine)
            divider
            infoRow("Release time", drop.releaseTimeDisplay)
        }
        .padding(.horizontal, RBSpacing.lg)
        .rbCard()
    }

    @ViewBuilder
    private var autobookCard: some View {
        let armed = drop.autobookEnabled
        VStack(alignment: .leading, spacing: RBSpacing.md) {
            HStack(spacing: RBSpacing.sm) {
                Image(systemName: armed ? "bolt.fill" : "bolt.slash")
                    .font(.system(size: 18))
                    .foregroundStyle(armed ? RBColor.success : RBColor.textMuted)
                Text(armed ? "Auto-book armed" : "Auto-book off")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(RBColor.textPrimary)
            }
            Text(autobookSummary)
                .font(.system(size: 13))
                .foregroundStyle(RBColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(RBSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rbCard(fill: RBColor.surface2, bordered: false)
    }

    private var autobookSummary: String {
        guard drop.autobookEnabled else {
            return "Watching for the next release. Turn on auto-book to grab a table the instant it opens."
        }
        let ab = drop.autobook
        var parts: [String] = []
        if let p = ab.partySize { parts.append("Party of \(p)") }
        if let days = ab.days, !days.isEmpty { parts.append(days) }
        if let e = ab.earliest, let l = ab.latest { parts.append("\(e) to \(l)") }
        let prefix = parts.isEmpty ? "" : parts.joined(separator: " · ") + ". "
        return prefix + "We grab the best match the instant it opens."
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(RBColor.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(RBColor.textPrimary)
        }
        .padding(.vertical, 13)
    }

    private var divider: some View {
        Rectangle().fill(RBColor.border).frame(height: 1)
    }

    private var releaseDateText: String {
        guard let date = drop.nextReleaseDate else { return "" }
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d 'at' h:mm a"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }
}
