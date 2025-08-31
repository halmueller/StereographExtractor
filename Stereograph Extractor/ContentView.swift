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
    @State private var cropRect: CGRect = .zero
    @State private var params = SegmentParams()
    @State private var showMask = false
    @State private var maskCG: CGImage?
    @State private var debugCG: CGImage?
    @State private var fallbackUsed = false
    @State private var keyMonitor: Any?
    @State private var dragStartRect: CGRect?
    
    private let numFmt: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()
    
    // Resize handle settings
    private let handleSize: CGFloat = 18
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
                            // Always show the editor so the red box and handles are live
                            GeometryReader { geo in
                                // (keep your existing editor code here: image, red rect, handles, gestures)
                                let imageSize = CGSize(width: cg.width, height: cg.height)
                                let scale = min(geo.size.width / imageSize.width, geo.size.height / imageSize.height)
                                let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
                                let origin = CGPoint(x: (geo.size.width - drawSize.width) / 2.0,
                                                     y: (geo.size.height - drawSize.height) / 2.0)
                                
                                
                                let nsimg = NSImage(cgImage: cg, size: .init(width: cg.width, height: cg.height))
                                
                                ZStack(alignment: .topLeading) {
                                    // Base image
                                    Image(nsImage: nsimg)
                                        .resizable()
                                        .interpolation(.high)
                                        .frame(width: drawSize.width, height: drawSize.height)
                                        .position(x: origin.x + drawSize.width/2, y: origin.y + drawSize.height/2)
                                        .zIndex(0)
                                        .allowsHitTesting(false)

                                    // Convert image-space cropRect to view-space
                                    let viewRect = CGRect(
                                        x: origin.x + cropRect.minX * scale,
                                        y: origin.y + cropRect.minY * scale,
                                        width: cropRect.width * scale,
                                        height: cropRect.height * scale
                                    )
                                    
                                    // Stroke + translucent fill (don’t steal gestures)
                                    Path { $0.addRect(viewRect) }
                                        .stroke(Color.red, lineWidth: max(2, drawSize.width * 0.002))
                                        .zIndex(1)
                                        .allowsHitTesting(false)
                                    // Corner guide brackets
                                    cornerBracket(rect: viewRect, length: max(10, viewRect.width * 0.03), thickness: 2)
                                        .stroke(Color.white, lineWidth: 2)
                                        .shadow(radius: 1)
                                        .zIndex(1)
                                        .allowsHitTesting(false)
                                    cornerBracket(rect: viewRect, length: max(10, viewRect.width * 0.03), thickness: 1)
                                        .stroke(Color.red, lineWidth: 1)
                                        .zIndex(1)
                                        .allowsHitTesting(false)
                                    Path { $0.addRect(viewRect) }
                                        .fill(Color.red.opacity(0.12))
                                        .allowsHitTesting(false)
                                        .zIndex(1)
                                    
                                    // LEFT (Xmin) — width only
                                    handle(at: CGPoint(x: viewRect.minX, y: viewRect.midY))
                                        .gesture(
                                            DragGesture(minimumDistance: 0)
                                                .onChanged { g in
                                                    if dragStartRect == nil { dragStartRect = cropRect }
                                                    guard let start = dragStartRect else { return }
                                                    let dx = g.translation.width / scale
                                                    let newXmin = max(0, min(start.minX + dx, start.maxX - minSide))
                                                    var r = start
                                                    r.origin.x = newXmin
                                                    r.size.width = max(minSide, start.maxX - newXmin)
                                                    cropRect = r
                                                }
                                                .onEnded { _ in dragStartRect = nil }
                                        )
                                        .zIndex(3)
                                    
                                    // RIGHT (Xmax) — width only
                                    handle(at: CGPoint(x: viewRect.maxX, y: viewRect.midY))
                                        .gesture(
                                            DragGesture(minimumDistance: 0)
                                                .onChanged { g in
                                                    if dragStartRect == nil { dragStartRect = cropRect }
                                                    guard let start = dragStartRect else { return }
                                                    let dx = g.translation.width / scale
                                                    let newXmax = min(imageSize.width, max(start.minX + minSide, start.maxX + dx))
                                                    var r = start
                                                    r.size.width = newXmax - start.minX
                                                    cropRect = r
                                                }
                                                .onEnded { _ in dragStartRect = nil }
                                        )
                                        .zIndex(3)
                                    
                                    // TOP (Ymin) — height only
                                    handle(at: CGPoint(x: viewRect.midX, y: viewRect.minY))
                                        .gesture(
                                            DragGesture(minimumDistance: 0)
                                                .onChanged { g in
                                                    if dragStartRect == nil { dragStartRect = cropRect }
                                                    guard let start = dragStartRect else { return }
                                                    let dy = g.translation.height / scale
                                                    let newYmin = max(0, min(start.minY + dy, start.maxY - minSide))
                                                    var r = start
                                                    r.origin.y = newYmin
                                                    r.size.height = max(minSide, start.maxY - newYmin)
                                                    cropRect = r
                                                }
                                                .onEnded { _ in dragStartRect = nil }
                                        )
                                        .zIndex(3)
                                    
                                    // BOTTOM (Ymax) — height only
                                    handle(at: CGPoint(x: viewRect.midX, y: viewRect.maxY))
                                        .gesture(
                                            DragGesture(minimumDistance: 0)
                                                .onChanged { g in
                                                    if dragStartRect == nil { dragStartRect = cropRect }
                                                    guard let start = dragStartRect else { return }
                                                    let dy = g.translation.height / scale
                                                    let newYmax = min(imageSize.height, max(start.minY + minSide, start.maxY + dy))
                                                    var r = start
                                                    r.size.height = newYmax - start.minY
                                                    cropRect = r
                                                }
                                                .onEnded { _ in dragStartRect = nil }
                                        )
                                        .zIndex(3)
                                    
                                }
                                .onAppear {
                                    if cropRect == .zero {
                                        // initialize to a centered box if segment hasn't run yet
                                        let w = imageSize.width * 0.7
                                        let h = imageSize.height * 0.7
                                        let x = (imageSize.width - w) / 2
                                        let y = (imageSize.height - h) / 2
                                        cropRect = CGRect(x: x, y: y, width: w, height: h)
                                    }
                                }
                            }                        }
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
            let type: UTType = .jpeg
            if let url = pickSaveURL(type: type) {
                try saveImage(cropped, to: url, type: type, quality: 0.95)
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
    // Visible, easy-to-hit resize handle
    @ViewBuilder
    private func handle(at p: CGPoint) -> some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.85))
            Circle().stroke(Color.white, lineWidth: 2)
            Circle().stroke(Color.red, lineWidth: 1)
        }
        .frame(width: handleSize * 1.5, height: handleSize * 1.5)
        .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 0)
        .position(p)
        .contentShape(Rectangle())
        .allowsHitTesting(true)
        .zIndex(10)
    }
    
    // Draw small "L" brackets at each corner of the rect
    private func cornerBracket(rect: CGRect, length: CGFloat, thickness: CGFloat) -> Path {
        var path = Path()
        let x0 = rect.minX, y0 = rect.minY
        let x1 = rect.maxX, y1 = rect.maxY
        // TL
        path.move(to: CGPoint(x: x0, y: y0 + length))
        path.addLine(to: CGPoint(x: x0, y: y0))
        path.addLine(to: CGPoint(x: x0 + length, y: y0))
        // TR
        path.move(to: CGPoint(x: x1 - length, y: y0))
        path.addLine(to: CGPoint(x: x1, y: y0))
        path.addLine(to: CGPoint(x: x1, y: y0 + length))
        // BL
        path.move(to: CGPoint(x: x0, y: y1 - length))
        path.addLine(to: CGPoint(x: x0, y: y1))
        path.addLine(to: CGPoint(x: x0 + length, y: y1))
        // BR
        path.move(to: CGPoint(x: x1 - length, y: y1))
        path.addLine(to: CGPoint(x: x1, y: y1))
        path.addLine(to: CGPoint(x: x1, y: y1 - length))
        return path
    }
    
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
