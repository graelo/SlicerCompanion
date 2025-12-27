//
//  HeatshrinkDecompressorTests.swift
//  SlicerCompanionTests
//
//  Unit tests for the Heatshrink decompressor.
//

import Foundation
import XCTest

@testable import SlicerCompanionLib

final class HeatshrinkDecompressorTests: XCTestCase {

    func testDecompress_EmptyData() throws {
        let emptyData = Data()
        let result = try HeatshrinkDecompressor.decompress(
            data: emptyData,
            windowBits: 11,
            lookaheadBits: 4
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testDecompress_Window11Lookahead4_DoesNotCrash() throws {
        // Test that the decompressor handles various inputs without crashing
        // The actual correctness is validated through BGCodeParser integration tests
        let randomData = Data((0..<100).map { _ in UInt8.random(in: 0...255) })

        // Should not throw - just process what it can
        _ = try HeatshrinkDecompressor.decompress(
            data: randomData,
            windowBits: 11,
            lookaheadBits: 4
        )
    }

    func testDecompress_Window12Lookahead4_DoesNotCrash() throws {
        let randomData = Data((0..<100).map { _ in UInt8.random(in: 0...255) })

        _ = try HeatshrinkDecompressor.decompress(
            data: randomData,
            windowBits: 12,
            lookaheadBits: 4
        )
    }

    func testDecompress_SingleByte_DoesNotCrash() throws {
        let singleByte = Data([0xFF])

        _ = try HeatshrinkDecompressor.decompress(
            data: singleByte,
            windowBits: 11,
            lookaheadBits: 4
        )
    }
}
