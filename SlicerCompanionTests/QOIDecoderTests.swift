//
//  QOIDecoderTests.swift
//  SlicerCompanionTests
//
//  Unit tests for the QOI image decoder.
//

import CoreGraphics
import Foundation
import XCTest

@testable import SlicerCompanionLib

final class QOIDecoderTests: XCTestCase {

    func testDecode_InvalidMagic() {
        // Invalid magic number
        var invalidData = Data(count: 20)
        invalidData[0] = 0x00  // Not 'q'

        XCTAssertNil(QOIDecoder.decode(from: invalidData))
    }

    func testDecode_TooSmallData() {
        let tooSmall = Data([0x71, 0x6F, 0x69, 0x66])  // Just the magic "qoif"

        XCTAssertNil(QOIDecoder.decode(from: tooSmall))
    }

    func testDecode_EmptyData() {
        let emptyData = Data()

        XCTAssertNil(QOIDecoder.decode(from: emptyData))
    }

    func testDecode_ZeroDimensions() {
        // QOI header with zero width
        var qoiData = Data()
        qoiData.append(contentsOf: [0x71, 0x6F, 0x69, 0x66])  // Magic "qoif"
        qoiData.append(contentsOf: [0x00, 0x00, 0x00, 0x00])  // Width = 0
        qoiData.append(contentsOf: [0x00, 0x00, 0x00, 0x01])  // Height = 1
        qoiData.append(contentsOf: [0x04, 0x00])              // Channels, colorspace
        qoiData.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01])  // End marker

        XCTAssertNil(QOIDecoder.decode(from: qoiData))
    }

    func testDecode_NegativeLikeDimensions() {
        // QOI header with very large (negative-like when interpreted as signed) dimensions
        var qoiData = Data()
        qoiData.append(contentsOf: [0x71, 0x6F, 0x69, 0x66])  // Magic "qoif"
        qoiData.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF])  // Width = max
        qoiData.append(contentsOf: [0x00, 0x00, 0x00, 0x01])  // Height = 1
        qoiData.append(contentsOf: [0x04, 0x00])              // Channels, colorspace

        // Should reject due to dimension limits
        XCTAssertNil(QOIDecoder.decode(from: qoiData))
    }

    func testDecode_ValidHeaderButNoData() {
        // Valid header but missing pixel data
        var qoiData = Data()
        qoiData.append(contentsOf: [0x71, 0x6F, 0x69, 0x66])  // Magic "qoif"
        qoiData.append(contentsOf: [0x00, 0x00, 0x00, 0x01])  // Width = 1
        qoiData.append(contentsOf: [0x00, 0x00, 0x00, 0x01])  // Height = 1
        qoiData.append(contentsOf: [0x04, 0x00])              // Channels = 4, colorspace = 0
        // No pixel data or end marker - just pad with zeros
        qoiData.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])

        // The decoder should still produce something (even if corrupted) for valid header
        let image = QOIDecoder.decode(from: qoiData)
        // Either it fails gracefully or produces a 1x1 image
        if let image = image {
            XCTAssertEqual(image.width, 1)
            XCTAssertEqual(image.height, 1)
        }
    }
}
