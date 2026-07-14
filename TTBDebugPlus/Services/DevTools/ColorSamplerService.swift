//
//  ColorSamplerService.swift
//  TTBDebugPlus
//
//  Thin wrapper around NSColorSampler for screen color picking.
//

import AppKit
import Foundation

@MainActor
protocol ColorSamplerServing: AnyObject {
    func sampleScreenColor() async -> NSColor?
}

@MainActor
final class ColorSamplerService: ColorSamplerServing {
    func sampleScreenColor() async -> NSColor? {
        await withCheckedContinuation { continuation in
            let sampler = NSColorSampler()
            sampler.show { color in
                continuation.resume(returning: color)
            }
        }
    }
}
