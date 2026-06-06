import SwiftUI
import SwiftData

struct PinsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: PinsViewModel?
    @State private var showingImporter = false
    @State private var geoJSONText = ""

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    content(vm)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Saved Spots")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingImporter = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel("Import pins")
                }
            }
            .sheet(isPresented: $showingImporter) {
                ImportSheet(text: $geoJSONText) {
                    Task { await viewModel?.importGeoJSON(geoJSONText) }
                }
            }
            .task {
                if viewModel == nil {
                    viewModel = PinsViewModel(modelContext: modelContext)
                    await viewModel?.load()
                }
            }
        }
    }

    @ViewBuilder
    private func content(_ vm: PinsViewModel) -> some View {
        if vm.pins.isEmpty {
            ContentUnavailableView {
                Label("No pins yet", systemImage: "mappin.and.ellipse")
            } description: {
                Text("Import your Google Maps saved places to get started.")
            } actions: {
                Button("Import GeoJSON") { showingImporter = true }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            List {
                Section {
                    ForEach(vm.pins) { pin in
                        NavigationLink {
                            LinkPinView(pin: pin, viewModel: vm)
                        } label: {
                            PinRow(pin: pin)
                        }
                    }
                } header: {
                    Text("\(vm.linkedCount) of \(vm.pins.count) linked")
                }
            }
            .refreshable { await vm.load() }
            .alert("Error", isPresented: Binding(
                get: { vm.showingError },
                set: { vm.showingError = $0 }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
    }
}

struct PinRow: View {
    let pin: PinDTO
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: pin.linked ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(pin.linked ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(pin.name).font(.body)
                if let provider = pin.provider, pin.linked {
                    Text(provider.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let addr = pin.address {
                    Text(addr).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ImportSheet: View {
    @Binding var text: String
    let onImport: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Paste the GeoJSON from Google Takeout (Saved > your list).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextEditor(text: $text)
                    .font(.system(.caption, design: .monospaced))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.quaternary)
                    )
            }
            .padding()
            .navigationTitle("Import Pins")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { onImport(); dismiss() }
                        .disabled(text.isEmpty)
                }
            }
        }
    }
}
