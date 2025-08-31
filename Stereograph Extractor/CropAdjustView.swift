//
//  CropAdjustView.swift
//  Stereograph Extractor
//
//  Created by Hal Mueller on 8/30/25.
//

import SwiftUI

// Crop rectangle editor over an image (CGImage) using SwiftUI only.
struct CropAdjustView: View {
    let original: CGImage
    @Binding var cropRect: CGRect   // in image pixels
    @State private var dragStartRect: CGRect?

    // tweak as you like
    private let handleSize: CGFloat = 18
    private let minSide: CGFloat = 20

    var body: some View {
        GeometryReader { geo in
            let imgSize = CGSize(width: original.width, height: original.height)
            let scale = min(geo.size.width / imgSize.width, geo.size.height / imgSize.height)
            let drawSize = CGSize(width: imgSize.width * scale, height: imgSize.height * scale)
            let origin = CGPoint(x: (geo.size.width - drawSize.width)/2,
                                 y: (geo.size.height - drawSize.height)/2)

            let nsimg = NSImage(cgImage: original, size: .init(width: original.width, height: original.height))

            ZStack(alignment: .topLeading) {
                // Image
                Image(nsImage: nsimg)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: drawSize.width, height: drawSize.height)
                    .position(x: origin.x + drawSize.width/2, y: origin.y + drawSize.height/2)
                    .zIndex(0)
                    .allowsHitTesting(false)

                // Crop rect (image -> view coords)
                let viewRect = CGRect(
                    x: origin.x + cropRect.minX * scale,
                    y: origin.y + cropRect.minY * scale,
                    width: cropRect.width * scale,
                    height: cropRect.height * scale
                )

                // Stroke+fill (behind handles)
                Path { $0.addRect(viewRect) }
                    .stroke(Color.red, lineWidth: max(2, drawSize.width * 0.002))
                    .zIndex(1)
                    .allowsHitTesting(false)

                Path { $0.addRect(viewRect) }
                    .fill(Color.red.opacity(0.12))
                    .allowsHitTesting(false)   // don’t block handles
                    .zIndex(1)

                // Mid-edge handles (adjust one edge only)
                cornerHandle(at: CGPoint(x: viewRect.minX, y: viewRect.midY))
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

                cornerHandle(at: CGPoint(x: viewRect.maxX, y: viewRect.midY))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { g in
                                if dragStartRect == nil { dragStartRect = cropRect }
                                guard let start = dragStartRect else { return }
                                let dx = g.translation.width / scale
                                let newXmax = min(imgSize.width, max(start.minX + minSide, start.maxX + dx))
                                var r = start
                                r.size.width = newXmax - start.minX
                                cropRect = r
                            }
                            .onEnded { _ in dragStartRect = nil }
                    )
                    .zIndex(3)

                cornerHandle(at: CGPoint(x: viewRect.midX, y: viewRect.minY))
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

                cornerHandle(at: CGPoint(x: viewRect.midX, y: viewRect.maxY))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { g in
                                if dragStartRect == nil { dragStartRect = cropRect }
                                guard let start = dragStartRect else { return }
                                let dy = g.translation.height / scale
                                let newYmax = min(imgSize.height, max(start.minY + minSide, start.maxY + dy))
                                var r = start
                                r.size.height = newYmax - start.minY
                                cropRect = r
                            }
                            .onEnded { _ in dragStartRect = nil }
                    )
                    .zIndex(3)
            }
        }
    }

    // MARK: - Views

    @ViewBuilder
    private func cornerHandle(at p: CGPoint) -> some View {
        // high-contrast square handle with border & shadow
        Rectangle()
            .fill(Color.white)
            .overlay(Rectangle().stroke(Color.black.opacity(0.7), lineWidth: 1))
            .frame(width: handleSize, height: handleSize)
            .shadow(radius: 1, x: 0, y: 0)
            .position(p)
            .contentShape(Rectangle())  // ensure easy hit area
    }
}
