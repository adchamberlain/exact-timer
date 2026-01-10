import SwiftUI
import SwiftData

/// Main view showing list of user's watches and their accuracy
struct WatchListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Watch.createdAt, order: .reverse) private var watches: [Watch]

    @State private var showingAddWatch = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if watches.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(watches) { watch in
                            NavigationLink(destination: WatchDetailView(watch: watch)) {
                                WatchRowView(watch: watch)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Spacer()
                        .frame(height: 20)

                    addWatchButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            .background(Color.black)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Watch Accuracy")
                        .font(.terminalTitle)
                        .foregroundColor(.terminalGreen)
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showingAddWatch) {
                WatchSetupView()
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
                .frame(height: 60)

            Text("No watches yet")
                .font(.terminalTitle)
                .foregroundColor(.terminalGreen)

            Text("Add your first mechanical watch\nto start tracking its accuracy")
                .font(.terminalCaption)
                .foregroundColor(.terminalDim)
                .multilineTextAlignment(.center)

            Spacer()
                .frame(height: 20)
        }
    }

    private var addWatchButton: some View {
        Button {
            showingAddWatch = true
        } label: {
            HStack {
                Text("[+]")
                    .font(.terminal(18))
                Text("Add Watch")
                    .font(.terminalBody)
            }
            .foregroundColor(.terminalBright)
            .padding(.vertical, 12)
            .padding(.horizontal, 24)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.terminalGreen, lineWidth: 1)
            )
        }
    }
}

/// Row view for a single watch in the list
struct WatchRowView: View {
    let watch: Watch

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(watch.name)
                        .font(.terminalTitle)
                        .foregroundColor(.terminalBright)

                    if let brand = watch.brand {
                        Text(brand)
                            .font(.terminalSmall)
                            .foregroundColor(.terminalDim)
                    }
                }

                Spacer()

                // Status indicator
                statusIndicator
            }

            // Accuracy info
            if watch.isModelTrained {
                accuracyInfo
            } else {
                Text("> Setup required")
                    .font(.terminalSmall)
                    .foregroundColor(.yellow)
            }
        }
        .padding(16)
        .background(Color.black)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.terminalDim, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if watch.isModelTrained {
            Text("[READY]")
                .font(.terminalSmall)
                .foregroundColor(.terminalGreen)
        } else {
            Text("[SETUP]")
                .font(.terminalSmall)
                .foregroundColor(.yellow)
        }
    }

    @ViewBuilder
    private var accuracyInfo: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading) {
                Text("Readings")
                    .font(.terminalSmall)
                    .foregroundColor(.terminalDim)
                Text("\(watch.readings.count)")
                    .font(.terminalBody)
                    .foregroundColor(.terminalGreen)
            }

            if let avgDeviation = watch.averageDeviationPerDay {
                VStack(alignment: .leading) {
                    Text("Avg/Day")
                        .font(.terminalSmall)
                        .foregroundColor(.terminalDim)
                    Text(formatDeviation(avgDeviation))
                        .font(.terminalBody)
                        .foregroundColor(deviationColor(avgDeviation))
                }
            }
        }
    }

    private func formatDeviation(_ seconds: Double) -> String {
        let absSeconds = abs(seconds)
        let sign = seconds >= 0 ? "+" : "-"
        return String(format: "%@%.1fs", sign, absSeconds)
    }

    private func deviationColor(_ seconds: Double) -> Color {
        let absSeconds = abs(seconds)
        if absSeconds < 5 {
            return .terminalGreen
        } else if absSeconds < 15 {
            return .yellow
        } else {
            return .red
        }
    }
}

#Preview {
    WatchListView()
        .modelContainer(for: Watch.self, inMemory: true)
}
