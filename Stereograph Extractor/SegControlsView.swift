//
//  SegControlsView.swift
//  Stereograph Extractor
//
//  Created by Hal Mueller on 8/30/25.
//

import SwiftUI

struct SegControlsView: View {
    @Binding var params: SegmentParams
    var onResegment: () -> Void

    // Bridge Float fields to Slider(Double)
    private func bind(_ kp: WritableKeyPath<SegmentParams, Float>) -> Binding<Double> {
        Binding<Double>(
            get: { Double(params[keyPath: kp]) },
            set: { params[keyPath: kp] = Float($0) }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // MARK: Yellow (HSV)
                Text("Yellow (HSV)").font(.headline)
                    .help("Yellowed collar detection uses a narrow hue band plus minimum saturation and brightness.")

                LabeledSlider("H low", value: bind(\.hYellowLow), range: 0...1, step: 0.001)
                    .help("Lower bound of hue band for yellow collar detection.")
                LabeledSlider("H high", value: bind(\.hYellowHigh), range: 0...1, step: 0.001)
                    .help("Upper bound of hue band for yellow collar detection.")
                LabeledSlider("S min", value: bind(\.sYellowMin), range: 0...1, step: 0.001)
                    .help("Minimum saturation to count as yellow. Higher = stricter yellow.")
                LabeledSlider("V min", value: bind(\.vYellowMin), range: 0...1, step: 0.001)
                    .help("Minimum brightness to count as yellow. Higher = stricter.")

                HStack {
                    Button {
                        // Collar RGB(253,214,77) -> HSV ~ (0.13, 0.70, 0.99)
                        params.hYellowLow  = 0.11   // ~40°
                        params.hYellowHigh = 0.15   // ~54°
                        params.sYellowMin  = 0.55
                        params.vYellowMin  = 0.85
                        onResegment()
                    } label: {
                        Label("Reset yellow to recommended", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)

                    Spacer()
                }

                Divider().padding(.vertical, 6)

                // MARK: Paper (HSV)
                Text("Paper (HSV)").font(.headline)
                    .help("Paper = low saturation and bright value. S slider is a MAX threshold: S ≤ S max; V slider is a MIN threshold.")

                LabeledSlider("S max", value: bind(\.sPaperMin), range: 0...1, step: 0.001)
                    .help("Maximum saturation for paper (paper is low-sat).")
                LabeledSlider("V min", value: bind(\.vPaperMin), range: 0...1, step: 0.001)
                    .help("Minimum brightness for paper (paper is bright).")

                Divider().padding(.vertical, 6)

                // MARK: Edge Scan
                Text("Edge Scan").font(.headline)
                    .help("Scan inward from each edge to find where collar/paper stops and content begins.")

                LabeledSlider("Max scan", value: bind(\.maxScanFrac), range: 0...1, step: 0.001)
                    .help("Fraction of the image scanned inward from edges. Larger = detect wider collars; smaller = faster.")
                LabeledSlider("Start threshold", value: bind(\.startThresh), range: 0...1, step: 0.001)
                    .help("Where we begin treating pixels as foreground. Lower = more aggressive crop; higher = conservative.")
                LabeledSlider("End threshold", value: bind(\.endThresh), range: 0...1, step: 0.001)
                    .help("Where we stop treating pixels as background. Lower = tighter crop; higher = looser.")

                Divider().padding(.vertical, 6)

                // MARK: Pads
                Text("Pads").font(.headline)
                    .help("Add breathing room after detection so you don’t clip content.")

                LabeledSlider("Pad X", value: bind(\.padFracX), range: 0...0.1, step: 0.0005)
                    .help("Horizontal padding (fraction of width). Prevents cutting too close to the stereo pair.")
                LabeledSlider("Pad Y", value: bind(\.padFracY), range: 0...0.1, step: 0.0005)
                    .help("Vertical padding (fraction of height). Adds head/foot room.")

                Divider().padding(.vertical, 6)

                // MARK: Safety / Fallback
                Text("Safety / Fallback").font(.headline)
                    .help("Bounds and defaults to avoid extreme crops or detection failures.")

                LabeledSlider("Min keep", value: bind(\.minKeepFrac), range: 0...1, step: 0.001)
                    .help("Minimum fraction of width/height preserved. Prevents the box from becoming too small.")
                LabeledSlider("Max crop", value: bind(\.maxTotalCropFrac), range: 0...1, step: 0.001)
                    .help("Maximum fraction of the image allowed to be cropped away.")
                LabeledSlider("Fallback left", value: bind(\.fallbackLeftFrac), range: 0...1, step: 0.001)
                    .help("Default left inset if detection fails.")
                LabeledSlider("Fallback other", value: bind(\.fallbackOtherFrac), range: 0...1, step: 0.001)
                    .help("Default right/top/bottom inset if detection fails.")

                Divider().padding(.vertical, 6)

                // MARK: Post-Bias
                Text("Post-Bias").font(.headline)
                    .help("Final shift applied after detection to correct systematic over/under cropping.")

                LabeledSlider("Bias X", value: bind(\.postBiasX), range: -0.1...0.1, step: 0.0005)
                    .help("Shift box horizontally after detection. Positive = tighter; negative = looser.")
                LabeledSlider("Bias Y", value: bind(\.postBiasY), range: -0.1...0.1, step: 0.0005)
                    .help("Shift box vertically after detection. Adjusts systematic over/under cropping.")

                Button {
                    onResegment()
                } label: {
                    Label("Re-segment", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 6)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }
}

/// Reusable labeled slider with a numeric readout (monospaced)
private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    init(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .frame(width: 120, alignment: .trailing)
            Slider(value: $value, in: range, step: step)
            Text(String(format: "%.3f", value))
                .font(.system(.caption, design: .monospaced))
                .frame(width: 60, alignment: .leading)
        }
    }
}


private extension Binding where Value == Float {
    var doubleBinding: Binding<Double> {
        Binding<Double>(
            get: { Double(wrappedValue) },
            set: { wrappedValue = Float($0) }
        )
    }
}
