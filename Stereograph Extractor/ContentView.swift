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
                }
                .frame(width: 360)
            }
            
            Divider()
            
            // Bottom bar…
            HStack {
                Button { openImage() } label: { Label("Open…", systemImage: "folder") }
                    .keyboardShortcut("o", modifiers: .command)
                
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
            let chosenType: UTType = /* pick based on user or original */ .jpeg
            if let url = pickSaveURL(suggestingFrom: originalInputURL, type: chosenType) {
                try saveImage(cropped, to: url, type: chosenType, quality: 0.95)
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
    
}

#Preview {
    ContentView()
}
