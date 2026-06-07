import SwiftUI
import MapKit

/// A map of your saved spots (those with coordinates). Linked spots are green,
/// unlinked are orange. Tap a pin to link it, open it in Maps, or jump to Resy.
struct SpotsMapView: View {
    let pins: [PinDTO]
    let viewModel: PinsViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var position: MapCameraPosition = .automatic
    @State private var selected: PinDTO?
    @State private var linkingPin: PinDTO?

    private var mapped: [PinDTO] { pins.filter { $0.lat != 0 || $0.lng != 0 } }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $position) {
                    ForEach(mapped) { pin in
                        Annotation(pin.name, coordinate: CLLocationCoordinate2D(latitude: pin.lat, longitude: pin.lng)) {
                            marker(pin)
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat))
                .ignoresSafeArea(edges: .bottom)

                if let selected { card(selected) }
            }
            .navigationTitle("Spots map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(RBColor.accent)
                }
            }
            .overlay {
                if mapped.isEmpty {
                    ContentUnavailableView(
                        "No mapped spots",
                        systemImage: "mappin.slash",
                        description: Text("Spots added by name don't have a location yet. Add one with search, or share from Apple Maps.")
                    )
                }
            }
            .sheet(item: $linkingPin) { pin in
                NavigationStack { LinkPinView(pin: pin, viewModel: viewModel) }
                    .preferredColorScheme(.dark)
            }
        }
        .tint(RBColor.accent)
    }

    private func marker(_ pin: PinDTO) -> some View {
        let isSelected = selected?.id == pin.id
        return Button {
            selected = isSelected ? nil : pin
        } label: {
            ZStack {
                Circle()
                    .fill(pin.linked ? RBColor.success : RBColor.accent)
                    .frame(width: isSelected ? 34 : 26, height: isSelected ? 34 : 26)
                    .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: isSelected ? 3 : 0))
                Image(systemName: "fork.knife")
                    .font(.system(size: isSelected ? 15 : 12, weight: .bold))
                    .foregroundStyle(.white)
            }
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
    }

    private func card(_ pin: PinDTO) -> some View {
        VStack(alignment: .leading, spacing: RBSpacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(pin.name).font(.system(size: 18, weight: .bold)).foregroundStyle(RBColor.textPrimary)
                    Text(pin.linked ? "Linked · \((pin.provider ?? "").providerDisplayName)" : "Not linked")
                        .font(.system(size: 13))
                        .foregroundStyle(pin.linked ? RBColor.success : RBColor.textMuted)
                }
                Spacer()
                Button { selected = nil } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 22)).foregroundStyle(RBColor.textMuted)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: RBSpacing.md) {
                Button { openInMaps(pin) } label: {
                    Label("Maps", systemImage: "map").frame(maxWidth: .infinity)
                }
                .buttonStyle(.rbSecondary)
                if pin.linked {
                    Button { openOnResy(pin) } label: {
                        Label("Resy", systemImage: "arrow.up.right.square").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.rbSecondary)
                } else {
                    Button { linkingPin = pin } label: {
                        Text("Link").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.rbPrimary)
                }
            }
        }
        .padding(RBSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rbCard()
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    private func openInMaps(_ pin: PinDTO) {
        let q = pin.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "http://maps.apple.com/?ll=\(pin.lat),\(pin.lng)&q=\(q)") { openURL(url) }
    }

    private func openOnResy(_ pin: PinDTO) {
        let q = pin.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://resy.com/cities/ny?query=\(q)") { openURL(url) }
    }
}
