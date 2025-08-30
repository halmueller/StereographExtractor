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

    var body: some View {
        ScrollView {
            Group {
                Text("Yellow (HSV)").font(.headline)
                slider("H low", value: $params.hYellowLow, 0, 1)
                slider("H high", value: $params.hYellowHigh, 0, 1)
                slider("S min", value: $params.sYellowMin, 0, 1)
                slider("V min", value: $params.vYellowMin, 0, 1)
            }.padding(.bottom, 8)

            Group {
                Text("Paper (HSV)").font(.headline)
                slider("H low", value: $params.hPaperLow, 0, 1)
                slider("H high", value: $params.hPaperHigh, 0, 1)
                slider("S min", value: $params.sPaperMin, 0, 1)
                slider("V min", value: $params.vPaperMin, 0, 1)
            }.padding(.bottom, 8)

            Group {
                Text("Edge Scan").font(.headline)
                slider("maxScanFrac", value: $params.maxScanFrac, 0.05, 0.50, step: 0.01)
                slider("startThresh", value: $params.startThresh, 0.2, 0.95, step: 0.01)
                slider("endThresh", value: $params.endThresh, 0.0, 0.8, step: 0.01)
            }.padding(.bottom, 8)

            Group {
                Text("Padding / Safety").font(.headline)
                slider("padFracX", value: $params.padFracX, 0.0, 0.02, step: 0.001)
                slider("padFracY", value: $params.padFracY, 0.0, 0.02, step: 0.001)
                slider("minKeepFrac", value: $params.minKeepFrac, 0.1, 0.6, step: 0.01)
                slider("maxTotalCropFrac", value: $params.maxTotalCropFrac, 0.2, 0.9, step: 0.01)
                slider("fallbackLeftFrac", value: $params.fallbackLeftFrac, 0.0, 0.2, step: 0.005)
                slider("fallbackOtherFrac", value: $params.fallbackOtherFrac, 0.0, 0.1, step: 0.005)
            }.padding(.bottom, 8)

            Group {
                Text("Post Bias (optional)").font(.headline)
                slider("biasLeft", value: $params.postBiasLeftFrac, -0.03, 0.03, step: 0.001)
                slider("biasRight", value: $params.postBiasRightFrac, -0.03, 0.03, step: 0.001)
                slider("biasTop", value: $params.postBiasTopFrac, -0.03, 0.03, step: 0.001)
                slider("biasBottom", value: $params.postBiasBottomFrac, -0.03, 0.03, step: 0.001)
            }

            Button {
                onResegment()
            } label: {
                Label("Re-segment", systemImage: "wand.and.stars")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 12)
        }
        .padding()
    }

    @ViewBuilder
    private func slider(_ label: String, value: Binding<Float>, _ min: Float, _ max: Float, step: Float = 0.005) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: "%.3f", value.wrappedValue)).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value.doubleBinding, in: Double(min)...Double(max), step: Double(step))
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
