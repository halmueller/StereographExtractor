//
//  ContentView.swift
//  Stereograph Extractor
//
//  Created by Hal Mueller on 8/30/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var original: CGImage?
    @State private var cropRect: CGRect = .zero
    @State private var params = SegmentParams()
    @State private var showMask = false
    @State private var maskCG: CGImage?
    @State private var debugCG: CGImage?
    @State private var fallbackUsed = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ZStack {
                        if let cg = original {
                            if showMask, let maskCG {
                                Image(nsImage: NSImage(cgImage: maskCG, size: .init(width: maskCG.width, height: maskCG.height)))
                                    .resizable().interpolation(.high).scaledToFit()
                            } else if let debug = debugCG, !showMask {
                                Image(nsImage: NSImage(cgImage: debug, size: .init(width: debug.width, height: debug.height)))
                                    .resizable().interpolation(.high).scaledToFit()
                            } else {
                                CropAdjustView(original: cg, cropRect: $cropRect)
                            }
                        } else {
                            Text("Open an image (⌘O)").foregroundStyle(.secondary)
                        }
                    }
                    .frame(minWidth: 500, minHeight: 400)
                    .background(Color.black.opacity(0.04))

                    Divider()

                    SegControlsView(params: $params) {
                        runSegmentation()
                    }
                    .frame(width: 340)
                }

                Divider()

                HStack {
                    Button {
                        if let url = pickImageURL(), let cg = cgImageFromURL(url) {
                            original = cg
                            runSegmentation()
                        }
                    } label: {
                        Label("Open…", systemImage: "folder")
                    }
                    .keyboardShortcut("o", modifiers: .command)

                    Toggle("Show mask/overlay", isOn: $showMask)
                        .toggleStyle(.switch)

                    Spacer()
                    Text(fallbackUsed ? "Fallback used" : "Detection used")
                        .foregroundStyle(fallbackUsed ? .orange : .green)
                        .font(.callout)

                    Button {
                        runSegmentation()
                    } label: {
                        Label("Re-segment", systemImage: "wand.and.stars")
                    }

                    Button {
                        applyAndSave()
                    } label: {
                        Label("Apply Crop & Save…", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(10)
            }
            .navigationTitle("Stereo Border Cropper (macOS)")
        }
        .frame(minWidth: 980, minHeight: 640)
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
}
#Preview {
    ContentView()
}
