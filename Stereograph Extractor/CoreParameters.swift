//
//  CoreParameters.swift
//  Stereograph Extractor
//
//  Created by Hal Mueller on 8/30/25.
//

import SwiftUI
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import AppKit

// MARK: - Tunable Parameters (same defaults as before)

public struct SegmentParams: Equatable {
    // Yellow (HSV) — collar yellow broadened to cover 239,194,94 and 253,214,77
    public var hYellowLow:  Float = 0.11   // ~40°
    public var hYellowHigh: Float = 0.15   // ~54°
    public var sYellowMin:  Float = 0.55   // down from 0.70 → now covers ~0.61
    public var vYellowMin:  Float = 0.90   // down from 0.99 → now covers ~0.94
    
    // Paper (HSV) — treat sPaperMin as a MAX saturation limit (<=), v as bright
    public var hPaperLow: Float  = 0.0
    public var hPaperHigh: Float = 1.0
    public var sPaperMin: Float  = 0.25   // interpreted as S <= sPaperMin
    public var vPaperMin: Float  = 0.85

    // MARK: - Edge scan parameters
    /// Fraction of the image edge scanned inward (0–1).
    /// Larger values scan deeper into the image to find where the collar/paper ends.
    /// Too small and you might miss the yellow border; too large and you risk creeping into content.
    public var maxScanFrac: Float = 0.50

    /// Threshold (fraction along the scan line) at which to start treating pixels as foreground.
    /// Lower = more aggressive cropping; higher = more conservative.
    public var startThresh: Float = 0.20

    /// Threshold (fraction along the scan line) at which to stop treating pixels as background.
    /// Lower = shorter collar strip, higher = extend deeper.
    public var endThresh:   Float = 0.80


    // MARK: - Padding adjustments
    /// Extra horizontal padding added to the detected box (fraction of image width).
    /// Helps prevent accidental clipping of the stereo images.
    public var padFracX: Float = 0.01

    /// Extra vertical padding added to the detected box (fraction of image height).
    /// Adds headroom/footroom after detection.
    public var padFracY: Float = 0.01


    // MARK: - Safety and fallback controls
    /// Minimum fraction of the image width/height to preserve,
    /// regardless of detection. Prevents over-cropping.
    public var minKeepFrac: Float = 0.80

    /// Maximum total fraction of the image that may be cropped away.
    /// Prevents discarding too much when thresholds overshoot.
    public var maxTotalCropFrac: Float = 0.40

    /// Fallback: fraction of width to keep on the left edge
    /// if detection fails (i.e., no clear collar found).
    public var fallbackLeftFrac:  Float = 0.48

    /// Fallback: fraction to keep on the other edges (right/top/bottom)
    /// if detection fails.
    public var fallbackOtherFrac: Float = 0.48


    // MARK: - Optional post-bias
    /// After a box is detected, bias it inward/outward
    /// by a fraction of width (X) or height (Y).
    /// Useful to fix systematic over- or under-cropping.
    public var postBiasX: Float = 0.0
    public var postBiasY: Float = 0.0
    public init() {}
}

public struct SegmentResult {
    public let bbox: CGRect
    public let fallbackUsed: Bool
    public let mask: CGImage?
    public let debug: CGImage?
}

public enum SegmentError: Error {
    case unsupported
    case cgContext
    case cropFailed
}

// RGB→HSV (0...1)
@inline(__always)
func rgbToHSV(r: Float, g: Float, b: Float) -> (h: Float, s: Float, v: Float) {
    let maxV = max(r, max(g, b))
    let minV = min(r, min(g, b))
    let delta = maxV - minV
    var h: Float = 0
    let v = maxV
    let s = (maxV == 0) ? 0 : (delta / maxV)

    if delta != 0 {
        if maxV == r { h = ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
        else if maxV == g { h = ((b - r) / delta) + 2 }
        else             { h = ((r - g) / delta) + 4 }
        h /= 6
        if h < 0 { h += 1 }
    }
    return (h, s, v)
}

// Build 0/255 paper/yellow mask
public func buildMask(input: CGImage, params: SegmentParams) throws -> (mask: [UInt8], width: Int, height: Int, bytesPerRow: Int) {
    let width = input.width
    let height = input.height
    guard width > 8, height > 8 else { throw SegmentError.unsupported }

    let bpp = 4
    let row = width * bpp
    var rgba = [UInt8](repeating: 0, count: height * row)
    let cs = CGColorSpaceCreateDeviceRGB()

    guard let ctx = CGContext(
        data: &rgba, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: row,
        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw SegmentError.cgContext }

    ctx.draw(input, in: CGRect(x: 0, y: 0, width: width, height: height))

    var mask = [UInt8](repeating: 0, count: width * height)

    for y in 0..<height {
        var idx = y * row
        let mRow = y * width
        for x in 0..<width {
            let (r, g, b) = (Float(rgba[idx]) / 255, Float(rgba[idx+1]) / 255, Float(rgba[idx+2]) / 255)
            let (h, s, v) = rgbToHSV(r: r, g: g, b: b)

            let isYellow = (h >= params.hYellowLow && h <= params.hYellowHigh &&
                            s >= params.sYellowMin && v >= params.vYellowMin)
            // Interpret sPaperMin as a MAX saturation threshold (paper is low-sat, bright)
            let isPaper  = (h >= params.hPaperLow && h <= params.hPaperHigh &&
                            s <= params.sPaperMin && v >= params.vPaperMin)

            mask[mRow + x] = (isYellow || isPaper) ? 255 : 0
            idx += 4
        }
    }

    return (mask, width, height, row)
}

// Scan inward to estimate edges
public func findEdges(mask: [UInt8], width: Int, height: Int, params: SegmentParams)
-> (left: Int, right: Int, top: Int, bottom: Int)
{
    let maxScanX = max(5, Int(Float(width)  * params.maxScanFrac))
    let maxScanY = max(5, Int(Float(height) * params.maxScanFrac))

    var left = 0
    for x in 0..<maxScanX {
        var cnt = 0; for y in 0..<height { if mask[y*width + x] != 0 { cnt += 1 } }
        let frac = Float(cnt)/Float(height)
        let t = params.startThresh + (params.endThresh - params.startThresh) * (Float(x)/Float(maxScanX))
        if frac < t { left = x; break }
        if x == maxScanX - 1 { left = Int(Float(maxScanX) * 0.8) }
    }

    var right = width - 1
    for i in 0..<maxScanX {
        let x = width - 1 - i
        var cnt = 0; for y in 0..<height { if mask[y*width + x] != 0 { cnt += 1 } }
        let frac = Float(cnt)/Float(height)
        let t = params.startThresh + (params.endThresh - params.startThresh) * (Float(i)/Float(maxScanX))
        if frac < t { right = x; break }
        if i == maxScanX - 1 { right = width - 1 - Int(Float(maxScanX) * 0.8) }
    }

    var top = 0
    for y in 0..<maxScanY {
        var cnt = 0; let base = y * width
        for x in 0..<width { if mask[base + x] != 0 { cnt += 1 } }
        let frac = Float(cnt)/Float(width)
        let t = params.startThresh + (params.endThresh - params.startThresh) * (Float(y)/Float(maxScanY))
        if frac < t { top = y; break }
        if y == maxScanY - 1 { top = Int(Float(maxScanY) * 0.8) }
    }

    var bottom = height - 1
    for i in 0..<maxScanY {
        let y = height - 1 - i
        var cnt = 0; let base = y * width
        for x in 0..<width { if mask[base + x] != 0 { cnt += 1 } }
        let frac = Float(cnt)/Float(width)
        let t = params.startThresh + (params.endThresh - params.startThresh) * (Float(i)/Float(maxScanY))
        if frac < t { bottom = y; break }
        if i == maxScanY - 1 { bottom = height - 1 - Int(Float(maxScanY) * 0.8) }
    }

    return (left, right, top, bottom)
}

// Full segmentation
public func segment(input: CGImage,
                    params: SegmentParams = .init(),
                    returnMaskAndDebug: Bool = true) throws -> SegmentResult
{
    let (mask, w, h, row) = try buildMask(input: input, params: params)
    var (l, r, t, b) = findEdges(mask: mask, width: w, height: h, params: params)

    // inward pad
    let padX = max(1, Int(Float(w) * params.padFracX))
    let padY = max(1, Int(Float(h) * params.padFracY))
    l = min(max(l + padX, 0), w - 2)
    r = max(min(r - padX, w - 1), l + 1)
    t = min(max(t + padY, 0), h - 2)
    b = max(min(b - padY, h - 1), t + 1)

    // optional post-bias
    l = min(max(l + Int(Float(w) * params.postBiasX), 0), r - 1)
    r = max(min(r - Int(Float(w) * params.postBiasX), w - 1), l + 1)
    t = min(max(t + Int(Float(h) * params.postBiasY), 0), b - 1)
    b = max(min(b - Int(Float(h) * params.postBiasY), h - 1), t + 1)

    // safety / fallback
    let widthCropFrac  = Float(l + (w - 1 - r)) / Float(w)
    let heightCropFrac = Float(t + (h - 1 - b)) / Float(h)
    var fallbackUsed = false
    if widthCropFrac > params.maxTotalCropFrac ||
       heightCropFrac > params.maxTotalCropFrac ||
       (r - l) < Int(Float(w)  * params.minKeepFrac) ||
       (b - t) < Int(Float(h) * params.minKeepFrac) {

        l = Int(Float(w) * params.fallbackLeftFrac)
        r = Int(Float(w) * (1.0 - params.fallbackOtherFrac))
        t = Int(Float(h) * params.fallbackOtherFrac)
        b = Int(Float(h) * (1.0 - params.fallbackOtherFrac))
        fallbackUsed = true
    }

    let rect = CGRect(x: l, y: t, width: r - l, height: b - t)

    // optional debug assets
    var maskCG: CGImage? = nil
    var debugCG: CGImage? = nil

    if returnMaskAndDebug {
        let cs = CGColorSpaceCreateDeviceRGB()
        var maskRGBA = [UInt8](repeating: 0, count: h * row)
        for y in 0..<h {
            let base = y * w
            let dst  = y * row
            for x in 0..<w {
                let m = mask[base + x]
                maskRGBA[dst + x*4 + 0] = m
                maskRGBA[dst + x*4 + 1] = m
                maskRGBA[dst + x*4 + 2] = 0
                maskRGBA[dst + x*4 + 3] = 255
            }
        }
        if let c = CGContext(data: &maskRGBA, width: w, height: h,
                             bitsPerComponent: 8, bytesPerRow: row,
                             space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            maskCG = c.makeImage()
        }
        debugCG = try? makeDebugOverlay(original: input, cropRect: rect)
    }

    return SegmentResult(bbox: rect, fallbackUsed: fallbackUsed, mask: maskCG, debug: debugCG)
}

// Debug overlay via CoreGraphics
public func makeDebugOverlay(original: CGImage, cropRect: CGRect, lineWidth: CGFloat? = nil) throws -> CGImage {
    let w = original.width, h = original.height
    let cs = CGColorSpaceCreateDeviceRGB()
    let row = w * 4
    var buf = [UInt8](repeating: 0, count: h * row)

    guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: row, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw SegmentError.cgContext
    }

    // draw original
    ctx.draw(original, in: CGRect(x: 0, y: 0, width: w, height: h))

    // stroke rect
    ctx.setStrokeColor(NSColor.systemRed.cgColor)
    ctx.setLineWidth(lineWidth ?? max(2.0, CGFloat(w) * 0.002))
    ctx.stroke(cropRect)

    guard let out = ctx.makeImage() else { throw SegmentError.cgContext }
    return out
}

// Apply user crop
public func applyCrop(original: CGImage, cropRect: CGRect) throws -> CGImage {
    guard let cg = original.cropping(to: cropRect.integral) else { throw SegmentError.cropFailed }
    return cg
}

// Save image (JPEG/PNG/HEIC…)
public func saveImage(_ image: CGImage, to url: URL, type: UTType = .jpeg, quality: CGFloat = 0.95) throws {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
        throw SegmentError.cgContext
    }
    var opts: [CFString: Any] = [:]
    if type == .jpeg { opts[kCGImageDestinationLossyCompressionQuality] = quality }
    CGImageDestinationAddImage(dest, image, opts as CFDictionary)
    CGImageDestinationFinalize(dest)
}
