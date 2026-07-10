import SwiftUI

/// First-run flow, shown once (existing installs with a key skip it): what the
/// app does, how the three tabs fit together, then connect the server. All of
/// it is skippable — every screen already teaches its own empty state.
struct OnboardingView: View {
    var onDone: () -> Void

    @State private var page = 0
    @State private var showingKey = false

    private let lastPage = 2

    var body: some View {
        ZStack {
            RBColor.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if page < lastPage {
                        Button("Skip") { onDone() }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(RBColor.textMuted)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 10)
                .frame(height: 44)

                TabView(selection: $page) {
                    welcome.tag(0)
                    howItWorks.tag(1)
                    connect.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                pageDots
                    .padding(.bottom, RBSpacing.lg)

                footer
                    .padding(.horizontal, 22)
                    .padding(.bottom, RBSpacing.section)
            }
        }
        .preferredColorScheme(.dark)
        .serverSettingsSheet(isPresented: $showingKey) { onDone() }
    }

    // MARK: - Pages

    private var welcome: some View {
        VStack(spacing: RBSpacing.xl) {
            Spacer()
            ZStack {
                Circle()
                    .fill(RBColor.accentSoft)
                Image(systemName: "fork.knife")
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(RBColor.accent)
            }
            .frame(width: 128, height: 128)

            VStack(spacing: RBSpacing.sm) {
                Text("Never miss a table")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(RBColor.textPrimary)
                Text("ResyBooker checks the restaurants you care about, catches releases and cancellations, and books before anyone else can.")
                    .font(.system(size: 15))
                    .foregroundStyle(RBColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 320)
            Spacer()
        }
        .padding(.horizontal, 22)
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: RBSpacing.xl) {
            Spacer()
            Text("Three tabs, one job")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(RBColor.textPrimary)

            VStack(spacing: RBSpacing.md) {
                step(
                    icon: "mappin.and.ellipse",
                    title: "Spots",
                    text: "Save the restaurants you want — search Apple Maps, share from other apps, or import a Google list — and link them to Resy or OpenTable."
                )
                step(
                    icon: "calendar",
                    title: "Tables",
                    text: "One search shows which of your spots has a table tonight, or any night — no more checking apps one by one."
                )
                step(
                    icon: "clock.badge.checkmark",
                    title: "Drops",
                    text: "For the impossible ones: track scheduled release drops with a live countdown, or watch a sold-out night for cancellations. Auto-book if you want."
                )
            }
            Spacer()
        }
        .padding(.horizontal, 22)
    }

    private var connect: some View {
        VStack(spacing: RBSpacing.xl) {
            Spacer()
            ZStack {
                Circle()
                    .fill(RBColor.surface)
                    .overlay(Circle().stroke(RBColor.border, lineWidth: 1))
                Image(systemName: "key.horizontal")
                    .font(.system(size: 40))
                    .foregroundStyle(RBColor.accent)
            }
            .frame(width: 108, height: 108)

            VStack(spacing: RBSpacing.sm) {
                Text("Connect your server")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(RBColor.textPrimary)
                Text("The app talks to your own booking server. Paste the app key from Home Assistant → Apps → ResyBooker → Configuration. It stays in your device's Keychain.")
                    .font(.system(size: 15))
                    .foregroundStyle(RBColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 320)
            Spacer()
        }
        .padding(.horizontal, 22)
    }

    private func step(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: RBSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(RBColor.accent)
                .frame(width: 32)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(RBColor.textPrimary)
                Text(text)
                    .font(.system(size: 13.5))
                    .foregroundStyle(RBColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(RBSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rbCard()
    }

    // MARK: - Chrome

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0...lastPage, id: \.self) { i in
                Capsule()
                    .fill(i == page ? RBColor.accent : RBColor.border)
                    .frame(width: i == page ? 22 : 7, height: 7)
                    .animation(.easeOut(duration: 0.2), value: page)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if page < lastPage {
            Button("Continue") {
                withAnimation { page += 1 }
            }
            .buttonStyle(.rbPrimary)
        } else {
            VStack(spacing: RBSpacing.md) {
                Button("Enter app key") { showingKey = true }
                    .buttonStyle(.rbPrimary)
                Button("Not yet — look around first") { onDone() }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(RBColor.textMuted)
            }
        }
    }
}

#Preview {
    OnboardingView(onDone: {})
}
