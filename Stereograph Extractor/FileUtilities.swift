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

import AppKit
import UniformTypeIdentifiers

extension UTType {
    static let jpeg2000 = UTType(importedAs: "public.jpeg-2000")
}

func pickSaveURL(suggestingFrom inputURL: URL?, type: UTType?) -> URL? {
    let panel = NSSavePanel()
    // Choose a default content type
    let chosenType: UTType = type ?? {
        switch inputURL?.pathExtension.lowercased() {
        case "jp2", "j2k": return .jpeg2000
        case "png":        return .png
        case "tif", "tiff":return .tiff
        case "heic":       return .heic
        default:           return .jpeg
        }
    }()

    panel.allowedContentTypes = [chosenType]

    // Suggest "<input>_cropped.<ext>"
    if let src = inputURL {
        let base = src.deletingPathExtension().lastPathComponent
        let ext  = (chosenType.preferredFilenameExtension) ?? src.pathExtension
        panel.nameFieldStringValue = "\(base)_cropped.\(ext)"
    } else {
        panel.nameFieldStringValue = "image_cropped." + (chosenType.preferredFilenameExtension ?? "jpg")
    }

    return panel.runModal() == .OK ? panel.url : nil
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
