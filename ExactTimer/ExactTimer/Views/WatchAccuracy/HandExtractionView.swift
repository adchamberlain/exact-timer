import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

/// Semi-automatic view for extracting watch hands from reference image
struct HandExtractionView: View {
    let image: UIImage

    @Binding var hourHandMask: UIImage?
    @Binding var minuteHandMask: UIImage?
    @Binding var secondHandMask: UIImage?
    @Binding var centerPoint: CGPoint

    @State private var currentSelection: HandType = .hour
    @State private var tapPoints: [CGPoint] = []
    @State private var imageSize: CGSize = .zero

    enum HandType: String, CaseIterable {
        case hour = "Hour"
        case minute = "Minute"
        case second = "Second"
        case center = "Center"
    }

    var body: some View {
        VStack(spacing: 12) {
            // Selection buttons
            HStack(spacing: 8) {
                ForEach(HandType.allCases, id: \.self) { type in
                    Button {
                        currentSelection = type
                        tapPoints = []
                    } label: {
                        Text(type.rawValue)
                            .font(.terminalSmall)
                            .foregroundColor(currentSelection == type ? .black : .terminalGreen)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(currentSelection == type ? Color.terminalGreen : Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.terminalGreen, lineWidth: 1)
                            )
                    }
                }
            }

            Text(instructionText)
                .font(.terminalSmall)
                .foregroundColor(.terminalDim)

            // Image with overlay
            GeometryReader { geo in
                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .background(
                            GeometryReader { imageGeo in
                                Color.clear.onAppear {
                                    imageSize = imageGeo.size
                                }
                            }
                        )
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { value in
                                    handleTap(at: value.location, in: geo.size)
                                }
                        )

                    // Draw existing masks preview
                    masksOverlay

                    // Draw tap points
                    ForEach(tapPoints.indices, id: \.self) { index in
                        Circle()
                            .fill(Color.red)
                            .frame(width: 10, height: 10)
                            .position(tapPoints[index])
                    }

                    // Draw center point
                    let centerInView = CGPoint(
                        x: centerPoint.x * imageSize.width + (geo.size.width - imageSize.width) / 2,
                        y: centerPoint.y * imageSize.height + (geo.size.height - imageSize.height) / 2
                    )
                    Circle()
                        .stroke(Color.yellow, lineWidth: 2)
                        .frame(width: 20, height: 20)
                        .position(centerInView)
                }
            }

            // Action buttons
            HStack {
                Button {
                    tapPoints = []
                } label: {
                    Text("[Clear]")
                        .font(.terminalSmall)
                        .foregroundColor(.terminalDim)
                }

                Spacer()

                if currentSelection != .center && tapPoints.count >= 2 {
                    Button {
                        createMaskFromPoints()
                    } label: {
                        Text("[Create Mask]")
                            .font(.terminalSmall)
                            .foregroundColor(.terminalGreen)
                    }
                }
            }
        }
    }

    private var instructionText: String {
        switch currentSelection {
        case .hour:
            return "Tap along the hour hand (at least 2 points)"
        case .minute:
            return "Tap along the minute hand (at least 2 points)"
        case .second:
            return "Tap along the second hand (optional, at least 2 points)"
        case .center:
            return "Tap the center of the watch"
        }
    }

    @ViewBuilder
    private var masksOverlay: some View {
        if let hourMask = hourHandMask {
            Image(uiImage: hourMask)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .opacity(0.3)
                .allowsHitTesting(false)
        }
        if let minuteMask = minuteHandMask {
            Image(uiImage: minuteMask)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .opacity(0.3)
                .allowsHitTesting(false)
        }
        if let secondMask = secondHandMask {
            Image(uiImage: secondMask)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .opacity(0.3)
                .allowsHitTesting(false)
        }
    }

    private func handleTap(at point: CGPoint, in containerSize: CGSize) {
        // Convert to normalized coordinates
        let imageFrame = calculateImageFrame(containerSize: containerSize)

        // Check if tap is within image bounds
        guard imageFrame.contains(point) else { return }

        if currentSelection == .center {
            // Set center point (normalized)
            let normalizedX = (point.x - imageFrame.minX) / imageFrame.width
            let normalizedY = (point.y - imageFrame.minY) / imageFrame.height
            centerPoint = CGPoint(x: normalizedX, y: normalizedY)
        } else {
            // Add point for line drawing
            tapPoints.append(point)
        }
    }

    private func calculateImageFrame(containerSize: CGSize) -> CGRect {
        let imageAspect = image.size.width / image.size.height
        let containerAspect = containerSize.width / containerSize.height

        var frame: CGRect

        if imageAspect > containerAspect {
            // Image is wider
            let height = containerSize.width / imageAspect
            frame = CGRect(
                x: 0,
                y: (containerSize.height - height) / 2,
                width: containerSize.width,
                height: height
            )
        } else {
            // Image is taller
            let width = containerSize.height * imageAspect
            frame = CGRect(
                x: (containerSize.width - width) / 2,
                y: 0,
                width: width,
                height: containerSize.height
            )
        }

        return frame
    }

    private func createMaskFromPoints() {
        guard tapPoints.count >= 2 else { return }

        // Create mask image from tap points
        // We'll draw a line through all points with some thickness

        guard let cgImage = image.cgImage else { return }

        let width = cgImage.width
        let height = cgImage.height

        // Create mask context
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        // Clear to transparent
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))

        // Convert view points to image coordinates
        let imagePoints = tapPoints.map { viewPoint -> CGPoint in
            // Assuming the image fills the available space proportionally
            let normalizedX = (viewPoint.x - (imageSize.width * 0)) / imageSize.width
            let normalizedY = (viewPoint.y - (imageSize.height * 0)) / imageSize.height

            return CGPoint(
                x: normalizedX * CGFloat(width),
                y: normalizedY * CGFloat(height)
            )
        }

        // Draw hand as a thick line from center through points
        let centerImagePoint = CGPoint(
            x: centerPoint.x * CGFloat(width),
            y: centerPoint.y * CGFloat(height)
        )

        // Find the farthest point from center
        let farthestPoint = imagePoints.max { p1, p2 in
            hypot(p1.x - centerImagePoint.x, p1.y - centerImagePoint.y) <
            hypot(p2.x - centerImagePoint.x, p2.y - centerImagePoint.y)
        } ?? imagePoints[0]

        // Draw line from center to farthest point with appropriate thickness
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineCap(.round)

        // Thickness based on hand type
        let thickness: CGFloat
        switch currentSelection {
        case .hour:
            thickness = CGFloat(width) * 0.025  // Thicker for hour hand
        case .minute:
            thickness = CGFloat(width) * 0.015  // Medium for minute hand
        case .second:
            thickness = CGFloat(width) * 0.005  // Thin for second hand
        case .center:
            thickness = 0
        }

        context.setLineWidth(thickness)
        context.move(to: centerImagePoint)
        context.addLine(to: farthestPoint)
        context.strokePath()

        // Also draw small circles at the points for better coverage
        context.setFillColor(UIColor.white.cgColor)
        for point in imagePoints {
            context.fillEllipse(in: CGRect(
                x: point.x - thickness / 2,
                y: point.y - thickness / 2,
                width: thickness,
                height: thickness
            ))
        }

        guard let maskCGImage = context.makeImage() else { return }
        let maskImage = UIImage(cgImage: maskCGImage)

        // Store the mask
        switch currentSelection {
        case .hour:
            hourHandMask = maskImage
        case .minute:
            minuteHandMask = maskImage
        case .second:
            secondHandMask = maskImage
        case .center:
            break
        }

        // Clear points and move to next
        tapPoints = []

        // Auto-advance to next hand
        switch currentSelection {
        case .hour:
            currentSelection = .minute
        case .minute:
            currentSelection = .second
        case .second:
            currentSelection = .center
        case .center:
            break
        }
    }
}

// MARK: - Edge Detection Helper

extension HandExtractionView {
    /// Perform edge detection to help identify hand boundaries
    static func detectEdges(in image: UIImage) -> UIImage? {
        guard let ciImage = CIImage(image: image) else { return nil }

        let context = CIContext()

        // Apply edge detection filter
        guard let filter = CIFilter(name: "CIEdges") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(3.0, forKey: "inputIntensity")

        guard let outputImage = filter.outputImage,
              let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}

#Preview {
    HandExtractionView(
        image: UIImage(systemName: "clock")!,
        hourHandMask: .constant(nil),
        minuteHandMask: .constant(nil),
        secondHandMask: .constant(nil),
        centerPoint: .constant(CGPoint(x: 0.5, y: 0.5))
    )
    .frame(height: 400)
    .background(Color.black)
}
