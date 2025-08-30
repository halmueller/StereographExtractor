//
//  ContentView.swift
//  Stereograph Extractor
//
//  Created by Hal Mueller on 8/30/25.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @State private var original: CGImage?
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
                                    // Corner guide brackets
                                    cornerBracket(rect: viewRect, length: max(10, viewRect.width * 0.03), thickness: 2)
                                        .stroke(Color.white, lineWidth: 2)
                                        .shadow(radius: 1)
                                        .zIndex(1)
                                    cornerBracket(rect: viewRect, length: max(10, viewRect.width * 0.03), thickness: 1)
                                        .stroke(Color.red, lineWidth: 1)
                                        .zIndex(1)
                                    Path { $0.addRect(viewRect) }
                                        .fill(Color.red.opacity(0.12))
                                        .allowsHitTesting(false)
                                        .zIndex(1)
                                    
                                    // Drag the whole rect
                                    Rectangle()
                                        .fill(Color.clear)
                                        .contentShape(Rectangle())
                                        .frame(width: viewRect.width, height: viewRect.height)
                                        .position(x: viewRect.midX, y: viewRect.midY)
                                        .gesture(
                                            DragGesture().onChanged { g in
                                                var r = cropRect
                                                let dx = g.translation.width  / scale
                                                let dy = g.translation.height / scale
                                                r.origin.x = max(0, min(r.origin.x + dx, imageSize.width  - r.width))
                                                r.origin.y = max(0, min(r.origin.y + dy, imageSize.height - r.height))
                                                cropRect = r
                                            }
                                        )
                                        .zIndex(2)
                                    
                                    // Corner handles (top-left, top-right, bottom-left, bottom-right)
                                    handle(at: CGPoint(x: viewRect.minX, y: viewRect.minY))
                                        .highPriorityGesture(
                                            DragGesture().onChanged { g in
                                                var r = cropRect
                                                let dx = g.translation.width  / scale
                                                let dy = g.translation.height / scale
                                                let maxX = r.maxX, maxY = r.maxY
                                                r.origin.x = min(max(0, r.origin.x + dx), maxX - minSide)
                                                r.origin.y = min(max(0, r.origin.y + dy), maxY - minSide)
                                                r.size.width  = max(minSide, maxX - r.origin.x)
                                                r.size.height = max(minSide, maxY - r.origin.y)
                                                cropRect = r
                                            }
                                        )
                                        .zIndex(3)
                                    
                                    handle(at: CGPoint(x: viewRect.maxX, y: viewRect.minY))
                                        .highPriorityGesture(
                                            DragGesture().onChanged { g in
                                                var r = cropRect
                                                let dx = g.translation.width  / scale
                                                let dy = g.translation.height / scale
                                                let minX = r.minX
                                                r.size.width  = max(minSide, min(imageSize.width - minX, r.size.width + dx))
                                                r.origin.y    = min(max(0, r.origin.y + dy), r.maxY - minSide)
                                                r.size.height = max(minSide, r.maxY - r.origin.y)
                                                cropRect = r
                                            }
                                        )
                                        .zIndex(3)
                                    
                                    handle(at: CGPoint(x: viewRect.minX, y: viewRect.maxY))
                                        .highPriorityGesture(
                                            DragGesture().onChanged { g in
                                                var r = cropRect
                                                let dx = g.translation.width  / scale
                                                let dy = g.translation.height / scale
                                                let maxX = r.maxX
                                                r.origin.x = min(max(0, r.origin.x + dx), maxX - minSide)
                                                r.size.width  = max(minSide, maxX - r.origin.x)
                                                r.size.height = max(minSide, min(imageSize.height - r.origin.y, r.size.height + dy))
                                                cropRect = r
                                            }
                                        )
                                        .zIndex(3)
                                    
                                    handle(at: CGPoint(x: viewRect.maxX, y: viewRect.maxY))
                                        .highPriorityGesture(
                                            DragGesture().onChanged { g in
                                                var r = cropRect
                                                let dx = g.translation.width  / scale
                                                let dy = g.translation.height / scale
                                                r.size.width  = max(minSide, min(imageSize.width  - r.origin.x, r.size.width + dx))
                                                r.size.height = max(minSide, min(imageSize.height - r.origin.y, r.size.height + dy))
                                                cropRect = r
                                            }
                                        )
                                        .zIndex(3)
                                    
                                    // Mid-edge handles (left, right, top, bottom)
                                    handle(at: CGPoint(x: viewRect.minX, y: viewRect.midY))
                                        .highPriorityGesture(
                                            DragGesture().onChanged { g in
                                                var r = cropRect
                                                let dx = g.translation.width / scale
                                                let newX = min(max(0, r.origin.x + dx), r.maxX - minSide)
                                                let delta = r.origin.x - newX
                                                r.origin.x = newX
                                                r.size.width = max(minSide, r.size.width + delta)
                                                cropRect = r
                                            }
                                        )
                                        .zIndex(3)

                                    handle(at: CGPoint(x: viewRect.maxX, y: viewRect.midY))
                                        .highPriorityGesture(
                                            DragGesture().onChanged { g in
                                                var r = cropRect
                                                let dx = g.translation.width / scale
                                                r.size.width = max(minSide, r.size.width + dx)
                                                r.size.width = min(r.size.width, imageSize.width - r.origin.x)
                                                cropRect = r
                                            }
                                        )
                                        .zIndex(3)

                                    handle(at: CGPoint(x: viewRect.midX, y: viewRect.minY))
                                        .highPriorityGesture(
                                            DragGesture().onChanged { g in
                                                var r = cropRect
                                                let dy = g.translation.height / scale
                                                let newY = min(max(0, r.origin.y + dy), r.maxY - minSide)
                                                let delta = r.origin.y - newY
                                                r.origin.y = newY
                                                r.size.height = max(minSide, r.size.height + delta)
                                                cropRect = r
                                            }
                                        )
                                        .zIndex(3)

                                    handle(at: CGPoint(x: viewRect.midX, y: viewRect.maxY))
                                        .highPriorityGesture(
                                            DragGesture().onChanged { g in
                                                var r = cropRect
                                                let dy = g.translation.height / scale
                                                r.size.height = max(minSide, r.size.height + dy)
                                                r.size.height = min(r.size.height, imageSize.height - r.origin.y)
                                                cropRect = r
                                            }
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
                            HStack {
                                Text("x").frame(width: 16, alignment: .trailing)
                                TextField("x", value: Binding(
                                    get: { Double(cropRect.origin.x) },
                                    set: { v in
                                        let w = Double(cropRect.size.width)
                                        let imgW = Double(original?.width ?? 0)
                                        let clamped = max(0, min(v, max(0, imgW - w)))
                                        cropRect.origin.x = CGFloat(clamped)
                                    }
                                ), formatter: numFmt)
                                Stepper("") {
                                    nudge(dx: 1, dy: 0)
                                } onDecrement: {
                                    nudge(dx: -1, dy: 0)
                                }.labelsHidden()
                            }
                            HStack {
                                Text("y").frame(width: 16, alignment: .trailing)
                                TextField("y", value: Binding(
                                    get: { Double(cropRect.origin.y) },
                                    set: { v in
                                        let h = Double(cropRect.size.height)
                                        let imgH = Double(original?.height ?? 0)
                                        let clamped = max(0, min(v, max(0, imgH - h)))
                                        cropRect.origin.y = CGFloat(clamped)
                                    }
                                ), formatter: numFmt)
                                Stepper("") {
                                    nudge(dx: 0, dy: 1)
                                } onDecrement: {
                                    nudge(dx: 0, dy: -1)
                                }.labelsHidden()
                            }
                            HStack {
                                Text("w").frame(width: 16, alignment: .trailing)
                                TextField("w", value: Binding(
                                    get: { Double(cropRect.size.width) },
                                    set: { v in
                                        let imgW = Double(original?.width ?? 0)
                                        let clamped = max(20, min(v, imgW - Double(cropRect.origin.x)))
                                        cropRect.size.width = CGFloat(clamped)
                                    }
                                ), formatter: numFmt)
                                Stepper("") {
                                    resize(dw: 1, dh: 0)
                                } onDecrement: {
                                    resize(dw: -1, dh: 0)
                                }.labelsHidden()
                            }
                            HStack {
                                Text("h").frame(width: 16, alignment: .trailing)
                                TextField("h", value: Binding(
                                    get: { Double(cropRect.size.height) },
                                    set: { v in
                                        let imgH = Double(original?.height ?? 0)
                                        let clamped = max(20, min(v, imgH - Double(cropRect.origin.y)))
                                        cropRect.size.height = CGFloat(clamped)
                                    }
                                ), formatter: numFmt)
                                Stepper("") {
                                    resize(dw: 0, dh: 1)
                                } onDecrement: {
                                    resize(dw: 0, dh: -1)
                                }.labelsHidden()
                            }
                            Text("Arrows = move 1px  •  ⇧+Arrows = 10px  •  ⌥+Arrows = resize 1px  •  ⌥⇧+Arrows = 10px")
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
}

#Preview {
    ContentView()
}
