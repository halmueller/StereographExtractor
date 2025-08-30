//
//  FileUtilities.swift
//  Stereograph Extractor
//
//  Created by Hal Mueller on 8/30/25.
//

import AppKit
import UniformTypeIdentifiers
import ImageIO
import CoreGraphics
import Foundation

extension UTType {
    /// JPEG 2000 (JP2) identifier recognized by CoreGraphics / ImageIO
    static let jpeg2000 = UTType(importedAs: "public.jpeg-2000")
}

// Open panel
func pickImageURL() -> URL? {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [
        .jpeg,
        .png,
        .tiff,
        .heic,
        .jpeg2000    // add JP2 support
    ]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    return panel.runModal() == .OK ? panel.url : nil
}

// Save panel
func pickSaveURL(defaultName: String = "stereo_cropped.jp2", type: UTType = .jpeg2000) -> URL? {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [type]
    panel.nameFieldStringValue = defaultName
    return panel.runModal() == .OK ? panel.url : nil
}

// Load CGImage from URL
func cgImageFromURL(_ url: URL) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}
