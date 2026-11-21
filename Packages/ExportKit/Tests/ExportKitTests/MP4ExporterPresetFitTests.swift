import CoreGraphics
import Foundation
import SharedKit
import Testing

@testable import ExportKit

/// Audit E21 + E24, 21.11.
@Suite("MP4Exporter preset fit")
struct MP4ExporterPresetFitTests {
    @Test("Portrait larger than the preset box is re-encoded")
    func portraitIsScaledDown() {
        // Width alone (1440 <= 1920) passed the old check although 2560 > 1920.
        #expect(!MP4Exporter.fitsPreset(CGSize(width: 1440, height: 2560), quality: .social))
        #expect(!MP4Exporter.fitsPreset(CGSize(width: 1080, height: 1920), quality: .web))
    }

    @Test("Sources inside the box pass through in either orientation")
    func fittingSourcesPassThrough() {
        #expect(MP4Exporter.fitsPreset(CGSize(width: 1920, height: 1080), quality: .social))
        #expect(MP4Exporter.fitsPreset(CGSize(width: 1080, height: 1920), quality: .social))
        #expect(MP4Exporter.fitsPreset(CGSize(width: 1280, height: 720), quality: .web))
    }

    @Test("Landscape wider than the box is re-encoded")
    func wideLandscapeIsScaledDown() {
        #expect(!MP4Exporter.fitsPreset(CGSize(width: 2560, height: 1440), quality: .social))
    }

    @Test("Export errors have readable descriptions")
    func exportErrorDescription() {
        let error: Error = ExportError.gifCreationFailed
        #expect(error.localizedDescription == "The GIF could not be created.")
    }
}
