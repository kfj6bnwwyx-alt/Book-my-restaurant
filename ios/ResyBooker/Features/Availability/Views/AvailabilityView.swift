import SwiftUI

struct AvailabilityView: View {
    @State private var viewModel = AvailabilityViewModel()
    @State private var pendingBooking: BookingPair?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    controls
                    results
                }
                .padding()
            }
            .navigationTitle("Tonight's Tables")
            .background(Color(.systemGroupedBackground))
            .alert("Error", isPresented: $viewModel.showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "Something went wrong")
            }
            .sheet(item: $pendingBooking) { pair in
                BookingConfirmView(
                    venue: pair.venue,
                    slot: pair.slot,
                    day: pair.day,
                    partySize: pair.partySize
                ) {
                    pendingBooking = nil
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            DatePicker(
                "Date",
                selection: $viewModel.day,
                in: Date()...,
                displayedComponents: .date
            )
            DatePicker(
                "Time",
                selection: $viewModel.time,
                displayedComponents: .hourAndMinute
            )
            Stepper(
                "Party of \(viewModel.partySize)",
                value: $viewModel.partySize,
                in: 1...12
            )
            Button {
                Task { await viewModel.search() }
            } label: {
                if viewModel.state == .loading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Find Tables").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.state == .loading)
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var results: some View {
        switch viewModel.state {
        case .idle:
            ContentUnavailableView(
                "Pick a date and search",
                systemImage: "fork.knife",
                description: Text("Checks every linked saved spot at once.")
            )
            .padding(.top, 40)
        case .loaded where viewModel.results.isEmpty:
            ContentUnavailableView(
                "No linked spots yet",
                systemImage: "mappin.slash",
                description: Text("Link pins to venues in the Spots tab first.")
            )
            .padding(.top, 40)
        case .loaded, .failed:
            if !viewModel.availableResults.isEmpty {
                section("Available", viewModel.availableResults)
            }
            if !viewModel.unavailableResults.isEmpty {
                section("No tables", viewModel.unavailableResults)
            }
        case .loading:
            ProgressView().padding(.top, 40)
        }
    }

    private func section(_ title: String, _ items: [VenueAvailabilityDTO]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(items) { venue in
                VenueAvailabilityCard(venue: venue) { slot in
                    pendingBooking = BookingPair(
                        venue: venue,
                        slot: slot,
                        day: DateFormatter.dayKey.string(from: viewModel.day),
                        partySize: viewModel.partySize
                    )
                }
            }
        }
    }
}

struct BookingPair: Identifiable {
    let venue: VenueAvailabilityDTO
    let slot: SlotDTO
    let day: String
    let partySize: Int
    var id: String { "\(venue.id)-\(slot.configToken ?? slot.time ?? "x")" }
}
