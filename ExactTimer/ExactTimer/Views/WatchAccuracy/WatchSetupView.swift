import SwiftUI
import SwiftData
import PhotosUI

/// Multi-step wizard for setting up a new watch
struct WatchSetupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // Optional existing watch for retraining
    var existingWatch: Watch?

    @State private var currentStep: SetupStep = .nameEntry
    @State private var watchName: String = ""
    @State private var watchBrand: String = ""
    @State private var referenceImage: UIImage?
    @State private var selectedPhotoItem: PhotosPickerItem?

    // Hand extraction state
    @State private var extractedHourHand: UIImage?
    @State private var extractedMinuteHand: UIImage?
    @State private var extractedSecondHand: UIImage?
    @State private var centerPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)

    // Reference time state
    @State private var referenceHour: Int = 10
    @State private var referenceMinute: Int = 10
    @State private var referenceSecond: Int = 0

    // Training state
    @StateObject private var mlService = WatchMLService()

    enum SetupStep: Int, CaseIterable {
        case nameEntry
        case photoCapture
        case handExtraction
        case referenceTime
        case training
        case complete
    }

    var body: some View {
        NavigationStack {
            VStack {
                // Progress indicator
                progressIndicator

                // Current step content
                ScrollView {
                    stepContent
                        .padding(.horizontal, 20)
                        .padding(.vertical, 20)
                }
            }
            .background(Color.black)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Watch Setup")
                        .font(.terminalTitle)
                        .foregroundColor(.terminalGreen)
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    if currentStep != .training {
                        Button("Cancel") {
                            dismiss()
                        }
                        .foregroundColor(.terminalDim)
                    }
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear {
                if let watch = existingWatch {
                    watchName = watch.name
                    watchBrand = watch.brand ?? ""
                    currentStep = .photoCapture
                }
            }
        }
    }

    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<SetupStep.allCases.count - 1, id: \.self) { index in
                Circle()
                    .fill(index <= currentStep.rawValue ? Color.terminalGreen : Color.terminalDim)
                    .frame(width: 10, height: 10)

                if index < SetupStep.allCases.count - 2 {
                    Rectangle()
                        .fill(index < currentStep.rawValue ? Color.terminalGreen : Color.terminalDim)
                        .frame(height: 2)
                }
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case .nameEntry:
            nameEntryStep
        case .photoCapture:
            photoCaptureStep
        case .handExtraction:
            handExtractionStep
        case .referenceTime:
            referenceTimeStep
        case .training:
            trainingStep
        case .complete:
            completeStep
        }
    }

    // MARK: - Step 1: Name Entry

    private var nameEntryStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("> Enter Watch Details")
                .font(.terminalTitle)
                .foregroundColor(.terminalGreen)

            Text("Give your watch a name to identify it")
                .font(.terminalCaption)
                .foregroundColor(.terminalDim)

            VStack(alignment: .leading, spacing: 8) {
                Text("Watch Name *")
                    .font(.terminalSmall)
                    .foregroundColor(.terminalDim)

                TextField("", text: $watchName)
                    .font(.terminalBody)
                    .foregroundColor(.terminalBright)
                    .padding(12)
                    .background(Color.black)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.terminalGreen, lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Brand (optional)")
                    .font(.terminalSmall)
                    .foregroundColor(.terminalDim)

                TextField("", text: $watchBrand)
                    .font(.terminalBody)
                    .foregroundColor(.terminalBright)
                    .padding(12)
                    .background(Color.black)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.terminalDim, lineWidth: 1)
                    )
            }

            Spacer()
                .frame(height: 30)

            nextButton(enabled: !watchName.isEmpty) {
                currentStep = .photoCapture
            }
        }
    }

    // MARK: - Step 2: Photo Capture

    private var photoCaptureStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("> Capture Reference Photo")
                .font(.terminalTitle)
                .foregroundColor(.terminalGreen)

            Text("Take a clear photo of your watch face.\nEnsure good lighting and no glare.")
                .font(.terminalCaption)
                .foregroundColor(.terminalDim)

            if let image = referenceImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.terminalGreen, lineWidth: 2)
                    )

                Button {
                    referenceImage = nil
                    selectedPhotoItem = nil
                } label: {
                    Text("[Retake]")
                        .font(.terminalBody)
                        .foregroundColor(.terminalDim)
                }
            } else {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.terminalGreen)

                        Text("Tap to select photo")
                            .font(.terminalBody)
                            .foregroundColor(.terminalGreen)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.terminalDim, style: StrokeStyle(lineWidth: 2, dash: [8]))
                    )
                }
                .onChange(of: selectedPhotoItem) { _, newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            referenceImage = image
                        }
                    }
                }
            }

            Spacer()
                .frame(height: 30)

            HStack {
                backButton {
                    currentStep = .nameEntry
                }

                Spacer()

                nextButton(enabled: referenceImage != nil) {
                    currentStep = .handExtraction
                }
            }
        }
    }

    // MARK: - Step 3: Hand Extraction

    private var handExtractionStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("> Identify Watch Hands")
                .font(.terminalTitle)
                .foregroundColor(.terminalGreen)

            Text("Tap on each hand to select it.\nStart with the hour hand.")
                .font(.terminalCaption)
                .foregroundColor(.terminalDim)

            if let image = referenceImage {
                HandExtractionView(
                    image: image,
                    hourHandMask: $extractedHourHand,
                    minuteHandMask: $extractedMinuteHand,
                    secondHandMask: $extractedSecondHand,
                    centerPoint: $centerPoint
                )
                .frame(height: 350)
            }

            // Status indicators
            VStack(alignment: .leading, spacing: 8) {
                handStatusRow("Hour hand", isSet: extractedHourHand != nil)
                handStatusRow("Minute hand", isSet: extractedMinuteHand != nil)
                handStatusRow("Second hand", isSet: extractedSecondHand != nil)
                handStatusRow("Center point", isSet: true)  // Always set with default
            }

            Spacer()
                .frame(height: 20)

            HStack {
                backButton {
                    currentStep = .photoCapture
                }

                Spacer()

                nextButton(enabled: extractedHourHand != nil && extractedMinuteHand != nil) {
                    currentStep = .referenceTime
                }
            }
        }
    }

    private func handStatusRow(_ label: String, isSet: Bool) -> some View {
        HStack {
            Text(isSet ? "[x]" : "[ ]")
                .font(.terminalBody)
                .foregroundColor(isSet ? .terminalGreen : .terminalDim)
            Text(label)
                .font(.terminalBody)
                .foregroundColor(isSet ? .terminalGreen : .terminalDim)
        }
    }

    // MARK: - Step 4: Reference Time

    private var referenceTimeStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("> Set Reference Time")
                .font(.terminalTitle)
                .foregroundColor(.terminalGreen)

            Text("What time does your watch show\nin the reference photo?")
                .font(.terminalCaption)
                .foregroundColor(.terminalDim)

            // Time picker
            HStack(spacing: 4) {
                Picker("Hour", selection: $referenceHour) {
                    ForEach(1...12, id: \.self) { hour in
                        Text("\(hour)").tag(hour % 12)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 60)

                Text(":")
                    .font(.terminalLarge)
                    .foregroundColor(.terminalGreen)

                Picker("Minute", selection: $referenceMinute) {
                    ForEach(0..<60) { minute in
                        Text(String(format: "%02d", minute)).tag(minute)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 60)

                Text(":")
                    .font(.terminalLarge)
                    .foregroundColor(.terminalGreen)

                Picker("Second", selection: $referenceSecond) {
                    ForEach(0..<60) { second in
                        Text(String(format: "%02d", second)).tag(second)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 60)
            }
            .frame(height: 150)

            Text("Selected: \(referenceHour):\(String(format: "%02d", referenceMinute)):\(String(format: "%02d", referenceSecond))")
                .font(.terminalBody)
                .foregroundColor(.terminalBright)

            Spacer()
                .frame(height: 30)

            HStack {
                backButton {
                    currentStep = .handExtraction
                }

                Spacer()

                nextButton(enabled: true) {
                    startTraining()
                }
            }
        }
    }

    // MARK: - Step 5: Training

    private var trainingStep: some View {
        VStack(spacing: 30) {
            Spacer()
                .frame(height: 40)

            Text("> Training Model")
                .font(.terminalTitle)
                .foregroundColor(.terminalGreen)

            // Progress bar
            VStack(spacing: 12) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.terminalDim)
                            .frame(height: 20)

                        Rectangle()
                            .fill(Color.terminalGreen)
                            .frame(width: geo.size.width * mlService.trainingProgress, height: 20)
                    }
                }
                .frame(height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 4))

                Text("\(Int(mlService.trainingProgress * 100))%")
                    .font(.terminalLarge)
                    .foregroundColor(.terminalBright)
            }

            Text(mlService.statusMessage)
                .font(.terminalCaption)
                .foregroundColor(.terminalDim)
                .multilineTextAlignment(.center)

            if let error = mlService.errorMessage {
                Text("Error: \(error)")
                    .font(.terminalSmall)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)

                Button {
                    startTraining()
                } label: {
                    Text("[Retry]")
                        .font(.terminalBody)
                        .foregroundColor(.terminalGreen)
                }
            }

            Spacer()
        }
    }

    // MARK: - Step 6: Complete

    private var completeStep: some View {
        VStack(spacing: 30) {
            Spacer()
                .frame(height: 60)

            Text("[SUCCESS]")
                .font(.terminalLarge)
                .foregroundColor(.terminalGreen)

            Text("Your watch model is ready!")
                .font(.terminalTitle)
                .foregroundColor(.terminalBright)

            Text("You can now take readings to\ntrack your watch's accuracy.")
                .font(.terminalCaption)
                .foregroundColor(.terminalDim)
                .multilineTextAlignment(.center)

            Spacer()
                .frame(height: 40)

            Button {
                dismiss()
            } label: {
                Text("[Done]")
                    .font(.terminalTitle)
                    .foregroundColor(.terminalBright)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 40)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.terminalGreen, lineWidth: 2)
                    )
            }

            Spacer()
        }
    }

    // MARK: - Buttons

    private func nextButton(enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("[Next >]")
                .font(.terminalBody)
                .foregroundColor(enabled ? .terminalBright : .terminalDim)
                .padding(.vertical, 12)
                .padding(.horizontal, 24)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(enabled ? Color.terminalGreen : Color.terminalDim, lineWidth: 1)
                )
        }
        .disabled(!enabled)
    }

    private func backButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("[< Back]")
                .font(.terminalBody)
                .foregroundColor(.terminalDim)
                .padding(.vertical, 12)
                .padding(.horizontal, 24)
        }
    }

    // MARK: - Training

    private func startTraining() {
        currentStep = .training

        Task {
            do {
                // Create or update watch
                let watch = existingWatch ?? Watch(name: watchName, brand: watchBrand.isEmpty ? nil : watchBrand)

                if existingWatch == nil {
                    modelContext.insert(watch)
                }

                // Save reference data
                watch.referencePhotoData = referenceImage?.jpegData(compressionQuality: 0.9)
                watch.hourHandMask = extractedHourHand?.pngData()
                watch.minuteHandMask = extractedMinuteHand?.pngData()
                watch.secondHandMask = extractedSecondHand?.pngData()
                watch.centerX = centerPoint.x
                watch.centerY = centerPoint.y
                watch.referenceHour = referenceHour
                watch.referenceMinute = referenceMinute
                watch.referenceSecond = referenceSecond

                // Train model
                let modelURL = try await mlService.trainModel(for: watch)
                watch.trainedModelPath = modelURL.path
                watch.trainingStatus = .completed

                try modelContext.save()

                currentStep = .complete

            } catch {
                mlService.errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    WatchSetupView()
        .modelContainer(for: Watch.self, inMemory: true)
}
