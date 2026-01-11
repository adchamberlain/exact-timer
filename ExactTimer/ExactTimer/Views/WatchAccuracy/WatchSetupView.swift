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
    @State private var showingCamera: Bool = false

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

    // Focus state for text fields
    @FocusState private var focusedField: FocusedField?

    enum FocusedField {
        case watchName
        case watchBrand
    }

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
            VStack(spacing: 0) {
                // Progress indicator
                progressIndicator

                // Current step content
                ScrollView {
                    stepContent
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 20)
                }

                // Fixed navigation buttons at bottom
                if shouldShowNavigationButtons {
                    navigationButtons
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(Color.black)
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

    private var shouldShowNavigationButtons: Bool {
        switch currentStep {
        case .training, .complete:
            return false
        default:
            return true
        }
    }

    private var navigationButtons: some View {
        HStack {
            // Back button
            if currentStep != .nameEntry {
                backButton {
                    switch currentStep {
                    case .photoCapture:
                        currentStep = .nameEntry
                    case .handExtraction:
                        currentStep = .photoCapture
                    case .referenceTime:
                        currentStep = .handExtraction
                    default:
                        break
                    }
                }
            }

            Spacer()

            // Next button
            switch currentStep {
            case .nameEntry:
                nextButton(enabled: !watchName.isEmpty) {
                    currentStep = .photoCapture
                }
            case .photoCapture:
                nextButton(enabled: referenceImage != nil) {
                    currentStep = .handExtraction
                }
            case .handExtraction:
                nextButton(enabled: extractedHourHand != nil && extractedMinuteHand != nil) {
                    currentStep = .referenceTime
                }
            case .referenceTime:
                nextButton(enabled: true) {
                    startTraining()
                }
            default:
                EmptyView()
            }
        }
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
                    .focused($focusedField, equals: .watchName)
                    .submitLabel(.next)
                    .onSubmit {
                        focusedField = .watchBrand
                    }
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
                    .focused($focusedField, equals: .watchBrand)
                    .submitLabel(.done)
                    .onSubmit {
                        focusedField = nil
                    }
            }
        }
        .onAppear {
            // Auto-focus the name field after a brief delay to pre-warm the keyboard
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                focusedField = .watchName
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
                VStack(spacing: 16) {
                    // Camera button
                    Button {
                        showingCamera = true
                    } label: {
                        VStack(spacing: 12) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.terminalGreen)

                            Text("Take Photo")
                                .font(.terminalBody)
                                .foregroundColor(.terminalGreen)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 140)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.terminalGreen, lineWidth: 2)
                        )
                    }

                    Text("or")
                        .font(.terminalCaption)
                        .foregroundColor(.terminalDim)

                    // Photo library picker
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 30))
                                .foregroundColor(.terminalDim)

                            Text("Choose from Library")
                                .font(.terminalBody)
                                .foregroundColor(.terminalDim)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.terminalDim, style: StrokeStyle(lineWidth: 1, dash: [8]))
                        )
                    }
                    .onChange(of: selectedPhotoItem) { _, newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self),
                               let image = UIImage(data: data) {
                                referenceImage = image
                                // Auto-advance to hand extraction after selecting photo
                                currentStep = .handExtraction
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingCamera) {
            CameraPicker(image: $referenceImage) {
                // Auto-advance to hand extraction after taking photo
                currentStep = .handExtraction
            }
        }
    }

    // MARK: - Step 3: Hand Extraction

    private var handExtractionStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("> Identify Watch Hands")
                .font(.terminalTitle)
                .foregroundColor(.terminalGreen)

            if let image = referenceImage {
                HandExtractionView(
                    image: image,
                    hourHandMask: $extractedHourHand,
                    minuteHandMask: $extractedMinuteHand,
                    secondHandMask: $extractedSecondHand,
                    centerPoint: $centerPoint
                )
                .frame(height: 500)
            }
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

            // Cancel button
            Button {
                cancelTraining()
            } label: {
                Text("[Cancel]")
                    .font(.terminalBody)
                    .foregroundColor(.terminalDim)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 24)
            }
            .padding(.bottom, 20)
        }
    }

    private func cancelTraining() {
        mlService.isTraining = false
        mlService.trainingProgress = 0
        mlService.statusMessage = ""
        mlService.errorMessage = nil
        currentStep = .referenceTime
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

// MARK: - Camera Picker

struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    var onCapture: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    init(image: Binding<UIImage?>, onCapture: (() -> Void)? = nil) {
        self._image = image
        self.onCapture = onCapture
    }

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
        let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let uiImage = info[.originalImage] as? UIImage {
                parent.image = uiImage
                parent.onCapture?()
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

#Preview {
    WatchSetupView()
        .modelContainer(for: Watch.self, inMemory: true)
}
