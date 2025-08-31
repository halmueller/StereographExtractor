//
//  ContentView.swift
//  Stereograph Extractor
//
//  Created by Hal Mueller on 8/30/25.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit
import CoreGraphics
import Accelerate

struct ContentView: View {
    @State private var original: CGImage?
    @State private var originalInputURL: URL?
    @State private var cropRect: CGRect = .zero
    @State private var params = SegmentParams()
    @State private var showMask = false
    @State private var maskCG: CGImage?
    @State private var debugCG: CGImage?
    @State private var fallbackUsed = false
    @State private var keyMonitor: Any?
    // Tuning state
    @State private var trainingSamples: [(url: URL?, image: CGImage, gtRect: CGRect)] = []
    @State private var isTuning: Bool = false
    
    private let numFmt: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()
    
    // Resize handle settings
    private let minSide: CGFloat = 20
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // LEFT: image/editor
                ZStack {
                    if let cg = original {
                        if showMask, let maskCG {
                            Image(nsImage: NSImage(cgImage: maskCG,
                                                   size: .init(width: maskCG.width, height: maskCG.height)))
                            .resizable().interpolation(.high).scaledToFit()
                        } else {
                            // Use dedicated CropAdjustView for editing
                            CropAdjustView(original: cg, cropRect: $cropRect)
                        }
                    } else {
                        Text("Open an image (⌘O)").foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 500, minHeight: 400)
                .background(Color.black.opacity(0.04))
                
                Divider()
                
                // RIGHT: controls + bbox inspector
                VStack(spacing: 10) {
                    SegControlsView(params: $params) {
                        runSegmentation()
                    }
                    Divider()
                    GroupBox("BBox Inspector (px)") {
                        VStack(alignment: .leading, spacing: 8) {
                            // LEFT inset (pixels from left edge)
                            HStack {
                                Text("Left").frame(width: 60, alignment: .trailing)
                                TextField("Left", value: Binding(
                                    get: { Swift.Double(cropRect.minX) },
                                    set: { (v: Double) in applyLeftInset(v) }
                                ), formatter: numFmt)
                                Stepper("") {
                                    nudgeLeftInset(+1)
                                } onDecrement: {
                                    nudgeLeftInset(-1)
                                }.labelsHidden()
                            }
                            
                            // RIGHT inset (pixels from right edge)
                            HStack {
                                Text("Right").frame(width: 60, alignment: .trailing)
                                TextField("Right", value: Binding(
                                    get: {
                                        guard let cg = original else { return 0 }
                                        let imgW = Swift.Double(cg.width)
                                        return imgW - Swift.Double(cropRect.maxX)
                                    },
                                    set: { (v: Double) in applyRightInset(v) }
                                ), formatter: numFmt)
                                Stepper("") {
                                    nudgeRightInset(+1)
                                } onDecrement: {
                                    nudgeRightInset(-1)
                                }.labelsHidden()
                            }
                            
                            // TOP inset (pixels from top edge)
                            HStack {
                                Text("Top").frame(width: 60, alignment: .trailing)
                                TextField("Top", value: Binding(
                                    get: { Swift.Double(cropRect.minY) },
                                    set: { (v: Double) in applyTopInset(v) }
                                ), formatter: numFmt)
                                Stepper("") {
                                    nudgeTopInset(+1)
                                } onDecrement: {
                                    nudgeTopInset(-1)
                                }.labelsHidden()
                            }
                            
                            // BOTTOM inset (pixels from bottom edge)
                            HStack {
                                Text("Bottom").frame(width: 60, alignment: .trailing)
                                TextField("Bottom", value: Binding(
                                    get: {
                                        guard let cg = original else { return 0 }
                                        let imgH = Swift.Double(cg.height)
                                        return imgH - Swift.Double(cropRect.maxY)
                                    },
                                    set: { (v: Double) in applyBottomInset(v) }
                                ), formatter: numFmt)
                                Stepper("") {
                                    nudgeBottomInset(+1)
                                } onDecrement: {
                                    nudgeBottomInset(-1)
                                }.labelsHidden()
                            }
                            
                            Text("Insets are pixels from each image edge. Width/height are implied.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)
                    }
                    Divider()
                    GroupBox("Tuning") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Samples: \(trainingSamples.count)")
                                Spacer()
                                Button { addCurrentSample() } label: { Label("Add sample", systemImage: "plus.circle") }
                                    .disabled(original == nil || cropRect.isEmpty)
                                Button { addPairViaPicker() } label: { Label("Add pair…", systemImage: "rectangle.on.rectangle") }
                                Button { batchAddFromFolder() } label: { Label("Open training set…", systemImage: "tray.and.arrow.down.fill") }
                            }
                            HStack(spacing: 12) {
                                Button {
                                    runTuning()
                                } label: { Label("Tune params", systemImage: "slider.horizontal.3") }
                                .disabled(trainingSamples.isEmpty || isTuning)

                                if isTuning { ProgressView().controlSize(.small) }
                            }
                            Text("Add 4+ (original,crop) pairs, then Tune. The search adjusts thresholds/padding/scan to maximize IoU vs your boxes.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)
                    }
                }
                .frame(width: 360)
            }
            
            Divider()
            
            // Bottom bar…
            HStack {
                Button { openImage() } label: { Label("Open…", systemImage: "folder") }
                    .keyboardShortcut("o", modifiers: .command)
                Button { batchAddFromFolder() } label: { Label("Open Training Set…", systemImage: "tray.and.arrow.down.fill") }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                Toggle("Show mask/overlay", isOn: $showMask)
                Spacer()
                Text(fallbackUsed ? "Fallback used" : "Detection used")
                    .foregroundStyle(fallbackUsed ? .orange : .green)
                Button { runSegmentation() } label: { Label("Re-segment", systemImage: "wand.and.stars") }
                Button { applyAndSave() } label: { Label("Apply Crop & Save…", systemImage: "square.and.arrow.down") }
                    .buttonStyle(.borderedProminent)
            }
            .padding(10)
        }
        .frame(minWidth: 980, minHeight: 640)
        .onAppear {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { ev in
                let step: CGFloat = ev.modifierFlags.contains(.shift) ? 10 : 1
                let isResize = ev.modifierFlags.contains(.option)
                switch ev.keyCode {
                    case 123: // left
                        if isResize { resize(dw: -step, dh: 0) } else { nudge(dx: -step, dy: 0) }
                        return nil
                    case 124: // right
                        if isResize { resize(dw: step, dh: 0) } else { nudge(dx: step, dy: 0) }
                        return nil
                    case 125: // down
                        if isResize { resize(dw: 0, dh: step) } else { nudge(dx: 0, dy: step) }
                        return nil
                    case 126: // up
                        if isResize { resize(dw: 0, dh: -step) } else { nudge(dx: 0, dy: -step) }
                        return nil
                    default:
                        break
                }
                return ev
            }
        }
        .onDisappear {
            if let m = keyMonitor { NSEvent.removeMonitor(m) }
            keyMonitor = nil
        }
    }
    
    private func openImage() {
        if let url = pickImageURL(),
           let cg = cgImageFromURL(url) {
            originalInputURL = url
            original = cg
            runSegmentation()
        }
    }
    
    private func runSegmentation() {
        guard let cg = original else { return }
        if let result = try? segment(input: cg, params: params, returnMaskAndDebug: true) {
            cropRect = result.bbox
            maskCG = result.mask
            debugCG = result.debug
            fallbackUsed = result.fallbackUsed
        }
    }
    
    private func applyAndSave() {
        guard let cg = original else { return }
        do {
            let cropped = try applyCrop(original: cg, cropRect: cropRect)
            let chosenType: UTType = inferredOutputType(from: originalInputURL)
            if let url = pickSaveURL(suggestingFrom: originalInputURL, type: chosenType) {
                try saveImage(cropped, to: url, type: chosenType, quality: 0.95)
                appendBBoxCSV(saveURL: url, originalURL: originalInputURL, image: cg, cropRect: cropRect)
            }
        } catch {
            NSAlert(error: error as NSError).runModal()
        }
    }
    
    // Keyboard nudge and resize helpers
    private func nudge(dx: CGFloat, dy: CGFloat) {
        guard let cg = original else { return }
        var r = cropRect
        r.origin.x = max(0, min(r.origin.x + dx, CGFloat(cg.width)  - r.width))
        r.origin.y = max(0, min(r.origin.y + dy, CGFloat(cg.height) - r.height))
        cropRect = r
    }
    
    private func resize(dw: CGFloat, dh: CGFloat) {
        guard let cg = original else { return }
        var r = cropRect
        r.size.width  = max(minSide, min(r.size.width  + dw, CGFloat(cg.width)  - r.origin.x))
        r.size.height = max(minSide, min(r.size.height + dh, CGFloat(cg.height) - r.origin.y))
        cropRect = r
    }
    // Clamp helpers (use image bounds and minSide)
    private func applyXMin(_ newXmin: CGFloat) {
        guard let cg = original else { return }
        let imgW = CGFloat(cg.width)
        var r = cropRect
        let xmax = r.maxX
        let xmin = max(0, min(newXmin, xmax - minSide))
        r.origin.x = xmin
        r.size.width = max(minSide, xmax - xmin)
        cropRect = r
    }
    
    private func applyXMax(_ newXmax: CGFloat) {
        guard let cg = original else { return }
        let imgW = CGFloat(cg.width)
        var r = cropRect
        let xmin = r.minX
        let xmax = min(imgW, max(xmin + minSide, newXmax))
        r.size.width = xmax - xmin
        cropRect = r
    }
    
    private func applyYMin(_ newYmin: CGFloat) {
        guard let cg = original else { return }
        let imgH = CGFloat(cg.height)
        var r = cropRect
        let ymax = r.maxY
        let ymin = max(0, min(newYmin, ymax - minSide))
        r.origin.y = ymin
        r.size.height = max(minSide, ymax - ymin)
        cropRect = r
    }
    
    private func applyYMax(_ newYmax: CGFloat) {
        guard let cg = original else { return }
        let imgH = CGFloat(cg.height)
        var r = cropRect
        let ymin = r.minY
        let ymax = min(imgH, max(ymin + minSide, newYmax))
        r.size.height = ymax - ymin
        cropRect = r
    }
    
    // Steppers / keyboard helpers
    private func nudgeXMin(_ amount: CGFloat) { applyXMin(cropRect.minX + amount) }
    private func nudgeXMax(_ amount: CGFloat) { applyXMax(cropRect.maxX + amount) }
    private func nudgeYMin(_ amount: CGFloat) { applyYMin(cropRect.minY + amount) }
    private func nudgeYMax(_ amount: CGFloat) { applyYMax(cropRect.maxY + amount) }
    
    // MARK: - Inset-based helpers (pixels from each image edge) — Double API for unambiguous TextField bindings
    private func applyLeftInset(_ left: Double) {
        guard let cg = original else { return }
        let imgW = Double(cg.width)
        var r = cropRect
        let right = imgW - Double(r.maxX)
        let l = max(0, min(left, imgW - right - Double(minSide)))
        r.origin.x = CGFloat(l)
        r.size.width = CGFloat(imgW - l - right)
        cropRect = r
    }

    private func applyRightInset(_ right: Double) {
        guard let cg = original else { return }
        let imgW = Double(cg.width)
        var r = cropRect
        let left = Double(r.minX)
        let rr = max(0, min(right, imgW - left - Double(minSide)))
        r.size.width = CGFloat(imgW - left - rr)
        cropRect = r
    }

    private func applyTopInset(_ top: Double) {
        guard let cg = original else { return }
        let imgH = Double(cg.height)
        var r = cropRect
        let bottom = imgH - Double(r.maxY)
        let t = max(0, min(top, imgH - bottom - Double(minSide)))
        r.origin.y = CGFloat(t)
        r.size.height = CGFloat(imgH - t - bottom)
        cropRect = r
    }

    private func applyBottomInset(_ bottom: Double) {
        guard let cg = original else { return }
        let imgH = Double(cg.height)
        var r = cropRect
        let top = Double(r.minY)
        let bb = max(0, min(bottom, imgH - top - Double(minSide)))
        r.size.height = CGFloat(imgH - top - bb)
        cropRect = r
    }

    private func nudgeLeftInset(_ d: CGFloat)  { applyLeftInset(Double(cropRect.minX) + Double(d)) }
    private func nudgeRightInset(_ d: CGFloat) {
        guard let cg = original else { return }
        let imgW = Double(cg.width)
        let right = imgW - Double(cropRect.maxX)
        applyRightInset(right + Double(d))
    }
    private func nudgeTopInset(_ d: CGFloat)   { applyTopInset(Double(cropRect.minY) + Double(d)) }
    private func nudgeBottomInset(_ d: CGFloat) {
        guard let cg = original else { return }
        let imgH = Double(cg.height)
        let bottom = imgH - Double(cropRect.maxY)
        applyBottomInset(bottom + Double(d))
    }
    
    // MARK: - Tuning helpers
    private func addCurrentSample() {
        guard let cg = original else { return }
        trainingSamples.append((url: originalInputURL, image: cg, gtRect: cropRect))
    }

    private func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let inter = a.intersection(b)
        if inter.isNull || inter.isEmpty { return 0 }
        let interArea = inter.width * inter.height
        let unionArea = a.width * a.height + b.width * b.height - interArea
        if unionArea <= 0 { return 0 }
        return interArea / unionArea
    }

    private func resizedImage(_ image: CGImage, maxDim: CGFloat) -> CGImage {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let scale = max(1.0, max(w, h) / maxDim)
        if scale <= 1.0 { return image }
        let newW = Int((w / scale).rounded())
        let newH = Int((h / scale).rounded())
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: newW, height: newH, bitsPerComponent: 8, bytesPerRow: newW * 4, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return image
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        return ctx.makeImage() ?? image
    }

    private func scaleRect(_ r: CGRect, from src: CGSize, to dst: CGSize) -> CGRect {
        let sx = dst.width / src.width
        let sy = dst.height / src.height
        return CGRect(x: r.minX * sx, y: r.minY * sy, width: r.width * sx, height: r.height * sy)
    }

    private func clamp01(_ v: CGFloat) -> CGFloat { max(0, min(1, v)) }
    private func clamp01f(_ v: Float) -> Float { max(0, min(1, v)) }
    private func frand(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat { .random(in: lo...hi) }
    private func frandf(_ lo: Float, _ hi: Float) -> Float { Float.random(in: lo...hi) }

    private func runTuning(iterations: Int = 250, maxDim: CGFloat = 1400) {
        guard !trainingSamples.isEmpty else { return }
        isTuning = true
        defer { isTuning = false }

        // Downscale samples for faster scoring
        var ds: [(image: CGImage, gt: CGRect)] = []
        ds.reserveCapacity(trainingSamples.count)
        for s in trainingSamples {
            let di = resizedImage(s.image, maxDim: maxDim)
            if di.width == s.image.width && di.height == s.image.height {
                ds.append((image: di, gt: s.gtRect))
            } else {
                let gtScaled = scaleRect(s.gtRect,
                                         from: CGSize(width: s.image.width, height: s.image.height),
                                         to: CGSize(width: di.width, height: di.height))
                ds.append((image: di, gt: gtScaled))
            }
        }

        func score(_ p: SegmentParams) -> CGFloat {
            var total: CGFloat = 0
            var count: CGFloat = 0
            for item in ds {
                if let result = try? segment(input: item.image, params: p, returnMaskAndDebug: false) {
                    total += iou(result.bbox, item.gt)
                    count += 1
                }
            }
            return count > 0 ? total / count : 0
        }

        var best = params
        var bestScore = score(best)
        print("[Tune] starting score =", bestScore)

        for _ in 0..<iterations {
            var cand = best
            // NOTE: HSV threshold fields aren't accessible on SegmentParams from here.
            // If you want them tuned as well, share SegmentParams's definition and
            // we'll hook them up by name (or via nested structs / keypaths).
            // cand.yellowHLo = ...
            // cand.yellowHHi = ...
            // cand.yellowSMin = ...
            // cand.yellowVMin = ...
            // cand.paperHLo  = ...
            // cand.paperHHi  = ...
            // cand.paperSMin = ...
            // cand.paperVMin = ...

            cand.maxScanFrac = clamp01f(best.maxScanFrac + frandf(-0.10, 0.10))
            cand.startThresh = clamp01f(best.startThresh + frandf(-0.10, 0.10))
            cand.endThresh   = clamp01f(best.endThresh   + frandf(-0.10, 0.10))

            cand.padFracX = clamp01f(best.padFracX + frandf(-0.01, 0.01))
            cand.padFracY = clamp01f(best.padFracY + frandf(-0.01, 0.01))

            cand.minKeepFrac = clamp01f(best.minKeepFrac + frandf(-0.05, 0.05))
            cand.maxTotalCropFrac = clamp01f(best.maxTotalCropFrac + frandf(-0.05, 0.05))

            cand.fallbackLeftFrac  = clamp01f(best.fallbackLeftFrac  + frandf(-0.03, 0.03))
            cand.fallbackOtherFrac = clamp01f(best.fallbackOtherFrac + frandf(-0.03, 0.03))

            let sc = score(cand)
            if sc >= bestScore {
                best = cand
                bestScore = sc
            }
        }

        params = best
        print("[Tune] best IoU =", bestScore)
        print("[Tune] params =", best)
    }

    // Allow user to add a pair (original + cropped) and auto-derive bbox
    private func addPairViaPicker() {
        guard let origURL = pickImageURL(title: "Pick ORIGINAL image", message: "Choose the full stereograph image."),
              let cropURL = pickImageURL(title: "Pick CROPPED image", message: "Choose the manually cropped result for the same image.") else { return }
        if let pair = loadPairAndDeriveBBox(originalURL: origURL, croppedURL: cropURL) {
            trainingSamples.append((url: origURL, image: pair.original, gtRect: pair.rectInOriginal))
        } else {
            let alert = NSAlert()
            alert.messageText = "Could not align the cropped image to the original"
            alert.informativeText = "Make sure the cropped image came from the chosen original without resizing or rotation."
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    private func batchAddFromFolder() {
        guard let folder = pickFolderURL(title: "Pick folder with originals and *_cropped images", message: "Files must be in the same folder; cropped files end with _cropped before the extension.") else { return }
        let pairs = findCroppedPairs(in: folder)
        if pairs.isEmpty {
            let alert = NSAlert()
            alert.messageText = "No pairs found"
            alert.informativeText = "Ensure cropped files use the suffix _cropped before the extension."
            alert.alertStyle = .informational
            alert.runModal()
            return
        }
        var added = 0
        for (orig, crop) in pairs {
            if let pr = loadPairAndDeriveBBox(originalURL: orig, croppedURL: crop) {
                trainingSamples.append((url: orig, image: pr.original, gtRect: pr.rectInOriginal))
                added += 1
            }
        }
        let alert = NSAlert()
        alert.messageText = "Batch add complete"
        alert.informativeText = "Found \(pairs.count) pairs, added \(added) samples."
        alert.alertStyle = .informational
        alert.runModal()
    }

// MARK: - CSV logging of bbox
private func appendBBoxCSV(saveURL: URL, originalURL: URL?, image: CGImage, cropRect: CGRect) {
    // Compute insets from each edge (pixels)
    let imgW = Double(image.width)
    let imgH = Double(image.height)
    let left   = Double(cropRect.minX)
    let top    = Double(cropRect.minY)
    let right  = imgW - Double(cropRect.maxX)
    let bottom = imgH - Double(cropRect.maxY)

    let filename = saveURL.lastPathComponent

    // Prefer writing CSV **next to the saved file** (same folder). NSSavePanel grants access here.
    let saveFolder = saveURL.deletingLastPathComponent()
    let saveCSV    = saveFolder.appendingPathComponent("training_bboxes.csv")

    // Secondary: original folder if available (may fail due to sandbox perms)
    let origFolder = originalURL?.deletingLastPathComponent()
    let origCSV    = origFolder?.appendingPathComponent("training_bboxes.csv")

    // CSV row
    let header = "filename,left,top,right,bottom,image_width,image_height\n"
    let line   = "\(filename),\(left),\(top),\(right),\(bottom),\(imgW),\(imgH)\n"

    // Helper to append or create-with-header
    func writeLine(to url: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            // Create file with header
            let data = (header + line).data(using: .utf8)!
            try data.write(to: url, options: .atomic)
        } else {
            let fh = try FileHandle(forWritingTo: url)
            defer { try? fh.close() }
            try fh.seekToEnd()
            let data = line.data(using: .utf8)!
            try fh.write(contentsOf: data)
        }
    }

    // Try save folder first
    do {
        try writeLine(to: saveCSV)
        return
    } catch {
        NSLog("[CSV] Could not write beside saved file: \(error.localizedDescription)")
    }

    // Try original folder second (if any)
    if let origCSV {
        do {
            try writeLine(to: origCSV)
            return
        } catch {
            NSLog("[CSV] Could not write in original folder: \(error.localizedDescription)")
        }
    }

    // Last resort: prompt the user for a location to save/append the CSV
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.commaSeparatedText]
    panel.nameFieldStringValue = "training_bboxes.csv"
    panel.message = "Select where to save the training CSV."
    if panel.runModal() == .OK, let url = panel.url {
        do {
            try writeLine(to: url)
        } catch {
            NSLog("[CSV] Failed to save CSV after user prompt: \(error.localizedDescription)")
        }
    }
}
}


// MARK: - Folder picker and pair discovery

/// File picker (image) with optional title/message
private func pickImageURL(title: String? = nil, message: String? = nil) -> URL? {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.jpeg, .png, .tiff, .heic, .jpeg2000]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    if let t = title { panel.title = t }
    if let m = message { panel.message = m }
    return panel.runModal() == .OK ? panel.url : nil
}

/// Infer output file type from the original input URL (defaults to .jpeg)
private func inferredOutputType(from url: URL?) -> UTType {
    guard let ext = url?.pathExtension.lowercased() else { return .jpeg }
    switch ext {
    case "jp2", "j2k": return .jpeg2000
    case "png":        return .png
    case "tif", "tiff":return .tiff
    case "heic":       return .heic
    case "jpg", "jpeg":return .jpeg
    default:           return .jpeg
    }
}

private func pickFolderURL(title: String? = nil, message: String? = nil) -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    if let t = title { panel.title = t }
    if let m = message { panel.message = m }
    return panel.runModal() == .OK ? panel.url : nil
}

private let supportedImageExtensions: Set<String> = [
    "jpg","jpeg","png","tif","tiff","heic","jp2","j2k"
]

/// Returns (original, cropped) pairs where cropped filename is `<base>_cropped.<ext>`
private func findCroppedPairs(in folder: URL) -> [(URL, URL)] {
    let fm = FileManager.default
    guard let items = try? fm.contentsOfDirectory(
        at: folder,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    ) else { return [] }

    var originals: [String: URL] = [:]
    var croppeds:  [String: URL] = [:]

    for url in items {
        let ext = url.pathExtension.lowercased()
        guard supportedImageExtensions.contains(ext) else { continue }
        let base = url.deletingPathExtension().lastPathComponent
        if base.hasSuffix("_cropped") {
            let origBase = String(base.dropLast("_cropped".count))
            croppeds[origBase] = url
        } else {
            originals[base] = url
        }
    }

    var out: [(URL, URL)] = []
    for (base, o) in originals {
        if let c = croppeds[base] { out.append((o,c)) }
    }
    return out.sorted { $0.0.lastPathComponent < $1.0.lastPathComponent }
}

// MARK: - Pair load + bbox derivation

private struct PairLoadResult { let original: CGImage; let cropped: CGImage; let rectInOriginal: CGRect }

/// Convert CGImage -> 8-bit gray vImage buffer
private func grayBuffer(from cg: CGImage) -> vImage_Buffer? {
    var fmt = vImage_CGImageFormat(
        bitsPerComponent: 8,
        bitsPerPixel: 8,
        colorSpace: nil,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
        version: 0,
        decode: nil,
        renderingIntent: .defaultIntent
    )
    var buf = vImage_Buffer()
    let err = vImageBuffer_InitWithCGImage(&buf, &fmt, nil, cg, vImage_Flags(kvImageNoFlags))
    return (err == kvImageNoError) ? buf : nil
}

/// Downscale buffer so max dimension <= maxDim. Returns the same buffer if no scaling is needed.
private func downscale(_ src: vImage_Buffer, maxDim: Int) -> vImage_Buffer {
    let w = Int(src.width), h = Int(src.height)
    let scale = max(1.0, Double(max(w,h)) / Double(maxDim))
    if scale <= 1.0 { return src }
    let nw = max(1, Int((Double(w)/scale).rounded()))
    let nh = max(1, Int((Double(h)/scale).rounded()))
    var dst = vImage_Buffer()
    vImageBuffer_Init(&dst, UInt(nh), UInt(nw), 8, vImage_Flags(kvImageNoFlags))
    var s = src
    vImageScale_Planar8(&s, &dst, nil, vImage_Flags(kvImageHighQualityResampling))
    return dst
}

/// Brute-force SSD to locate `small` within `big` (on downscaled grayscale)
private func findSubimage(big: vImage_Buffer, small: vImage_Buffer, step: Int = 2) -> (x:Int,y:Int)?{
    let BW = Int(big.width), BH = Int(big.height)
    let SW = Int(small.width), SH = Int(small.height)
    guard SW <= BW && SH <= BH else { return nil }

    var bestErr = Int64.max
    var best: (Int,Int)? = nil

    for y in Swift.stride(from: 0, through: BH - SH, by: step) {
        for x in Swift.stride(from: 0, through: BW - SW, by: step) {
            var err: Int64 = 0
            for j in 0..<SH {
                let bp = big.data.advanced(by: (y + j) * big.rowBytes + x)
                let sp = small.data.advanced(by: j * small.rowBytes)
                let brow = bp.assumingMemoryBound(to: UInt8.self)
                let srow = sp.assumingMemoryBound(to: UInt8.self)
                var rowSum: Int64 = 0
                for i in 0..<SW {
                    let d: Int64 = Int64(brow[i]) - Int64(srow[i])
                    rowSum = rowSum &+ (d * d)
                }
                err = err &+ rowSum
                if err >= bestErr { break }
            }
            if err < bestErr { bestErr = err; best = (x,y) }
        }
    }
    return best
}

/// Derive the crop rect of `cropped` within `original`.
private func deriveCropRect(original: CGImage, cropped: CGImage, maxDim: Int = 1200) -> CGRect? {
    guard let bigG = grayBuffer(from: original), let smallG = grayBuffer(from: cropped) else { return nil }
    let bigDS   = downscale(bigG, maxDim: maxDim)
    let smallDS = downscale(smallG, maxDim: maxDim)

    defer {
        if bigDS.data   != bigG.data   { free(bigDS.data) }
        if smallDS.data != smallG.data { free(smallDS.data) }
        free(bigG.data); free(smallG.data)
    }

    guard let pos = findSubimage(big: bigDS, small: smallDS) else { return nil }
    let sx = CGFloat(original.width) / CGFloat(bigDS.width)
    let sy = CGFloat(original.height) / CGFloat(bigDS.height)
    let x = CGFloat(pos.x) * sx
    let y = CGFloat(pos.y) * sy
    let w = CGFloat(smallDS.width)  * sx
    let h = CGFloat(smallDS.height) * sy
    return CGRect(x: x.rounded(), y: y.rounded(), width: w.rounded(), height: h.rounded())
}

private func loadPairAndDeriveBBox(originalURL: URL, croppedURL: URL) -> PairLoadResult? {
    guard let orig = cgImageFromURL(originalURL), let crop = cgImageFromURL(croppedURL),
          let rect = deriveCropRect(original: orig, cropped: crop) else { return nil }
    return PairLoadResult(original: orig, cropped: crop, rectInOriginal: rect)
}

#Preview {
    ContentView()
}
