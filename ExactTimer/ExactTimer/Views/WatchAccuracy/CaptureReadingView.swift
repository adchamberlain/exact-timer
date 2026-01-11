import SwiftUI
import SwiftData

/// View for capturing a new accuracy reading from a watch
struct CaptureReadingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var ntpService: NTPService

    let watch: Watch

    @State private var capturedImage: UIImage?
    @State private var showingCamera: Bool = false
    @State private var prediction: WatchMLService.TimePrediction?
    @State private var captureTime: Date?

    @State private var adjustedHour: Int = 12
    @State private var adjustedMinute: Int = 0
    @State private var adjustedSecond: Int = 0
    @State private var isAdjusting: Bool = false

    @State private var isProcessing: Bool = false
    @State private var errorMessage: String?

    @StateObject private var mlService = WatchMLService()

    enum CaptureState {
        case ready
        case captured
        case predicted
        case adjusting
        case saved
    }

    @State private var state: CaptureState = .ready

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Reference time display
                    referenceTimeDisplay

                    Divider()
                        .background(Color.terminalDim)

                    // Main content based on state
                    switch state {
                    case .ready:
                        captureSection
                    case .captured, .predicted:
                        predictionSection
                    case .adjusting:
                        adjustmentSection
                    case .saved:
                        savedSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
            .background(Color.black)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("New Reading")
                        .font(.terminalTitle)
                        .foregroundColor(.terminalGreen)
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.terminalDim)
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    // MARK: - Reference Time Display

    private var referenceTimeDisplay: some View {
        VStack(spacing: 8) {
            Text("> Reference Time (NTP)")
                .font(.terminalSmall)
                .foregroundColor(.terminalDim)

            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                Text(formatTime(ntpService.now()))
                    .font(.terminal(32))
                    .foregroundColor(.terminalBright)
                    .monospacedDigit()
            }

            if ntpService.isSynced {
                Text("Synced with NIST")
                    .font(.terminalSmall)
                    .foregroundColor(.terminalGreen)
            } else {
                Text("Not synced - accuracy may be affected")
                    .font(.terminalSmall)
                    .foregroundColor(.yellow)
            }
        }
        .padding(.vertical, 16)
    }

    // MARK: - Capture Section

    private var captureSection: some View {
        VStack(spacing: 20) {
            Text("> Capture Your Watch")
                .font(.terminalTitle)
                .foregroundColor(.terminalGreen)

            Text("Take a photo of your \(watch.name)\npointing at the watch face")
                .font(.terminalCaption)
                .foregroundColor(.terminalDim)
                .multilineTextAlignment(.center)

            Button {
                showingCamera = true
            } label: {
                VStack(spacing: 16) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 60))
                        .foregroundColor(.terminalGreen)

                    Text("Tap to capture")
                        .font(.terminalBody)
                        .foregroundColor(.terminalGreen)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.terminalGreen, style: StrokeStyle(lineWidth: 2, dash: [8]))
                )
            }
            .sheet(isPresented: $showingCamera) {
                ReadingCameraPicker(ntpService: ntpService) { image, timestamp in
                    capturedImage = image
                    captureTime = timestamp  // NTP time captured at exact moment of photo
                    state = .captured
                    Task {
                        await processImage()
                    }
                }
            }
        }
    }

    // MARK: - Prediction Section

    private var predictionSection: some View {
        VStack(spacing: 20) {
            if let image = capturedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.terminalGreen, lineWidth: 2)
                    )
            }

            if isProcessing {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.terminalGreen)

                    Text("Analyzing watch face...")
                        .font(.terminalCaption)
                        .foregroundColor(.terminalDim)
                }
            } else if let prediction = prediction {
                VStack(spacing: 12) {
                    Text("> Detected Time")
                        .font(.terminalSmall)
                        .foregroundColor(.terminalDim)

                    Text(prediction.timeString)
                        .font(.terminal(40))
                        .foregroundColor(.terminalBright)

                    Text("Confidence: \(Int(prediction.confidence * 100))%")
                        .font(.terminalSmall)
                        .foregroundColor(prediction.confidence > 0.7 ? .terminalGreen : .yellow)

                    // Deviation preview
                    if let captureTime = captureTime {
                        let deviation = calculateDeviation(
                            watchHour: prediction.hour,
                            watchMinute: prediction.minute,
                            watchSecond: prediction.second,
                            referenceTime: captureTime
                        )
                        Text("Deviation: \(formatDeviation(deviation))")
                            .font(.terminalBody)
                            .foregroundColor(deviationColor(deviation))
                    }
                }

                HStack(spacing: 16) {
                    Button {
                        adjustedHour = prediction.hour
                        adjustedMinute = prediction.minute
                        adjustedSecond = prediction.second
                        state = .adjusting
                    } label: {
                        Text("[Adjust]")
                            .font(.terminalBody)
                            .foregroundColor(.terminalDim)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 20)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.terminalDim, lineWidth: 1)
                            )
                    }

                    Button {
                        saveReading(wasAdjusted: false)
                    } label: {
                        Text("[Confirm]")
                            .font(.terminalBody)
                            .foregroundColor(.terminalBright)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 20)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.terminalGreen, lineWidth: 1)
                            )
                    }
                }
            } else if let error = errorMessage {
                VStack(spacing: 12) {
                    Text("Prediction failed")
                        .font(.terminalBody)
                        .foregroundColor(.red)

                    Text(error)
                        .font(.terminalSmall)
                        .foregroundColor(.terminalDim)

                    Button {
                        adjustedHour = 12
                        adjustedMinute = 0
                        adjustedSecond = 0
                        state = .adjusting
                    } label: {
                        Text("[Enter Manually]")
                            .font(.terminalBody)
                            .foregroundColor(.terminalGreen)
                    }
                }
            }

            Button {
                resetCapture()
            } label: {
                Text("[Retake Photo]")
                    .font(.terminalSmall)
                    .foregroundColor(.terminalDim)
            }
        }
    }

    // MARK: - Adjustment Section

    private var adjustmentSection: some View {
        VStack(spacing: 20) {
            Text("> Adjust Time")
                .font(.terminalTitle)
                .foregroundColor(.terminalGreen)

            Text("Set the exact time shown on your watch")
                .font(.terminalCaption)
                .foregroundColor(.terminalDim)

            if let image = capturedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Time picker
            HStack(spacing: 4) {
                Picker("Hour", selection: $adjustedHour) {
                    ForEach(0..<24) { hour in
                        Text("\(hour)").tag(hour)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 60)

                Text(":")
                    .font(.terminalLarge)
                    .foregroundColor(.terminalGreen)

                Picker("Minute", selection: $adjustedMinute) {
                    ForEach(0..<60) { minute in
                        Text(String(format: "%02d", minute)).tag(minute)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 60)

                Text(":")
                    .font(.terminalLarge)
                    .foregroundColor(.terminalGreen)

                Picker("Second", selection: $adjustedSecond) {
                    ForEach(0..<60) { second in
                        Text(String(format: "%02d", second)).tag(second)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 60)
            }
            .frame(height: 150)

            // Deviation preview
            if let captureTime = captureTime {
                let deviation = calculateDeviation(
                    watchHour: adjustedHour,
                    watchMinute: adjustedMinute,
                    watchSecond: adjustedSecond,
                    referenceTime: captureTime
                )
                Text("Deviation: \(formatDeviation(deviation))")
                    .font(.terminalBody)
                    .foregroundColor(deviationColor(deviation))
            }

            HStack(spacing: 16) {
                Button {
                    state = .predicted
                } label: {
                    Text("[Back]")
                        .font(.terminalBody)
                        .foregroundColor(.terminalDim)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 20)
                }

                Button {
                    saveReading(wasAdjusted: true)
                } label: {
                    Text("[Save]")
                        .font(.terminalBody)
                        .foregroundColor(.terminalBright)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.terminalGreen, lineWidth: 1)
                        )
                }
            }
        }
    }

    // MARK: - Saved Section

    private var savedSection: some View {
        VStack(spacing: 30) {
            Text("[SAVED]")
                .font(.terminalLarge)
                .foregroundColor(.terminalGreen)

            Text("Reading recorded successfully!")
                .font(.terminalBody)
                .foregroundColor(.terminalBright)

            Button {
                dismiss()
            } label: {
                Text("[Done]")
                    .font(.terminalBody)
                    .foregroundColor(.terminalBright)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 30)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.terminalGreen, lineWidth: 1)
                    )
            }

            Button {
                resetCapture()
            } label: {
                Text("[Take Another]")
                    .font(.terminalSmall)
                    .foregroundColor(.terminalDim)
            }
        }
    }

    // MARK: - Processing

    private func processImage() async {
        guard let image = capturedImage,
              let modelPath = watch.trainedModelPath else {
            errorMessage = "Model not found"
            return
        }

        isProcessing = true
        errorMessage = nil

        do {
            prediction = try await mlService.predict(image: image, modelPath: modelPath)
            state = .predicted
        } catch {
            errorMessage = error.localizedDescription
        }

        isProcessing = false
    }

    private func saveReading(wasAdjusted: Bool) {
        guard let captureTime = captureTime else { return }

        let hour: Int
        let minute: Int
        let second: Int

        if wasAdjusted {
            hour = adjustedHour
            minute = adjustedMinute
            second = adjustedSecond
        } else if let prediction = prediction {
            hour = prediction.hour
            minute = prediction.minute
            second = prediction.second
        } else {
            return
        }

        // Get previous cumulative deviation
        let previousDeviation = watch.readings
            .sorted { $0.capturedAt > $1.capturedAt }
            .first?.cumulativeDeviation ?? 0

        let reading = WatchReading(
            watch: watch,
            capturedAt: captureTime,
            watchHour: hour,
            watchMinute: minute,
            watchSecond: second,
            referenceTime: captureTime,
            previousCumulativeDeviation: previousDeviation
        )

        reading.wasManuallyAdjusted = wasAdjusted
        reading.confidenceScore = prediction?.confidence
        reading.photoData = capturedImage?.jpegData(compressionQuality: 0.7)

        modelContext.insert(reading)

        do {
            try modelContext.save()
            state = .saved
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }

    private func resetCapture() {
        capturedImage = nil
        prediction = nil
        captureTime = nil
        errorMessage = nil
        state = .ready
    }

    // MARK: - Helpers

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func calculateDeviation(watchHour: Int, watchMinute: Int, watchSecond: Int, referenceTime: Date) -> Double {
        let watchSeconds = watchHour * 3600 + watchMinute * 60 + watchSecond

        let refComponents = Calendar.current.dateComponents([.hour, .minute, .second], from: referenceTime)
        let refSeconds = (refComponents.hour ?? 0) * 3600 + (refComponents.minute ?? 0) * 60 + (refComponents.second ?? 0)

        var deviation = Double(watchSeconds - refSeconds)

        // Handle wrap-around
        if deviation > 43200 {
            deviation -= 86400
        } else if deviation < -43200 {
            deviation += 86400
        }

        return deviation
    }

    private func formatDeviation(_ seconds: Double) -> String {
        let absSeconds = abs(seconds)
        let sign = seconds >= 0 ? "+" : "-"

        if absSeconds < 60 {
            return String(format: "%@%.1fs", sign, absSeconds)
        } else {
            let minutes = Int(absSeconds) / 60
            let secs = absSeconds.truncatingRemainder(dividingBy: 60)
            return String(format: "%@%dm %.1fs", sign, minutes, secs)
        }
    }

    private func deviationColor(_ seconds: Double) -> Color {
        let absSeconds = abs(seconds)
        if absSeconds < 5 {
            return .terminalGreen
        } else if absSeconds < 30 {
            return .yellow
        } else {
            return .red
        }
    }
}

// MARK: - Camera Picker for Readings

/// Camera picker that captures the exact NTP time when the photo is taken
struct ReadingCameraPicker: UIViewControllerRepresentable {
    let ntpService: NTPService
    let onCapture: (UIImage, Date) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ReadingCameraPicker

        init(_ parent: ReadingCameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            // Capture NTP time immediately when photo is confirmed
            let captureTimestamp = parent.ntpService.now()

            if let uiImage = info[.originalImage] as? UIImage {
                parent.onCapture(uiImage, captureTimestamp)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

#Preview {
    CaptureReadingView(watch: Watch(name: "Test Watch"))
        .environmentObject(NTPService.shared)
        .modelContainer(for: Watch.self, inMemory: true)
}
