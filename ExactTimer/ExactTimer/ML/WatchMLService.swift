import Foundation
import CoreML
import Vision
import UIKit

/// Service for training and running inference with watch time prediction models
@MainActor
class WatchMLService: ObservableObject {

    /// Training progress (0-1)
    @Published var trainingProgress: Double = 0

    /// Current status message
    @Published var statusMessage: String = ""

    /// Whether training is in progress
    @Published var isTraining: Bool = false

    /// Error message if training failed
    @Published var errorMessage: String?

    private let dataGenerator = SyntheticDataGenerator()

    /// Prediction result from the ML model
    struct TimePrediction {
        let hour: Int
        let minute: Int
        let second: Int
        let confidence: Double

        var timeString: String {
            String(format: "%d:%02d:%02d", hour, minute, second)
        }
    }

    // MARK: - Training

    /// Train a model for the given watch
    func trainModel(for watch: Watch) async throws -> URL {
        isTraining = true
        errorMessage = nil

        do {
            // Step 1: Validate watch has required data
            statusMessage = "Validating watch data..."
            trainingProgress = 0.05

            // Give UI a chance to update
            try await Task.sleep(nanoseconds: 100_000_000)

            guard let referenceData = watch.referencePhotoData,
                  let referenceImage = UIImage(data: referenceData),
                  let hourMaskData = watch.hourHandMask,
                  let hourMask = UIImage(data: hourMaskData),
                  let minuteMaskData = watch.minuteHandMask,
                  let minuteMask = UIImage(data: minuteMaskData),
                  let centerX = watch.centerX,
                  let centerY = watch.centerY,
                  let refHour = watch.referenceHour,
                  let refMinute = watch.referenceMinute,
                  let refSecond = watch.referenceSecond else {
                throw WatchMLError.missingWatchData
            }

            let secondMask: UIImage? = watch.secondHandMask.flatMap { UIImage(data: $0) }
            let center = CGPoint(x: centerX, y: centerY)

            // Step 2: Inpaint dial (remove hands) - run off main thread
            statusMessage = "Preparing dial image..."
            trainingProgress = 0.1

            print("[ML] Starting inpainting...")
            print("[ML] Reference image size: \(referenceImage.size)")
            print("[ML] Hour mask size: \(hourMask.size)")
            print("[ML] Minute mask size: \(minuteMask.size)")

            // Give UI a chance to update
            try await Task.sleep(nanoseconds: 50_000_000)

            let cleanDial = await Task.detached { [dataGenerator] in
                let result = dataGenerator.inpaintDial(
                    referenceImage: referenceImage,
                    hourHandMask: hourMask,
                    minuteHandMask: minuteMask,
                    secondHandMask: secondMask
                )
                print("[ML] Inpainting complete, result: \(result != nil ? "success" : "nil")")
                return result
            }.value

            guard let cleanDial else {
                print("[ML] Inpainting failed - cleanDial is nil")
                throw WatchMLError.inpaintingFailed
            }

            print("[ML] Clean dial size: \(cleanDial.size)")

            // Step 3: Generate synthetic training data
            statusMessage = "Generating training data..."
            trainingProgress = 0.2

            // Give UI a chance to update
            try await Task.sleep(nanoseconds: 50_000_000)

            let samples = await Task.detached { [dataGenerator] in
                return dataGenerator.generateTrainingData(
                    dialImage: cleanDial,
                    hourHandMask: hourMask,
                    minuteHandMask: minuteMask,
                    secondHandMask: secondMask,
                    center: center,
                    referenceTime: (hour: refHour, minute: refMinute, second: refSecond)
                )
            }.value

            guard !samples.isEmpty else {
                throw WatchMLError.dataGenerationFailed
            }

            statusMessage = "Generated \(samples.count) training samples"
            trainingProgress = 0.4

            // Step 4: Create and train the model
            statusMessage = "Training model..."

            let modelURL = try await trainCoreMLModel(
                samples: samples,
                watchId: watch.id
            )

            trainingProgress = 1.0
            statusMessage = "Training complete!"
            isTraining = false

            return modelURL

        } catch {
            isTraining = false
            errorMessage = error.localizedDescription
            throw error
        }
    }

    /// Train a Core ML model on the synthetic data
    private func trainCoreMLModel(
        samples: [SyntheticDataGenerator.TrainingSample],
        watchId: UUID
    ) async throws -> URL {
        // For the MVP, we'll create training data and use MLImageClassifier
        // In production, you'd use a custom neural network with MLUpdateTask

        // Create directories for training data
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let watchDir = documentsDir.appendingPathComponent("watches/\(watchId.uuidString)")
        let trainingDir = watchDir.appendingPathComponent("training")

        try FileManager.default.createDirectory(at: trainingDir, withIntermediateDirectories: true)

        // Save training images organized by class
        // Class format: "H{hour}_M{minute}" (we'll bucket seconds for simplicity)
        statusMessage = "Preparing training images..."

        var progress = 0.4
        let progressIncrement = 0.3 / Double(samples.count)

        for sample in samples {
            // Create class directory (bucket by 5-minute intervals for manageable class count)
            let minuteBucket = (sample.minute / 5) * 5
            let className = String(format: "H%02d_M%02d", sample.hour, minuteBucket)
            let classDir = trainingDir.appendingPathComponent(className)

            try FileManager.default.createDirectory(at: classDir, withIntermediateDirectories: true)

            // Save image
            let imageName = "\(sample.hour)_\(sample.minute)_\(sample.second).png"
            let imageURL = classDir.appendingPathComponent(imageName)

            if let pngData = UIImage(cgImage: sample.image).pngData() {
                try pngData.write(to: imageURL)
            }

            progress += progressIncrement
            await MainActor.run {
                self.trainingProgress = min(progress, 0.7)
            }
        }

        // Use Create ML's MLImageClassifier for training
        // Note: This is a simplified approach for MVP
        // For production, use MLUpdateTask with a custom neural network

        statusMessage = "Training classifier..."
        trainingProgress = 0.75

        // For on-device training, we need to use MLUpdateTask
        // However, for the MVP, we'll create a simple k-NN based model
        // that can be trained quickly on device

        let modelURL = try await createAndTrainKNNModel(
            trainingDir: trainingDir,
            outputDir: watchDir,
            watchId: watchId
        )

        // Clean up training images
        try? FileManager.default.removeItem(at: trainingDir)

        trainingProgress = 0.95
        statusMessage = "Finalizing model..."

        return modelURL
    }

    /// Create and train a k-NN model (faster on-device training)
    private func createAndTrainKNNModel(
        trainingDir: URL,
        outputDir: URL,
        watchId: UUID
    ) async throws -> URL {
        // For MVP: Store feature vectors and labels for k-NN inference
        // This is much faster than training a neural network on device

        var featureVectors: [[Float]] = []
        var labels: [(hour: Int, minute: Int)] = []

        let classDirectories = try FileManager.default.contentsOfDirectory(
            at: trainingDir,
            includingPropertiesForKeys: nil
        ).filter { $0.hasDirectoryPath }

        for classDir in classDirectories {
            // Parse class name
            let className = classDir.lastPathComponent
            let components = className.split(separator: "_")
            guard components.count == 2,
                  let hour = Int(components[0].dropFirst()),
                  let minute = Int(components[1].dropFirst()) else {
                continue
            }

            // Get images in this class
            let images = try FileManager.default.contentsOfDirectory(
                at: classDir,
                includingPropertiesForKeys: nil
            ).filter { $0.pathExtension == "png" }

            for imageURL in images {
                if let imageData = try? Data(contentsOf: imageURL),
                   let image = UIImage(data: imageData),
                   let features = extractFeatures(from: image) {
                    featureVectors.append(features)
                    labels.append((hour: hour, minute: minute))
                }
            }
        }

        // Save the model data
        let modelData = KNNModelData(
            featureVectors: featureVectors,
            labels: labels
        )

        let modelURL = outputDir.appendingPathComponent("model.json")
        let encoder = JSONEncoder()
        let data = try encoder.encode(modelData)
        try data.write(to: modelURL)

        return modelURL
    }

    /// Extract simple features from an image for k-NN
    private func extractFeatures(from image: UIImage) -> [Float]? {
        guard let cgImage = image.cgImage else { return nil }

        // Resize to small size for feature extraction
        let size = 32
        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

        guard let data = context.data else { return nil }

        let pixels = data.bindMemory(to: UInt8.self, capacity: size * size * 4)

        // Convert to grayscale feature vector
        var features: [Float] = []
        for i in 0..<(size * size) {
            let r = Float(pixels[i * 4]) / 255.0
            let g = Float(pixels[i * 4 + 1]) / 255.0
            let b = Float(pixels[i * 4 + 2]) / 255.0
            let gray = 0.299 * r + 0.587 * g + 0.114 * b
            features.append(gray)
        }

        return features
    }

    // MARK: - Inference

    /// Predict time from an image using a trained model
    func predict(image: UIImage, modelPath: String) async throws -> TimePrediction {
        let modelURL = URL(fileURLWithPath: modelPath)

        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw WatchMLError.modelNotFound
        }

        // Load k-NN model
        let data = try Data(contentsOf: modelURL)
        let decoder = JSONDecoder()
        let modelData = try decoder.decode(KNNModelData.self, from: data)

        // Extract features from input image
        guard let queryFeatures = extractFeatures(from: image) else {
            throw WatchMLError.featureExtractionFailed
        }

        // Find k nearest neighbors
        let k = 5
        let distances = modelData.featureVectors.enumerated().map { (idx, features) -> (Int, Float) in
            let dist = euclideanDistance(queryFeatures, features)
            return (idx, dist)
        }.sorted { $0.1 < $1.1 }

        // Vote on the result
        var votes: [String: Int] = [:]
        for i in 0..<min(k, distances.count) {
            let idx = distances[i].0
            let label = modelData.labels[idx]
            let key = "\(label.hour)_\(label.minute)"
            votes[key, default: 0] += 1
        }

        // Find winning class
        guard let winner = votes.max(by: { $0.value < $1.value }) else {
            throw WatchMLError.predictionFailed
        }

        let components = winner.key.split(separator: "_")
        let hour = Int(components[0]) ?? 0
        let minute = Int(components[1]) ?? 0

        // Confidence based on vote proportion
        let confidence = Double(winner.value) / Double(k)

        return TimePrediction(
            hour: hour,
            minute: minute,
            second: 0,  // k-NN doesn't predict seconds in MVP
            confidence: confidence
        )
    }

    private func euclideanDistance(_ a: [Float], _ b: [Float]) -> Float {
        var sum: Float = 0
        for i in 0..<min(a.count, b.count) {
            let diff = a[i] - b[i]
            sum += diff * diff
        }
        return sqrt(sum)
    }
}

// MARK: - Supporting Types

struct KNNModelData: Codable {
    let featureVectors: [[Float]]
    let labels: [TimeLabel]

    struct TimeLabel: Codable {
        let hour: Int
        let minute: Int
    }

    init(featureVectors: [[Float]], labels: [(hour: Int, minute: Int)]) {
        self.featureVectors = featureVectors
        self.labels = labels.map { TimeLabel(hour: $0.hour, minute: $0.minute) }
    }
}

enum WatchMLError: LocalizedError {
    case missingWatchData
    case inpaintingFailed
    case dataGenerationFailed
    case modelNotFound
    case featureExtractionFailed
    case predictionFailed
    case trainingFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingWatchData:
            return "Watch is missing required data (reference photo, hand masks, or center point)"
        case .inpaintingFailed:
            return "Failed to remove hands from dial image"
        case .dataGenerationFailed:
            return "Failed to generate training data"
        case .modelNotFound:
            return "Trained model not found"
        case .featureExtractionFailed:
            return "Failed to extract features from image"
        case .predictionFailed:
            return "Failed to make prediction"
        case .trainingFailed(let message):
            return "Training failed: \(message)"
        }
    }
}
