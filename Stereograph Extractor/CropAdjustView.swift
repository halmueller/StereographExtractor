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

                Path { $0.addRect(viewRect) }
                    .fill(Color.red.opacity(0.12))
                    .allowsHitTesting(false)   // don’t block handles
                    .zIndex(1)

                // Corner handles (above everything)
                cornerHandle(at: CGPoint(x: viewRect.minX, y: viewRect.minY))
                    .highPriorityGesture(resizeTL(scale: scale, imageSize: imgSize))
                    .zIndex(3)
                cornerHandle(at: CGPoint(x: viewRect.maxX, y: viewRect.minY))
                    .highPriorityGesture(resizeTR(scale: scale, imageSize: imgSize))
                    .zIndex(3)
                cornerHandle(at: CGPoint(x: viewRect.minX, y: viewRect.maxY))
                    .highPriorityGesture(resizeBL(scale: scale, imageSize: imgSize))
                    .zIndex(3)
                cornerHandle(at: CGPoint(x: viewRect.maxX, y: viewRect.maxY))
                    .highPriorityGesture(resizeBR(scale: scale, imageSize: imgSize))
                    .zIndex(3)

                // Drag whole rect (below handles, above fill)
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .frame(width: viewRect.width, height: viewRect.height)
                    .position(x: viewRect.midX, y: viewRect.midY)
                    .gesture(dragWhole(scale: scale, imageSize: imgSize))
                    .zIndex(2)
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

    // MARK: - Gestures

    private func dragWhole(scale: CGFloat, imageSize: CGSize) -> some Gesture {
        DragGesture().onChanged { g in
            var r = cropRect
            let dx = g.translation.width  / scale
            let dy = g.translation.height / scale
            r.origin.x = max(0, min(r.origin.x + dx, imageSize.width  - r.width))
            r.origin.y = max(0, min(r.origin.y + dy, imageSize.height - r.height))
            cropRect = r
        }
    }

    private func resizeTL(scale: CGFloat, imageSize: CGSize) -> some Gesture {
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
    }

    private func resizeTR(scale: CGFloat, imageSize: CGSize) -> some Gesture {
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
    }

    private func resizeBL(scale: CGFloat, imageSize: CGSize) -> some Gesture {
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
    }

    private func resizeBR(scale: CGFloat, imageSize: CGSize) -> some Gesture {
        DragGesture().onChanged { g in
            var r = cropRect
            let dx = g.translation.width  / scale
            let dy = g.translation.height / scale
            r.size.width  = max(minSide, min(imageSize.width  - r.origin.x, r.size.width + dx))
            r.size.height = max(minSide, min(imageSize.height - r.origin.y, r.size.height + dy))
            cropRect = r
        }
    }
}
