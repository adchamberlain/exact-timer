import SwiftUI
import SwiftData

/// Detail view for a single watch showing readings and accuracy trends
struct WatchDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var watch: Watch

    @State private var showingCapture = false
    @State private var showingSetup = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Watch header
                watchHeader

                Divider()
                    .background(Color.terminalDim)

                // Action buttons
                actionButtons

                // Accuracy summary
                if !watch.readings.isEmpty {
                    accuracySummary
                }

                // Readings list
                if !watch.readings.isEmpty {
                    readingsSection
                }

                Spacer()
                    .frame(height: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        .background(Color.black)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(watch.name)
                    .font(.terminalTitle)
                    .foregroundColor(.terminalGreen)
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    deleteWatch()
                } label: {
                    Text("[Delete]")
                        .font(.terminalSmall)
                        .foregroundColor(.red)
                }
            }
        }
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(isPresented: $showingCapture) {
            CaptureReadingView(watch: watch)
        }
        .sheet(isPresented: $showingSetup) {
            WatchSetupView(existingWatch: watch)
        }
    }

    private var watchHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if let brand = watch.brand {
                    Text(brand)
                        .font(.terminalCaption)
                        .foregroundColor(.terminalDim)
                }

                Text("Created \(watch.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.terminalSmall)
                    .foregroundColor(.terminalDim)
            }

            Spacer()

            // Status
            if watch.isModelTrained {
                VStack(alignment: .trailing) {
                    Text("[MODEL READY]")
                        .font(.terminalSmall)
                        .foregroundColor(.terminalGreen)
                }
            } else {
                Text("[NEEDS SETUP]")
                    .font(.terminalSmall)
                    .foregroundColor(.yellow)
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            if watch.isModelTrained {
                Button {
                    showingCapture = true
                } label: {
                    HStack {
                        Text("[+]")
                        Text("New Reading")
                    }
                    .font(.terminalBody)
                    .foregroundColor(.terminalBright)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.terminalGreen, lineWidth: 1)
                    )
                }
            }

            Button {
                showingSetup = true
            } label: {
                Text(watch.isModelTrained ? "[Retrain]" : "[Setup]")
                    .font(.terminalBody)
                    .foregroundColor(watch.isModelTrained ? .terminalDim : .yellow)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(watch.isModelTrained ? Color.terminalDim : Color.yellow, lineWidth: 1)
                    )
            }
        }
    }

    @ViewBuilder
    private var accuracySummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("> Accuracy Summary")
                .font(.terminalTitle)
                .foregroundColor(.terminalGreen)

            HStack(spacing: 30) {
                VStack(alignment: .leading) {
                    Text("Total Readings")
                        .font(.terminalSmall)
                        .foregroundColor(.terminalDim)
                    Text("\(watch.readings.count)")
                        .font(.terminalLarge)
                        .foregroundColor(.terminalBright)
                }

                if let avgDeviation = watch.averageDeviationPerDay {
                    VStack(alignment: .leading) {
                        Text("Avg. Per Day")
                            .font(.terminalSmall)
                            .foregroundColor(.terminalDim)
                        Text(formatDeviation(avgDeviation))
                            .font(.terminalLarge)
                            .foregroundColor(deviationColor(avgDeviation))
                    }
                }
            }

            if let latestReading = watch.readings.sorted(by: { $0.capturedAt > $1.capturedAt }).first {
                Text("Last reading: \(latestReading.capturedAt.formatted())")
                    .font(.terminalSmall)
                    .foregroundColor(.terminalDim)
            }
        }
        .padding(16)
        .background(Color.black)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.terminalDim, lineWidth: 1)
        )
    }

    private var readingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("> Reading History")
                .font(.terminalTitle)
                .foregroundColor(.terminalGreen)

            ForEach(watch.readings.sorted(by: { $0.capturedAt > $1.capturedAt })) { reading in
                ReadingRowView(reading: reading)
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

    private func deleteWatch() {
        // Delete model file if exists
        if let modelPath = watch.trainedModelPath {
            try? FileManager.default.removeItem(atPath: modelPath)
        }
        modelContext.delete(watch)
        dismiss()
    }
}

struct ReadingRowView: View {
    let reading: WatchReading

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(reading.capturedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.terminalCaption)
                    .foregroundColor(.terminalGreen)

                Text("Watch: \(reading.watchTimeString)")
                    .font(.terminalSmall)
                    .foregroundColor(.terminalDim)
            }

            Spacer()

            VStack(alignment: .trailing) {
                Text(reading.deviationString)
                    .font(.terminalBody)
                    .foregroundColor(deviationColor)

                if reading.wasManuallyAdjusted {
                    Text("(adjusted)")
                        .font(.terminalSmall)
                        .foregroundColor(.terminalDim)
                }
            }
        }
        .padding(12)
        .background(Color.black)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.terminalDim.opacity(0.5), lineWidth: 1)
        )
    }

    private var deviationColor: Color {
        let absSeconds = abs(reading.deviationSeconds)
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
    NavigationStack {
        WatchDetailView(watch: Watch(name: "Test Watch", brand: "Seiko"))
    }
    .modelContainer(for: Watch.self, inMemory: true)
}
