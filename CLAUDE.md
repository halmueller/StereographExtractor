# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build

Open and build in Xcode:
```
open "Stereograph Extractor.xcodeproj"
```

Command-line build (macOS target):
```
xcodebuild -project "Stereograph Extractor.xcodeproj" -scheme "Stereograph Extractor" -configuration Debug build
```

There are no automated tests in use — the test targets are empty placeholders.

## Architecture

This is a macOS-only SwiftUI app that automatically crops yellow collar and paper borders from stereograph card scans. The segmentation algorithm is pure Swift using CoreGraphics (no external dependencies).

### File roles

- **`CoreParameters.swift`** — All segmentation logic and types: `SegmentParams` (tunable HSV thresholds and scan parameters), `buildMask()` (per-pixel HSV classification into yellow/paper mask), `findEdges()` (inward scan from each edge using adaptive thresholds), `segment()` (full pipeline returning `SegmentResult` with `bbox`, `mask`, `debug`, `fallbackUsed`), plus `makeDebugOverlay()`, `applyCrop()`, `saveImage()`.

- **`ContentView.swift`** — Main two-panel layout: left panel is the image editor (`CropAdjustView`), right panel is `SegControlsView` + BBox Inspector. Owns all app state (`original`, `cropRect`, `params`, batch state). Handles keyboard nudge/resize (arrow keys = 1px, Shift = 10px; Option+arrow = resize), file open/save, batch folder processing, and CSV logging of crop boundaries to `training_bboxes.csv`.

- **`CropAdjustView.swift`** — Interactive crop-rect editor drawn over the image. Four mid-edge drag handles (left/right/top/bottom). `cropRect` binding is always in **image pixel coordinates** (CGImage origin = top-left).

- **`SegControlsView.swift`** — Scrollable sliders panel exposing all `SegmentParams` fields. Uses a `bind(_ kp:)` helper to bridge `Float` fields to `Slider`'s `Double`. Has a "Reset yellow to recommended" button.

- **`FileUtilities.swift`** — `cgImageFromURL()`, `pickSaveURL()`, `pickImageURL()`, `UTType.jpeg2000` extension.

- **`SingleFile.swift`** — Leftover iOS/UIKit prototype; **not included in the macOS build target**. Ignore it.

### Segmentation pipeline

1. Draw input `CGImage` into an RGBA byte buffer.
2. Classify each pixel as yellow collar (narrow HSV hue band + S/V minimums) or paper (low saturation + high brightness). Result is a flat `[UInt8]` mask.
3. Scan inward from each edge up to `maxScanFrac` of the image. At each column/row, count the fraction of masked pixels. Compare against an adaptive threshold that interpolates from `startThresh` to `endThresh` as we scan deeper.
4. Apply `padFracX`/`padFracY` inward padding and optional `postBiasX`/`postBiasY`.
5. Safety check: if the detected box crops away more than `maxTotalCropFrac` or leaves less than `minKeepFrac`, fall back to fixed fractions (`fallbackLeftFrac`/`fallbackOtherFrac`) and set `fallbackUsed = true`.

### Batch processing

"Open Folder…" loads all supported image files alphabetically, skipping files whose base name ends in `_cropped`. After each "Apply Crop & Save" (Return key), the app auto-advances to the next image. Crop boundaries are appended to `training_bboxes.csv` beside the saved file.

### Coordinate system

`cropRect` throughout the app is in **image pixel coordinates** with origin at the top-left corner, matching `CGImage`'s native coordinate space. `CropAdjustView` applies a scale factor to convert to view coordinates for display.
