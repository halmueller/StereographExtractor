//
//  SingleFile.swift
//  Stereograph Extractor
//
//  Created by Hal Mueller on 8/30/25.
//

import SwiftUI
import CoreGraphics
import UniformTypeIdentifiers
import UIKit

// MARK: - Tunable Parameters

public struct SegmentParams {
    // HSV thresholds (0...1)
    public var hYellowLow: Float = 12.0/255.0
    public var hYellowHigh: Float = 58.0/255.0
    public var sYellowMin: Float = 48.0/255.0
    public var vYellowMin: Float = 58.0/255.0

    public var hPaperLow: Float  = 8.0/255.0
    public var hPaperHigh: Float = 64.0/255.0
    public var sPaperMin: Float  = 25.0/255.0
    public var vPaperMin: Float  = 70.0/255.0

    // Edge scanning behavior
    public var maxScanFrac: Float = 0.30
    public var startThresh: Float = 0.62
    public var endThresh: Float = 0.12

    // Small inward pad to avoid yellow slivers at edges
    public var padFracX: Float = 0.004   // ~0.4%
    public var padFracY: Float = 0.004

    // Safe fallback (if detection looks risky)
    public var fallbackLeftFrac: Float   = 0.08
    public var fallbackOtherFrac: Float  = 0.02
    public var minKeepFrac: Float        = 0.28  // min keep size vs image
    public var maxTotalCropFrac: Float   = 0.45  // avoid overcropping

    public init() {}
}

// MARK: - Results

public struct SegmentResult {
    public let bbox: CGRect
    public let fallbackUsed: Bool
    public let mask: CGImage?   // optional: for visualization
    public let debug: CGImage?  // optional: for visualization
}

// MARK: - Step 1–4: Segment (compute crop rect from yellow/paper border)

public enum SegmentError: Error {
    case unsupported
    case cgContext
    case cropFailed
}

public func segment(input: CGImage, params: SegmentParams = .init(),
                    returnMaskAndDebug: Bool = true) throws -> SegmentResult {
    let width = input.width
    let height = input.height
    guard width > 8, height > 8 else { throw SegmentError.unsupported }

    // 1) RGBA buffer
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var rgba = [UInt8](repeating: 0, count: height * bytesPerRow)
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    guard let ctx = CGContext(
        data: &rgba,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw SegmentError.cgContext }

    ctx.draw(input, in: CGRect(x: 0, y: 0, width: width, height: height))

    // 2) Build mask in HSV (1 = paper/yellow)
    @inline(__always)
    func rgbToHSV(r: Float, g: Float, b: Float) -> (h: Float, s: Float, v: Float) {
        let maxV = max(r, max(g, b))
        let minV = min(r, min(g, b))
        let delta = maxV - minV
        var h: Float = 0
        let v = maxV
        let s = (maxV == 0) ? 0 : (delta / maxV)

        if delta != 0 {
            if maxV == r { h = ( (g - b) / delta ).truncatingRemainder(dividingBy: 6) }
            else if maxV == g { h = ( (b - r) / delta ) + 2 }
            else { h = ( (r - g) / delta ) + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, s, v)
    }

    var mask = [UInt8](repeating: 0, count: width * height)

    for y in 0..<height {
        var idx = y * bytesPerRow
        let mRow = y * width
        for x in 0..<width {
            let r = Float(rgba[idx + 0]) / 255.0
            let g = Float(rgba[idx + 1]) / 255.0
            let b = Float(rgba[idx + 2]) / 255.0
            let (h, s, v) = rgbToHSV(r: r, g: g, b: b)

            let isYellow =
              (h >= params.hYellowLow && h <= params.hYellowHigh &&
               s >= params.sYellowMin && v >= params.vYellowMin)

            let isPaper  =
              (h >= params.hPaperLow  && h <= params.hPaperHigh  &&
               s >= params.sPaperMin  && v >= params.vPaperMin)

            mask[mRow + x] = (isYellow || isPaper) ? 255 : 0
            idx += 4
        }
    }

    // 3) Scan inward from each edge with adaptive thresholds
    func findEdges(mask: [UInt8], width: Int, height: Int) -> (Int, Int, Int, Int) {
        let maxScanX = max(5, Int(Float(width)  * params.maxScanFrac))
        let maxScanY = max(5, Int(Float(height) * params.maxScanFrac))

        // Left
        var left = 0
        for x in 0..<maxScanX {
            var cnt = 0
            for y in 0..<height { if mask[y*width + x] != 0 { cnt += 1 } }
            let frac = Float(cnt) / Float(height)
            let t = params.startThresh + (params.endThresh - params.startThresh) * (Float(x) / Float(maxScanX))
            if frac < t { left = x; break }
            if x == maxScanX - 1 { left = Int(Float(maxScanX) * 0.8) }
        }

        // Right
        var right = width - 1
        for i in 0..<maxScanX {
            let x = width - 1 - i
            var cnt = 0
            for y in 0..<height { if mask[y*width + x] != 0 { cnt += 1 } }
            let frac = Float(cnt) / Float(height)
            let t = params.startThresh + (params.endThresh - params.startThresh) * (Float(i) / Float(maxScanX))
            if frac < t { right = x; break }
            if i == maxScanX - 1 { right = width - 1 - Int(Float(maxScanX) * 0.8) }
        }

        // Top
        var top = 0
        for y in 0..<maxScanY {
            var cnt = 0
            let rowBase = y * width
            for x in 0..<width { if mask[rowBase + x] != 0 { cnt += 1 } }
            let frac = Float(cnt) / Float(width)
            let t = params.startThresh + (params.endThresh - params.startThresh) * (Float(y) / Float(maxScanY))
            if frac < t { top = y; break }
            if y == maxScanY - 1 { top = Int(Float(maxScanY) * 0.8) }
        }

        // Bottom
        var bottom = height - 1
        for i in 0..<maxScanY {
            let y = height - 1 - i
            var cnt = 0
            let rowBase = y * width
            for x in 0..<width { if mask[rowBase + x] != 0 { cnt += 1 } }
            let frac = Float(cnt) / Float(width)
            let t = params.startThresh + (params.endThresh - params.startThresh) * (Float(i) / Float(maxScanY))
            if frac < t { bottom = y; break }
            if i == maxScanY - 1 { bottom = height - 1 - Int(Float(maxScanY) * 0.8) }
        }

        return (left, right, top, bottom)
    }

    var (l, r, t, b) = findEdges(mask: mask, width: width, height: height)

    // 4) Small inward pad to avoid tiny slivers
    let padX = max(1, Int(Float(width)  * params.padFracX))
    let padY = max(1, Int(Float(height) * params.padFracY))
    l = min(max(l + padX, 0), width - 2)
    r = max(min(r - padX, width - 1), l + 1)
    t = min(max(t + padY, 0), height - 2)
    b = max(min(b - padY, height - 1), t + 1)

    // Safety / fallback
    let widthCropFrac  = Float(l + (width - 1 - r)) / Float(width)
    let heightCropFrac = Float(t + (height - 1 - b)) / Float(height)

    var fallbackUsed = false
    if widthCropFrac > params.maxTotalCropFrac ||
       heightCropFrac > params.maxTotalCropFrac ||
       (r - l) < Int(Float(width)  * params.minKeepFrac) ||
       (b - t) < Int(Float(height) * params.minKeepFrac) {

        l = Int(Float(width)  * params.fallbackLeftFrac)
        r = Int(Float(width)  * (1.0 - params.fallbackOtherFrac))
        t = Int(Float(height) * params.fallbackOtherFrac)
        b = Int(Float(height) * (1.0 - params.fallbackOtherFrac))
        fallbackUsed = true
    }

    let rect = CGRect(x: l, y: t, width: r - l, height: b - t)

    // Optional outputs (mask + debug)
    var maskCG: CGImage? = nil
    var debugCG: CGImage? = nil

    if returnMaskAndDebug {
        // gray/yellow mask visualization
        var maskRGBA = [UInt8](repeating: 0, count: height * bytesPerRow)
        for y in 0..<height {
            let rowBase = y * width
            let dstBase = y * bytesPerRow
            for x in 0..<width {
                let m = mask[rowBase + x]  // 0 or 255
                maskRGBA[dstBase + x*4 + 0] = m
                maskRGBA[dstBase + x*4 + 1] = m
                maskRGBA[dstBase + x*4 + 2] = 0
                maskRGBA[dstBase + x*4 + 3] = 255
            }
        }
        if let mctx = CGContext(
            data: &maskRGBA,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) {
            maskCG = mctx.makeImage()
        }

        // Debug overlay
        UIGraphicsBeginImageContextWithOptions(CGSize(width: width, height: height), false, 1.0)
        UIImage(cgImage: input).draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        let path = UIBezierPath(rect: rect)
        UIColor.red.setStroke()
        path.lineWidth = max(2.0, CGFloat(width) * 0.002)
        path.stroke()
        debugCG = UIGraphicsGetImageFromCurrentImageContext()?.cgImage
        UIGraphicsEndImageContext()
    }

    return SegmentResult(bbox: rect, fallbackUsed: fallbackUsed, mask: maskCG, debug: debugCG)
}

// MARK: - Make debug overlay (for display in SwiftUI)

public func makeDebugOverlay(original: CGImage, cropRect: CGRect, lineWidth: CGFloat? = nil) throws -> CGImage {
    let w = original.width, h = original.height
    UIGraphicsBeginImageContextWithOptions(CGSize(width: w, height: h), false, 1.0)
    UIImage(cgImage: original).draw(in: CGRect(x: 0, y: 0, width: w, height: h))
    let path = UIBezierPath(rect: cropRect)
    UIColor.red.setStroke()
    path.lineWidth = lineWidth ?? max(2.0, CGFloat(w) * 0.002)
    path.stroke()
    let out = UIGraphicsGetImageFromCurrentImageContext()?.cgImage
    UIGraphicsEndImageContext()
    guard let cg = out else { throw SegmentError.cgContext }
    return cg
}

// MARK: - Apply user-adjusted crop

public func applyCrop(original: CGImage, cropRect: CGRect) throws -> CGImage {
    guard let cg = original.cropping(to: cropRect.integral) else {
        throw SegmentError.cropFailed
    }
    return cg
}

// MARK: - Save (JPEG/PNG)

public func saveImage(_ image: CGImage, to url: URL, type: UTType = .jpeg, quality: CGFloat = 0.95) throws {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
        throw SegmentError.cgContext
    }
    var options: [CFString: Any] = [:]
    if type == .jpeg {
        options[kCGImageDestinationLossyCompressionQuality] = quality
    }
    CGImageDestinationAddImage(dest, image, options as CFDictionary)
    CGImageDestinationFinalize(dest)
}

// MARK: - SwiftUI crop overlay (drag + resize)

struct CropAdjustView: View {
    let original: CGImage
    @Binding var cropRect: CGRect     // in image coordinates
    @State private var dragOffset: CGSize = .zero
    @State private var lastDrag: CGSize = .zero

    // simple resizers
    private let handleSize: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            // Display original image
            let uiImage = UIImage(cgImage: original)
            let img = Image(uiImage: uiImage).resizable().interpolation(.high)
            let imageSize = CGSize(width: original.width, height: original.height)

            // Fit the image in the available geometry preserving aspect
            let scale = min(geo.size.width / imageSize.width, geo.size.height / imageSize.height)
            let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
            let origin = CGPoint(x: (geo.size.width - drawSize.width) / 2.0,
                                 y: (geo.size.height - drawSize.height) / 2.0)

            ZStack(alignment: .topLeading) {
                img
                    .frame(width: drawSize.width, height: drawSize.height)
                    .position(x: origin.x + drawSize.width/2, y: origin.y + drawSize.height/2)

                // Crop rect overlay (convert image-space -> view-space)
                let viewRect = CGRect(
                    x: origin.x + cropRect.minX * scale,
                    y: origin.y + cropRect.minY * scale,
                    width: cropRect.width * scale,
                    height: cropRect.height * scale
                )

                // translucent fill + stroke
                Color.clear
                    .overlay(
                        Rectangle()
                            .path(in: viewRect)
                            .stroke(Color.red, lineWidth: max(2, drawSize.width * 0.002))
                            .background(Rectangle().fill(Color.red.opacity(0.12)).clipShape(Rectangle().path(in: viewRect)))
                    )

                // Dragging the whole rect
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .frame(width: viewRect.width, height: viewRect.height)
                    .position(x: viewRect.midX, y: viewRect.midY)
                    .gesture(
                        DragGesture()
                            .onChanged { g in
                                let dx = g.translation.width / scale
                                let dy = g.translation.height / scale
                                var new = cropRect
                                new.origin.x += dx
                                new.origin.y += dy
                                // Clamp to image bounds
                                new.origin.x = max(0, min(new.origin.x, imageSize.width - new.size.width))
                                new.origin.y = max(0, min(new.origin.y, imageSize.height - new.size.height))
                                cropRect = new
                            }
                    )

                // Corner handles for resizing (just top-left and bottom-right for brevity)
                handle(at: CGPoint(x: viewRect.minX, y: viewRect.minY))
                    .gesture(
                        DragGesture().onChanged { g in
                            var new = cropRect
                            let dx = g.translation.width / scale
                            let dy = g.translation.height / scale
                            new.origin.x = max(0, min(new.maxX - 20, new.origin.x + dx))
                            new.origin.y = max(0, min(new.maxY - 20, new.origin.y + dy))
                            new.size.width  = max(20, cropRect.maxX - new.origin.x)
                            new.size.height = max(20, cropRect.maxY - new.origin.y)
                            cropRect = new
                        }
                    )

                handle(at: CGPoint(x: viewRect.maxX, y: viewRect.maxY))
                    .gesture(
                        DragGesture().onChanged { g in
                            var new = cropRect
                            let dx = g.translation.width / scale
                            let dy = g.translation.height / scale
                            new.size.width  = max(20, min(imageSize.width - new.origin.x, new.size.width + dx))
                            new.size.height = max(20, min(imageSize.height - new.origin.y, new.size.height + dy))
                            cropRect = new
                        }
                    )
            }
        }
    }

    @ViewBuilder
    private func handle(at p: CGPoint) -> some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(Color.red, lineWidth: 2))
            .frame(width: handleSize, height: handleSize)
            .position(p)
            .shadow(radius: 1)
    }
}

// MARK: - Example usage

struct ContentView: View {
    @State private var resultRect: CGRect = .zero
    @State private var original: CGImage?

    var body: some View {
        VStack {
            if let original {
                CropAdjustView(original: original, cropRect: $resultRect)
                    .border(Color.gray.opacity(0.4))
                    .onAppear {
                        // Run segmentation on appear (step 1–4), then let user adjust
                        if resultRect == .zero {
                            if let r = try? segment(input: original, params: SegmentParams(), returnMaskAndDebug: false) {
                                resultRect = r.bbox
                            }
                        }
                    }

                HStack {
                    Button("Apply Crop & Save") {
                        do {
                            let cropped = try applyCrop(original: original, cropRect: resultRect)
                            let tmpURL = FileManager.default.temporaryDirectory
                                .appendingPathComponent("stereo_cropped.jpg")
                            try saveImage(cropped, to: tmpURL, type: .jpeg, quality: 0.95)
                            print("Saved to:", tmpURL)
                        } catch {
                            print("Crop/save failed:", error)
                        }
                    }
                }
                .padding()
            } else {
                Text("Load an image…")
            }
        }
        .onAppear {
            // Demo: load a bundled image (replace with your loader)
            if let ui = UIImage(named: "stereograph"),
               let cg = ui.cgImage {
                self.original = cg
            }
        }
        .padding()
    }
}
