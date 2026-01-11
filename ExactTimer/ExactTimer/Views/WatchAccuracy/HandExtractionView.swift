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

    @State private var currentSelection: HandType = .center
    @State private var tapPoints: [CGPoint] = []
    @State private var imageSize: CGSize = .zero

    // Saved points for each hand in NORMALIZED coordinates (0-1)
    // This ensures dots don't shift when the view layout changes
    @State private var hourHandPoints: [CGPoint] = []
    @State private var minuteHandPoints: [CGPoint] = []
    @State private var secondHandPoints: [CGPoint] = []

    // Zoom state
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    @State private var zoomOffset: CGSize = .zero
    @State private var lastZoomOffset: CGSize = .zero

    // Magnifier loupe state
    @State private var showMagnifier: Bool = false
    @State private var magnifierPosition: CGPoint = .zero
    @State private var touchPosition: CGPoint = .zero

    enum HandType: String, CaseIterable {
        case center = "Center"
        case hour = "Hour"
        case minute = "Minute"
        case second = "Second"
    }

    var body: some View {
        VStack(spacing: 12) {
            // Selection buttons
            HStack(spacing: 8) {
                ForEach(HandType.allCases, id: \.self) { type in
                    let isSet = isMaskSet(for: type)
                    Button {
                        withAnimation(.none) {
                            // Auto-save current mask if switching away from a hand with 2+ points
                            if currentSelection != .center && currentSelection != type && tapPoints.count >= 2 {
                                createMaskFromPoints()
                            }
                            currentSelection = type
                            tapPoints = []
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if isSet {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10))
                            }
                            Text(type.rawValue)
                        }
                        .font(.terminalSmall)
                        .foregroundColor(currentSelection == type ? .black : (isSet ? .terminalBright : .terminalGreen))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(currentSelection == type ? Color.terminalGreen : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(isSet ? Color.terminalBright : Color.terminalGreen, lineWidth: isSet ? 2 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(instructionText)
                .font(.terminalSmall)
                .foregroundColor(.terminalDim)

            // Image with overlay
            GeometryReader { geo in
                let imageFrame = calculateImageFrame(containerSize: geo.size)

                ZStack {
                    // Main image content
                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .onAppear {
                                imageSize = imageFrame.size
                            }
                            .onChange(of: geo.size) { _, _ in
                                imageSize = calculateImageFrame(containerSize: geo.size).size
                            }

                        // Draw existing masks preview
                        masksOverlay

                        // Draw saved points for each hand (dimmer to show they're saved)
                        // Convert from normalized (0-1) to display coordinates
                        ForEach(hourHandPoints.indices, id: \.self) { index in
                            Circle()
                                .fill(Color.terminalGreen.opacity(currentSelection == .hour ? 1.0 : 0.5))
                                .frame(width: 10, height: 10)
                                .position(
                                    x: hourHandPoints[index].x * imageFrame.width,
                                    y: hourHandPoints[index].y * imageFrame.height
                                )
                        }
                        ForEach(minuteHandPoints.indices, id: \.self) { index in
                            Circle()
                                .fill(Color.terminalGreen.opacity(currentSelection == .minute ? 1.0 : 0.5))
                                .frame(width: 10, height: 10)
                                .position(
                                    x: minuteHandPoints[index].x * imageFrame.width,
                                    y: minuteHandPoints[index].y * imageFrame.height
                                )
                        }
                        ForEach(secondHandPoints.indices, id: \.self) { index in
                            Circle()
                                .fill(Color.terminalGreen.opacity(currentSelection == .second ? 1.0 : 0.5))
                                .frame(width: 10, height: 10)
                                .position(
                                    x: secondHandPoints[index].x * imageFrame.width,
                                    y: secondHandPoints[index].y * imageFrame.height
                                )
                        }

                        // Draw current tap points (for hand being edited)
                        ForEach(tapPoints.indices, id: \.self) { index in
                            Circle()
                                .fill(Color.terminalGreen)
                                .frame(width: 10, height: 10)
                                .position(tapPoints[index])
                        }

                        // Draw center point (only if explicitly set)
                        if centerPoint.x != 0.5 || centerPoint.y != 0.5 {
                            Circle()
                                .stroke(Color.terminalBright, lineWidth: 2)
                                .frame(width: 20, height: 20)
                                .position(
                                    x: centerPoint.x * imageFrame.width,
                                    y: centerPoint.y * imageFrame.height
                                )
                        }

                        // Crosshair at touch position while dragging
                        if showMagnifier {
                            CrosshairView()
                                .position(touchPosition)
                        }
                    }
                    .frame(width: imageFrame.width, height: imageFrame.height)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let loc = value.location
                                // Check if within image bounds
                                if loc.x >= 0 && loc.x <= imageFrame.width &&
                                   loc.y >= 0 && loc.y <= imageFrame.height {
                                    touchPosition = loc
                                    showMagnifier = true
                                    // Position magnifier in top corner, opposite to touch
                                    magnifierPosition = loc
                                }
                            }
                            .onEnded { value in
                                showMagnifier = false
                                let loc = value.location
                                if loc.x >= 0 && loc.x <= imageFrame.width &&
                                   loc.y >= 0 && loc.y <= imageFrame.height {
                                    handleTap(at: loc, in: imageFrame.size)
                                }
                            }
                    )
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)

                    // Magnifier loupe in top corner
                    if showMagnifier {
                        MagnifierLoupe(
                            image: image,
                            touchPoint: touchPosition,
                            displaySize: imageFrame.size
                        )
                        .position(
                            x: touchPosition.x < imageFrame.width / 2 ? geo.size.width - 70 : 70,
                            y: 70
                        )
                    }
                }
            }
            .clipped()

            // Status and actions for each mask
            VStack(spacing: 8) {
                // Current action buttons
                HStack {
                    Button {
                        tapPoints = []
                    } label: {
                        Text("[Clear Points]")
                            .font(.terminalSmall)
                            .foregroundColor(.terminalDim)
                    }

                    Spacer()

                    if currentSelection != .center && tapPoints.count >= 2 {
                        Button {
                            createMaskFromPoints()
                        } label: {
                            Text("[Done]")
                                .font(.terminalSmall)
                                .foregroundColor(.terminalGreen)
                        }
                    }

                    if zoomScale > 1 {
                        Button {
                            withAnimation {
                                zoomScale = 1.0
                                lastZoomScale = 1.0
                                zoomOffset = .zero
                                lastZoomOffset = .zero
                            }
                        } label: {
                            Text("[Reset Zoom]")
                                .font(.terminalSmall)
                                .foregroundColor(.terminalDim)
                        }
                    }
                }

                // Mask status with delete buttons
                HStack(spacing: 16) {
                    centerStatusButton()
                    maskStatusButton(.hour, isSet: hourHandMask != nil) {
                        hourHandMask = nil
                        hourHandPoints = []
                    }
                    maskStatusButton(.minute, isSet: minuteHandMask != nil) {
                        minuteHandMask = nil
                        minuteHandPoints = []
                    }
                    maskStatusButton(.second, isSet: secondHandMask != nil) {
                        secondHandMask = nil
                        secondHandPoints = []
                    }
                }
            }
        }
    }

    private func maskStatusButton(_ type: HandType, isSet: Bool, onDelete: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(isSet ? "✓" : "○")
                .font(.terminalSmall)
                .foregroundColor(isSet ? .terminalGreen : .terminalDim)
            Text(type.rawValue)
                .font(.terminalSmall)
                .foregroundColor(isSet ? .terminalGreen : .terminalDim)
            if isSet {
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.red.opacity(0.7))
                }
            }
        }
    }

    private func centerStatusButton() -> some View {
        let isDefault = centerPoint.x == 0.5 && centerPoint.y == 0.5
        return HStack(spacing: 4) {
            Text(isDefault ? "○" : "✓")
                .font(.terminalSmall)
                .foregroundColor(isDefault ? .terminalDim : .terminalGreen)
            Text("Center")
                .font(.terminalSmall)
                .foregroundColor(isDefault ? .terminalDim : .terminalGreen)
            if !isDefault {
                Button {
                    centerPoint = CGPoint(x: 0.5, y: 0.5)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.red.opacity(0.7))
                }
            }
        }
    }

    private func isMaskSet(for type: HandType) -> Bool {
        switch type {
        case .hour:
            return hourHandMask != nil
        case .minute:
            return minuteHandMask != nil
        case .second:
            return secondHandMask != nil
        case .center:
            return centerPoint.x != 0.5 || centerPoint.y != 0.5
        }
    }

    private var instructionText: String {
        switch currentSelection {
        case .center:
            if isMaskSet(for: .center) {
                return "Center set. Tap to adjust, or select Hour above."
            }
            return "Tap the center of the watch face"
        case .hour:
            if isMaskSet(for: .hour) {
                return "Hour set. Tap to redo, or select Minute above."
            }
            return "Tap 2+ points along hour hand, then [Done]"
        case .minute:
            if isMaskSet(for: .minute) {
                return "Minute set. Tap to redo, or select Second above."
            }
            return "Tap 2+ points along minute hand, then [Done]"
        case .second:
            if isMaskSet(for: .second) {
                return "Second set. Press Next when done."
            }
            return "Optional: Tap 2+ points along second hand"
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

    private func handleTap(at point: CGPoint, in imageSize: CGSize) {
        // Point is already in image coordinate space (0 to imageSize.width/height)

        if currentSelection == .center {
            // No snapping for center - user should tap exactly on center
            // Set center point (normalized 0-1)
            let normalizedX = point.x / imageSize.width
            let normalizedY = point.y / imageSize.height
            centerPoint = CGPoint(x: normalizedX, y: normalizedY)
            // Don't auto-advance - user can tap again to adjust, then press Continue
        } else {
            // Use raw point directly (snap-to-contrast disabled for now)
            tapPoints.append(point)
        }
    }

    /// Find the darkest pixel within a radius of the tap point (watch hands are usually dark)
    private func snapToContrast(point: CGPoint, in displaySize: CGSize, radius: CGFloat) -> CGPoint {
        // Use image.size which reflects the displayed dimensions (accounting for orientation)
        let imgWidth = Int(image.size.width)
        let imgHeight = Int(image.size.height)

        // Convert display point to image pixel coordinates
        let scaleX = CGFloat(imgWidth) / displaySize.width
        let scaleY = CGFloat(imgHeight) / displaySize.height
        let imgX = Int(point.x * scaleX)
        let imgY = Int(point.y * scaleY)
        let searchRadius = Int(radius * scaleX)

        // Use UIGraphics to get pixel data with correct orientation
        // This draws the UIImage respecting its orientation metadata
        UIGraphicsBeginImageContextWithOptions(image.size, true, 1.0)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        guard let drawnImage = UIGraphicsGetImageFromCurrentImageContext(),
              let cgImage = drawnImage.cgImage else {
            UIGraphicsEndImageContext()
            return point
        }
        UIGraphicsEndImageContext()

        // Create context to read pixel data
        guard let context = CGContext(
            data: nil,
            width: imgWidth,
            height: imgHeight,
            bitsPerComponent: 8,
            bytesPerRow: imgWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return point }

        // Draw the already-correctly-oriented CGImage
        // No flip needed since UIGraphics already produced correct orientation
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: imgWidth, height: imgHeight))

        guard let data = context.data else { return point }
        let pixels = data.bindMemory(to: UInt8.self, capacity: imgWidth * imgHeight * 4)

        var darkestPoint = (x: imgX, y: imgY)
        var darkestBrightness: CGFloat = 1.0

        // Search in radius for darkest pixel
        for dy in -searchRadius...searchRadius {
            for dx in -searchRadius...searchRadius {
                // Check if within circular radius
                if dx * dx + dy * dy > searchRadius * searchRadius { continue }

                let nx = imgX + dx
                let ny = imgY + dy

                // Bounds check
                if nx >= 0 && nx < imgWidth && ny >= 0 && ny < imgHeight {
                    // CGContext stores pixels with origin at bottom-left
                    // So flip Y to convert from top-left (UIKit) to bottom-left (CG)
                    let bufferY = imgHeight - 1 - ny
                    let pixelIdx = (bufferY * imgWidth + nx) * 4
                    let r = CGFloat(pixels[pixelIdx]) / 255.0
                    let g = CGFloat(pixels[pixelIdx + 1]) / 255.0
                    let b = CGFloat(pixels[pixelIdx + 2]) / 255.0

                    // Calculate brightness (luminance)
                    let brightness = 0.299 * r + 0.587 * g + 0.114 * b

                    if brightness < darkestBrightness {
                        darkestBrightness = brightness
                        darkestPoint = (x: nx, y: ny)
                    }
                }
            }
        }

        // Convert back to display coordinates
        return CGPoint(
            x: CGFloat(darkestPoint.x) / scaleX,
            y: CGFloat(darkestPoint.y) / scaleY
        )
    }

    /// Normalize image orientation so CGImage matches the displayed orientation
    private func normalizeImageOrientation(_ image: UIImage) -> UIImage? {
        guard image.imageOrientation != .up else { return image }

        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return normalizedImage
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

        // Convert view points to image pixel coordinates
        // tapPoints are in image display coordinates (0 to displayedImageSize)
        // We need to scale to actual image pixel dimensions
        // Note: CGContext has origin at bottom-left, so we flip Y
        let displayedImageSize = imageSize.width > 0 ? imageSize : CGSize(width: CGFloat(width), height: CGFloat(height))

        let imagePoints = tapPoints.map { viewPoint -> CGPoint in
            let normalizedX = viewPoint.x / displayedImageSize.width
            let normalizedY = viewPoint.y / displayedImageSize.height

            return CGPoint(
                x: normalizedX * CGFloat(width),
                y: (1.0 - normalizedY) * CGFloat(height)  // Flip Y for CGContext
            )
        }

        // Draw hand as a thick line from center through points
        // Also flip Y for center point
        let centerImagePoint = CGPoint(
            x: centerPoint.x * CGFloat(width),
            y: (1.0 - centerPoint.y) * CGFloat(height)  // Flip Y for CGContext
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

        // Store the mask and save the points in normalized coordinates for display
        // Convert from display coordinates to normalized (0-1)
        let normalizedPoints = tapPoints.map { point in
            CGPoint(
                x: point.x / displayedImageSize.width,
                y: point.y / displayedImageSize.height
            )
        }

        switch currentSelection {
        case .hour:
            hourHandMask = maskImage
            hourHandPoints = normalizedPoints
        case .minute:
            minuteHandMask = maskImage
            minuteHandPoints = normalizedPoints
        case .second:
            secondHandMask = maskImage
            secondHandPoints = normalizedPoints
        case .center:
            break
        }

        // Clear current editing points
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

// MARK: - Crosshair View

struct CrosshairView: View {
    var body: some View {
        ZStack {
            // Vertical line
            Rectangle()
                .fill(Color.terminalBright)
                .frame(width: 1, height: 30)
            // Horizontal line
            Rectangle()
                .fill(Color.terminalBright)
                .frame(width: 30, height: 1)
            // Center dot
            Circle()
                .fill(Color.terminalGreen)
                .frame(width: 6, height: 6)
        }
    }
}

// MARK: - Magnifier Loupe

struct MagnifierLoupe: View {
    let image: UIImage
    let touchPoint: CGPoint
    let displaySize: CGSize
    let loupeSize: CGFloat = 120
    let magnification: CGFloat = 2.5

    var body: some View {
        // Convert touch point to normalized coordinates (0-1)
        let normalizedX = touchPoint.x / displaySize.width
        let normalizedY = touchPoint.y / displaySize.height

        // Get the cropped and zoomed image centered on the touch point
        let croppedImage = cropImage(normalizedCenter: CGPoint(x: normalizedX, y: normalizedY))

        return ZStack {
            // Background
            Circle()
                .fill(Color.black)
                .frame(width: loupeSize, height: loupeSize)

            // Cropped zoomed image
            if let croppedImage = croppedImage {
                Image(uiImage: croppedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: loupeSize, height: loupeSize)
            }

            // Crosshair
            CrosshairView()
        }
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.terminalGreen, lineWidth: 3)
        )
        .shadow(color: .black.opacity(0.5), radius: 5)
        .frame(width: loupeSize, height: loupeSize)
    }

    /// Crop a region of the image centered on the normalized point
    private func cropImage(normalizedCenter: CGPoint) -> UIImage? {
        // First, normalize the image orientation to ensure CGImage matches display
        guard let normalizedImage = normalizeImageOrientation(image),
              let cgImage = normalizedImage.cgImage else { return nil }

        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)

        // Calculate the size of the region to crop (inverse of magnification)
        let cropWidth = imageWidth / magnification
        let cropHeight = imageHeight / magnification

        // Calculate crop rect centered on the touch point
        let centerX = normalizedCenter.x * imageWidth
        let centerY = normalizedCenter.y * imageHeight

        var cropRect = CGRect(
            x: centerX - cropWidth / 2,
            y: centerY - cropHeight / 2,
            width: cropWidth,
            height: cropHeight
        )

        // Clamp to image bounds
        cropRect.origin.x = max(0, min(cropRect.origin.x, imageWidth - cropWidth))
        cropRect.origin.y = max(0, min(cropRect.origin.y, imageHeight - cropHeight))

        // Crop the image
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else { return nil }

        return UIImage(cgImage: croppedCGImage)
    }

    /// Normalize image orientation so CGImage matches the displayed orientation
    private func normalizeImageOrientation(_ image: UIImage) -> UIImage? {
        guard image.imageOrientation != .up else { return image }

        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return normalizedImage
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
