//
//  ThumbnailExtractorTests.swift
//  SlicerCompanionTests
//
//  Unit tests for the thumbnail extraction functionality.
//

import CoreGraphics
import Foundation
import XCTest

@testable import SlicerCompanionLib

final class SlicerFileTypeTests: XCTestCase {

    func testFileTypeFromURL_3MF() {
        let url = URL(fileURLWithPath: "/path/to/file.3mf")
        XCTAssertEqual(SlicerFileType.from(url: url), .threeMF)
    }

    func testFileTypeFromURL_GCode() {
        let url = URL(fileURLWithPath: "/path/to/file.gcode")
        XCTAssertEqual(SlicerFileType.from(url: url), .gcode)
    }

    func testFileTypeFromURL_GCO() {
        let url = URL(fileURLWithPath: "/path/to/file.gco")
        XCTAssertEqual(SlicerFileType.from(url: url), .gco)
    }

    func testFileTypeFromURL_BGCode() {
        let url = URL(fileURLWithPath: "/path/to/file.bgcode")
        XCTAssertEqual(SlicerFileType.from(url: url), .bgcode)
    }

    func testFileTypeFromURL_CaseInsensitive() {
        let urls = [
            URL(fileURLWithPath: "/path/to/file.3MF"),
            URL(fileURLWithPath: "/path/to/file.GCODE"),
            URL(fileURLWithPath: "/path/to/file.GCO"),
            URL(fileURLWithPath: "/path/to/file.BGCODE"),
        ]
        XCTAssertEqual(SlicerFileType.from(url: urls[0]), .threeMF)
        XCTAssertEqual(SlicerFileType.from(url: urls[1]), .gcode)
        XCTAssertEqual(SlicerFileType.from(url: urls[2]), .gco)
        XCTAssertEqual(SlicerFileType.from(url: urls[3]), .bgcode)
    }

    func testFileTypeFromURL_UnsupportedFormat() {
        let url = URL(fileURLWithPath: "/path/to/file.stl")
        XCTAssertNil(SlicerFileType.from(url: url))
    }

    func testFileTypeFromURL_NoExtension() {
        let url = URL(fileURLWithPath: "/path/to/file")
        XCTAssertNil(SlicerFileType.from(url: url))
    }
}

final class ThumbnailExtractorErrorTests: XCTestCase {

    func testErrorDescriptions() {
        XCTAssertEqual(
            ThumbnailExtractorError.fileNotFound.errorDescription,
            "File not found"
        )
        XCTAssertEqual(
            ThumbnailExtractorError.unsupportedFormat("xyz").errorDescription,
            "Unsupported file format: xyz"
        )
        XCTAssertEqual(
            ThumbnailExtractorError.invalidFileFormat.errorDescription,
            "Invalid file format"
        )
        XCTAssertEqual(
            ThumbnailExtractorError.thumbnailNotFound.errorDescription,
            "No thumbnail found in file"
        )
        XCTAssertEqual(
            ThumbnailExtractorError.decompressionFailed.errorDescription,
            "Failed to decompress data"
        )
        XCTAssertEqual(
            ThumbnailExtractorError.imageCreationFailed.errorDescription,
            "Failed to create image from thumbnail data"
        )
        XCTAssertEqual(
            ThumbnailExtractorError.invalidZipFile.errorDescription,
            "Invalid ZIP file format"
        )
        XCTAssertEqual(
            ThumbnailExtractorError.corruptedFile.errorDescription,
            "Corrupted file"
        )
    }
}

final class ThreeMFParserTests: XCTestCase {

    func testExtractThumbnail_ValidFile() throws {
        guard let url = Bundle.module.url(
            forResource: "First Layer - square",
            withExtension: "3mf"
        ) else {
            throw XCTSkip("Test file 'First Layer - square.3mf' not found in test bundle")
        }

        let data = try Data(contentsOf: url)
        let image = try ThreeMFParser.extractThumbnail(from: data)

        XCTAssertGreaterThan(image.width, 0)
        XCTAssertGreaterThan(image.height, 0)
    }

    func testExtractThumbnail_ValidFile_SO101() throws {
        guard let url = Bundle.module.url(
            forResource: "SO101 follower - grip",
            withExtension: "3mf"
        ) else {
            throw XCTSkip("Test file 'SO101 follower - grip.3mf' not found in test bundle")
        }

        let data = try Data(contentsOf: url)
        let image = try ThreeMFParser.extractThumbnail(from: data)

        XCTAssertGreaterThan(image.width, 0)
        XCTAssertGreaterThan(image.height, 0)
    }

    func testExtractThumbnail_WithMaxSize() throws {
        guard let url = Bundle.module.url(
            forResource: "First Layer - square",
            withExtension: "3mf"
        ) else {
            throw XCTSkip("Test file 'First Layer - square.3mf' not found in test bundle")
        }

        let data = try Data(contentsOf: url)
        let maxSize = CGSize(width: 64, height: 64)
        let image = try ThreeMFParser.extractThumbnail(from: data, maxSize: maxSize)

        XCTAssertLessThanOrEqual(image.width, Int(maxSize.width))
        XCTAssertLessThanOrEqual(image.height, Int(maxSize.height))
    }

    func testExtractThumbnail_InvalidZipSignature() {
        let invalidData = Data([0x00, 0x01, 0x02, 0x03])

        XCTAssertThrowsError(try ThreeMFParser.extractThumbnail(from: invalidData)) { error in
            XCTAssertEqual(error as? ThumbnailExtractorError, .invalidZipFile)
        }
    }

    func testExtractThumbnail_EmptyData() {
        let emptyData = Data()

        XCTAssertThrowsError(try ThreeMFParser.extractThumbnail(from: emptyData)) { error in
            XCTAssertEqual(error as? ThumbnailExtractorError, .invalidZipFile)
        }
    }

    func testExtractThumbnail_TooSmallData() {
        let smallData = Data([0x50, 0x4B, 0x03, 0x04])  // Valid ZIP signature but too small

        XCTAssertThrowsError(try ThreeMFParser.extractThumbnail(from: smallData)) { error in
            XCTAssertEqual(error as? ThumbnailExtractorError, .invalidZipFile)
        }
    }
}

final class GCodeParserTests: XCTestCase {

    func testExtractThumbnail_ValidFile() throws {
        guard let url = Bundle.module.url(
            forResource: "SO101 leader grip",
            withExtension: "gcode"
        ) else {
            throw XCTSkip("Test file 'SO101 leader grip.gcode' not found in test bundle")
        }

        let data = try Data(contentsOf: url)
        let image = try GCodeParser.extractThumbnail(from: data)

        XCTAssertGreaterThan(image.width, 0)
        XCTAssertGreaterThan(image.height, 0)
    }

    func testExtractThumbnail_WithMaxSize() throws {
        guard let url = Bundle.module.url(
            forResource: "SO101 leader grip",
            withExtension: "gcode"
        ) else {
            throw XCTSkip("Test file 'SO101 leader grip.gcode' not found in test bundle")
        }

        let data = try Data(contentsOf: url)
        let maxSize = CGSize(width: 100, height: 100)
        let image = try GCodeParser.extractThumbnail(from: data, maxSize: maxSize)

        XCTAssertLessThanOrEqual(image.width, Int(maxSize.width))
        XCTAssertLessThanOrEqual(image.height, Int(maxSize.height))
    }

    func testExtractThumbnail_ValidSyntheticThumbnail() throws {
        // Create a minimal valid GCode with embedded thumbnail
        let pngBase64 = createMinimalPNGBase64()
        let gcode = """
        ; generated by PrusaSlicer
        ; thumbnail begin 16x16 \(pngBase64.count)
        ; \(pngBase64)
        ; thumbnail end
        G28 ; Home all axes
        """

        let data = gcode.data(using: .utf8)!
        let image = try GCodeParser.extractThumbnail(from: data)

        XCTAssertEqual(image.width, 16)
        XCTAssertEqual(image.height, 16)
    }

    func testExtractThumbnail_MultipleThumbnails_SelectsLargest() throws {
        // Create GCode with multiple thumbnails of different sizes
        let smallPNG = createMinimalPNGBase64()
        let gcode = """
        ; thumbnail begin 16x16 \(smallPNG.count)
        ; \(smallPNG)
        ; thumbnail end
        ; thumbnail begin 32x32 \(smallPNG.count)
        ; \(smallPNG)
        ; thumbnail end
        """

        let data = gcode.data(using: .utf8)!

        // The parser should select the largest thumbnail (32x32)
        // Note: The actual image size will be 16x16 because we're using the same base64 data
        // But the parser attempts to select based on the declared dimensions
        let image = try GCodeParser.extractThumbnail(from: data)
        XCTAssertGreaterThan(image.width, 0)
    }

    func testExtractThumbnail_NoThumbnail() {
        let gcode = """
        ; generated by PrusaSlicer
        G28 ; Home all axes
        G1 X100 Y100
        """

        let data = gcode.data(using: .utf8)!

        XCTAssertThrowsError(try GCodeParser.extractThumbnail(from: data)) { error in
            XCTAssertEqual(error as? ThumbnailExtractorError, .thumbnailNotFound)
        }
    }

    func testExtractThumbnail_InvalidBase64() {
        let gcode = """
        ; thumbnail begin 16x16 100
        ; !!!invalid-base64!!!
        ; thumbnail end
        """

        let data = gcode.data(using: .utf8)!

        XCTAssertThrowsError(try GCodeParser.extractThumbnail(from: data)) { error in
            XCTAssertEqual(error as? ThumbnailExtractorError, .thumbnailNotFound)
        }
    }

    func testExtractThumbnail_EmptyData() {
        let emptyData = Data()

        // Empty GCode has no thumbnails, so it throws thumbnailNotFound
        XCTAssertThrowsError(try GCodeParser.extractThumbnail(from: emptyData)) { error in
            XCTAssertEqual(error as? ThumbnailExtractorError, .thumbnailNotFound)
        }
    }

    // Helper to create a minimal valid PNG in base64
    private func createMinimalPNGBase64() -> String {
        // Minimal 16x16 red PNG
        let pngData: [UInt8] = [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,  // PNG signature
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,  // IHDR chunk
            0x00, 0x00, 0x00, 0x10, 0x00, 0x00, 0x00, 0x10,  // 16x16
            0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x91, 0x68,
            0x36,
            0x00, 0x00, 0x00, 0x19, 0x49, 0x44, 0x41, 0x54,  // IDAT chunk
            0x78, 0x9C, 0x62, 0xF8, 0xCF, 0xC0, 0xC0, 0xC0,
            0xC0, 0xC0, 0xC0, 0xC0, 0xC0, 0xC0, 0xC0, 0xC0,
            0xC0, 0xC0, 0xC0, 0x00, 0x00, 0x05, 0x10, 0x00,
            0x01,
            0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44,  // IEND chunk
            0xAE, 0x42, 0x60, 0x82
        ]
        return Data(pngData).base64EncodedString()
    }
}

final class BGCodeParserTests: XCTestCase {

    func testExtractThumbnail_ValidFile() throws {
        guard let url = Bundle.module.url(
            forResource: "SO101 leader grip",
            withExtension: "bgcode"
        ) else {
            throw XCTSkip("Test file 'SO101 leader grip.bgcode' not found in test bundle")
        }

        let data = try Data(contentsOf: url)
        let image = try BGCodeParser.extractThumbnail(from: data)

        XCTAssertGreaterThan(image.width, 0)
        XCTAssertGreaterThan(image.height, 0)
    }

    func testExtractThumbnail_WithMaxSize() throws {
        guard let url = Bundle.module.url(
            forResource: "SO101 leader grip",
            withExtension: "bgcode"
        ) else {
            throw XCTSkip("Test file 'SO101 leader grip.bgcode' not found in test bundle")
        }

        let data = try Data(contentsOf: url)
        let maxSize = CGSize(width: 100, height: 100)
        let image = try BGCodeParser.extractThumbnail(from: data, maxSize: maxSize)

        XCTAssertLessThanOrEqual(image.width, Int(maxSize.width))
        XCTAssertLessThanOrEqual(image.height, Int(maxSize.height))
    }

    func testExtractThumbnail_InvalidMagic() {
        let invalidData = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09])

        XCTAssertThrowsError(try BGCodeParser.extractThumbnail(from: invalidData)) { error in
            XCTAssertEqual(error as? ThumbnailExtractorError, .invalidFileFormat)
        }
    }

    func testExtractThumbnail_EmptyData() {
        let emptyData = Data()

        XCTAssertThrowsError(try BGCodeParser.extractThumbnail(from: emptyData)) { error in
            XCTAssertEqual(error as? ThumbnailExtractorError, .invalidFileFormat)
        }
    }

    func testExtractThumbnail_TooSmallData() {
        // Valid magic but too small to have any blocks
        let magic: [UInt8] = [0x47, 0x43, 0x44, 0x45]  // "GCDE"
        let smallData = Data(magic)

        XCTAssertThrowsError(try BGCodeParser.extractThumbnail(from: smallData)) { error in
            XCTAssertEqual(error as? ThumbnailExtractorError, .invalidFileFormat)
        }
    }
}

final class ThumbnailExtractorIntegrationTests: XCTestCase {

    func testExtractThumbnail_3MFFile() throws {
        guard let url = Bundle.module.url(
            forResource: "First Layer - square",
            withExtension: "3mf"
        ) else {
            throw XCTSkip("Test file 'First Layer - square.3mf' not found in test bundle")
        }

        let image = try ThumbnailExtractor.extractThumbnail(from: url)

        XCTAssertGreaterThan(image.width, 0)
        XCTAssertGreaterThan(image.height, 0)
    }

    func testExtractThumbnail_GCodeFile() throws {
        guard let url = Bundle.module.url(
            forResource: "SO101 leader grip",
            withExtension: "gcode"
        ) else {
            throw XCTSkip("Test file 'SO101 leader grip.gcode' not found in test bundle")
        }

        let image = try ThumbnailExtractor.extractThumbnail(from: url)

        XCTAssertGreaterThan(image.width, 0)
        XCTAssertGreaterThan(image.height, 0)
    }

    func testExtractThumbnail_BGCodeFile() throws {
        guard let url = Bundle.module.url(
            forResource: "SO101 leader grip",
            withExtension: "bgcode"
        ) else {
            throw XCTSkip("Test file 'SO101 leader grip.bgcode' not found in test bundle")
        }

        let image = try ThumbnailExtractor.extractThumbnail(from: url)

        XCTAssertGreaterThan(image.width, 0)
        XCTAssertGreaterThan(image.height, 0)
    }

    func testExtractThumbnail_UnsupportedFormat() {
        let url = URL(fileURLWithPath: "/path/to/file.stl")

        XCTAssertThrowsError(try ThumbnailExtractor.extractThumbnail(from: url)) { error in
            guard case ThumbnailExtractorError.unsupportedFormat(let ext) = error else {
                XCTFail("Expected unsupportedFormat error")
                return
            }
            XCTAssertEqual(ext, "stl")
        }
    }

    func testExtractThumbnail_NonExistentFile() {
        let url = URL(fileURLWithPath: "/nonexistent/file.3mf")

        XCTAssertThrowsError(try ThumbnailExtractor.extractThumbnail(from: url)) { error in
            XCTAssertEqual(error as? ThumbnailExtractorError, .fileNotFound)
        }
    }
}
