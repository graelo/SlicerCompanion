//
//  ThumbnailExtractor.swift
//  SlicerCompanion
//
//  Pure Swift implementation for extracting thumbnails from 3D printing files:
//  - 3MF (ZIP archive with embedded PNG/JPEG)
//  - GCode (text with base64-encoded PNG)
//  - BGCode (binary format with embedded thumbnails)
//
//  No external dependencies - uses only Apple frameworks.
//

import Compression
import CoreGraphics
import Foundation
import ImageIO
import os.log

// MARK: - Supported File Types

enum SlicerFileType: String, CaseIterable {
    case threeMF = "3mf"
    case gcode = "gcode"
    case gco = "gco"
    case bgcode = "bgcode"

    static func from(url: URL) -> SlicerFileType? {
        let ext = url.pathExtension.lowercased()
        return SlicerFileType(rawValue: ext)
    }
}

// MARK: - Error Types

enum ThumbnailExtractorError: Error, LocalizedError, Equatable {
    case fileNotFound
    case unsupportedFormat(String)
    case invalidFileFormat
    case thumbnailNotFound
    case decompressionFailed
    case imageCreationFailed
    case invalidZipFile
    case corruptedFile

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "File not found"
        case .unsupportedFormat(let ext):
            return "Unsupported file format: \(ext)"
        case .invalidFileFormat:
            return "Invalid file format"
        case .thumbnailNotFound:
            return "No thumbnail found in file"
        case .decompressionFailed:
            return "Failed to decompress data"
        case .imageCreationFailed:
            return "Failed to create image from thumbnail data"
        case .invalidZipFile:
            return "Invalid ZIP file format"
        case .corruptedFile:
            return "Corrupted file"
        }
    }
}

// MARK: - Main Thumbnail Extractor

struct ThumbnailExtractor {
    private static let logger = Logger(
        subsystem: "org.slicercompanion",
        category: "ThumbnailExtractor"
    )

    /// Extract thumbnail from a slicer file (3MF, GCode, or BGCode)
    static func extractThumbnail(from fileURL: URL, maxSize: CGSize? = nil) throws -> CGImage {
        NSLog("[ThumbnailExtractor] Starting extraction from: %@", fileURL.path)
        logger.info("Extracting thumbnail from: \(fileURL.path)")

        guard let fileType = SlicerFileType.from(url: fileURL) else {
            let ext = fileURL.pathExtension
            NSLog("[ThumbnailExtractor] Unsupported file extension: %@", ext)
            logger.error("Unsupported file extension: \(ext)")
            throw ThumbnailExtractorError.unsupportedFormat(ext)
        }
        NSLog("[ThumbnailExtractor] File type detected: %@", fileType.rawValue)

        // Handle security scoped resources
        let didStartAccessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        // Read file data
        let fileData: Data
        do {
            NSLog("[ThumbnailExtractor] Reading file data...")
            fileData = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            NSLog("[ThumbnailExtractor] Read %d bytes from file", fileData.count)
            logger.debug("Read \(fileData.count) bytes from file")
        } catch {
            NSLog("[ThumbnailExtractor] Failed to read file: %@", error.localizedDescription)
            logger.error("Failed to read file: \(error.localizedDescription)")
            throw ThumbnailExtractorError.fileNotFound
        }

        // Extract based on file type
        let image: CGImage
        switch fileType {
        case .threeMF:
            NSLog("[ThumbnailExtractor] Parsing 3MF file...")
            image = try ThreeMFParser.extractThumbnail(from: fileData, maxSize: maxSize)
        case .gcode, .gco:
            NSLog("[ThumbnailExtractor] Parsing GCode file...")
            image = try GCodeParser.extractThumbnail(from: fileData, maxSize: maxSize)
        case .bgcode:
            NSLog("[ThumbnailExtractor] Parsing BGCode file...")
            image = try BGCodeParser.extractThumbnail(from: fileData, maxSize: maxSize)
        }

        NSLog("[ThumbnailExtractor] Successfully extracted thumbnail (%dx%d)", image.width, image.height)
        logger.info("Successfully extracted thumbnail (\(image.width)x\(image.height))")
        return image
    }
}

// MARK: - ZIP File Format Constants

private struct ZIPConstants {
    static let localFileSignature: UInt32 = 0x0403_4b50
    static let centralDirSignature: UInt32 = 0x0201_4b50
    static let endOfCentralDirSignature: UInt32 = 0x0605_4b50

    static let compressionStored: UInt16 = 0
    static let compressionDeflate: UInt16 = 8
}

// MARK: - ZIP Structures

private struct ZIPLocalFileHeader {
    let signature: UInt32
    let version: UInt16
    let flags: UInt16
    let compression: UInt16
    let modTime: UInt16
    let modDate: UInt16
    let crc32: UInt32
    let compressedSize: UInt32
    let uncompressedSize: UInt32
    let filenameLength: UInt16
    let extraFieldLength: UInt16

    static let size = 30
}

private struct ZIPCentralDirHeader {
    let signature: UInt32
    let versionMadeBy: UInt16
    let versionNeeded: UInt16
    let flags: UInt16
    let compression: UInt16
    let modTime: UInt16
    let modDate: UInt16
    let crc32: UInt32
    let compressedSize: UInt32
    let uncompressedSize: UInt32
    let filenameLength: UInt16
    let extraFieldLength: UInt16
    let commentLength: UInt16
    let diskNumber: UInt16
    let internalAttributes: UInt16
    let externalAttributes: UInt32
    let localHeaderOffset: UInt32

    static let size = 46
}

private struct ZIPEndOfCentralDir {
    let signature: UInt32
    let diskNumber: UInt16
    let centralDirDisk: UInt16
    let entriesOnDisk: UInt16
    let totalEntries: UInt16
    let centralDirSize: UInt32
    let centralDirOffset: UInt32
    let commentLength: UInt16

    static let size = 22
}

// MARK: - 3MF Parser (ZIP-based)

struct ThreeMFParser {
    private static let logger = Logger(
        subsystem: "org.slicercompanion",
        category: "ThreeMFParser"
    )

    /// Thumbnail paths to search in 3MF files (in priority order)
    private static let thumbnailPaths = [
        "Metadata/thumbnail.png",
        "Metadata/thumbnail.jpeg",
        "Metadata/thumbnail.jpg",
        "Thumbnails/thumbnail.png",
        "Thumbnails/thumbnail.jpeg",
        "Thumbnails/thumbnail.jpg",
    ]

    static func extractThumbnail(from zipData: Data, maxSize: CGSize? = nil) throws -> CGImage {
        NSLog("[ThreeMFParser] Starting 3MF parsing (%d bytes)", zipData.count)
        logger.info("Parsing 3MF file (\(zipData.count) bytes)")

        guard zipData.count >= ZIPLocalFileHeader.size else {
            NSLog("[ThreeMFParser] File too small")
            throw ThumbnailExtractorError.invalidZipFile
        }

        // Verify ZIP signature
        NSLog("[ThreeMFParser] Verifying ZIP signature...")
        let signature = zipData.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        guard signature == ZIPConstants.localFileSignature else {
            NSLog("[ThreeMFParser] Invalid ZIP signature: 0x%08x", signature)
            logger.error("Invalid ZIP signature: 0x\(String(signature, radix: 16))")
            throw ThumbnailExtractorError.invalidZipFile
        }
        NSLog("[ThreeMFParser] ZIP signature valid")

        // Find end of central directory
        NSLog("[ThreeMFParser] Finding end of central directory...")
        guard let endOfCentralDir = findEndOfCentralDirectory(in: zipData) else {
            NSLog("[ThreeMFParser] Could not find end of central directory")
            throw ThumbnailExtractorError.corruptedFile
        }
        NSLog("[ThreeMFParser] Found EOCD at offset %d, %d entries", endOfCentralDir.centralDirOffset, endOfCentralDir.totalEntries)

        // Try each thumbnail path
        for thumbnailPath in thumbnailPaths {
            NSLog("[ThreeMFParser] Trying to extract: %@", thumbnailPath)
            if let thumbnailData = try? extractFile(
                from: zipData,
                endOfCentralDir: endOfCentralDir,
                filename: thumbnailPath
            ) {
                NSLog("[ThreeMFParser] Found thumbnail at: %@ (%d bytes)", thumbnailPath, thumbnailData.count)
                logger.debug("Found thumbnail at: \(thumbnailPath)")
                if let image = createImage(from: thumbnailData, maxSize: maxSize) {
                    NSLog("[ThreeMFParser] Created image successfully")
                    return image
                }
                NSLog("[ThreeMFParser] Failed to create image from thumbnail data")
            }
        }

        NSLog("[ThreeMFParser] No thumbnail found in 3MF file")
        logger.warning("No thumbnail found in 3MF file")
        throw ThumbnailExtractorError.thumbnailNotFound
    }
}

// MARK: - GCode Parser (Text + Base64)

struct GCodeParser {
    private static let logger = Logger(
        subsystem: "org.slicercompanion",
        category: "GCodeParser"
    )

    /// Regex pattern for thumbnail begin line
    /// Format: ; thumbnail begin <width>x<height> <size>
    private static let thumbnailBeginPattern = #"; thumbnail begin (\d+)x(\d+) (\d+)"#

    static func extractThumbnail(from data: Data, maxSize: CGSize? = nil) throws -> CGImage {
        logger.info("Parsing GCode file (\(data.count) bytes)")

        guard let content = String(data: data, encoding: .utf8) else {
            // Try latin1 as fallback
            guard let content = String(data: data, encoding: .isoLatin1) else {
                throw ThumbnailExtractorError.invalidFileFormat
            }
            return try extractThumbnailFromText(content, maxSize: maxSize)
        }

        return try extractThumbnailFromText(content, maxSize: maxSize)
    }

    private static func extractThumbnailFromText(_ content: String, maxSize: CGSize?) throws -> CGImage {
        // Find all thumbnails and select the largest
        var thumbnails: [(width: Int, height: Int, data: Data)] = []

        let lines = content.components(separatedBy: .newlines)
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Check for thumbnail begin
            if line.contains("; thumbnail begin") {
                if let thumbnailInfo = parseThumbnailBlock(lines: lines, startIndex: i) {
                    thumbnails.append((width: thumbnailInfo.width, height: thumbnailInfo.height, data: thumbnailInfo.data))
                    i = thumbnailInfo.endIndex
                    continue
                }
            }
            i += 1
        }

        guard !thumbnails.isEmpty else {
            logger.warning("No thumbnails found in GCode file")
            throw ThumbnailExtractorError.thumbnailNotFound
        }

        // Select largest thumbnail
        let largest = thumbnails.max(by: { ($0.width * $0.height) < ($1.width * $1.height) })!
        logger.debug("Selected thumbnail: \(largest.width)x\(largest.height)")

        guard let image = createImage(from: largest.data, maxSize: maxSize) else {
            throw ThumbnailExtractorError.imageCreationFailed
        }

        return image
    }

    private static func parseThumbnailBlock(
        lines: [String],
        startIndex: Int
    ) -> (width: Int, height: Int, data: Data, endIndex: Int)? {
        let beginLine = lines[startIndex]

        // Parse dimensions from begin line
        guard let regex = try? NSRegularExpression(pattern: thumbnailBeginPattern),
              let match = regex.firstMatch(
                  in: beginLine,
                  range: NSRange(beginLine.startIndex..., in: beginLine)
              ),
              match.numberOfRanges >= 4
        else {
            return nil
        }

        guard let widthRange = Range(match.range(at: 1), in: beginLine),
              let heightRange = Range(match.range(at: 2), in: beginLine),
              let width = Int(beginLine[widthRange]),
              let height = Int(beginLine[heightRange])
        else {
            return nil
        }

        // Collect base64 lines until "; thumbnail end"
        var base64Lines: [String] = []
        var i = startIndex + 1

        while i < lines.count {
            let line = lines[i]

            if line.contains("; thumbnail end") {
                break
            }

            // Extract base64 data (remove leading "; ")
            if line.hasPrefix("; ") {
                let base64Part = String(line.dropFirst(2))
                base64Lines.append(base64Part)
            } else if line.hasPrefix(";") {
                let base64Part = String(line.dropFirst(1))
                base64Lines.append(base64Part)
            }

            i += 1
        }

        // Decode base64
        let base64String = base64Lines.joined()
        guard let imageData = Data(base64Encoded: base64String, options: .ignoreUnknownCharacters) else {
            logger.warning("Failed to decode base64 thumbnail data")
            return nil
        }

        return (width: width, height: height, data: imageData, endIndex: i)
    }
}

// MARK: - BGCode Parser (Binary)

struct BGCodeParser {
    private static let logger = Logger(
        subsystem: "org.slicercompanion",
        category: "BGCodeParser"
    )

    // BGCode magic number: "GCDE" in ASCII
    private static let magicNumber: UInt32 = 0x4544_4347  // "GCDE" little-endian

    // Block types
    private static let blockTypeThumbnail: UInt16 = 5

    // Thumbnail formats
    private static let formatPNG: UInt16 = 0
    private static let formatJPG: UInt16 = 1
    private static let formatQOI: UInt16 = 2

    // Compression types
    private static let compressionNone: UInt16 = 0
    private static let compressionDeflate: UInt16 = 1
    private static let compressionHeatshrink11: UInt16 = 2
    private static let compressionHeatshrink12: UInt16 = 3

    static func extractThumbnail(from data: Data, maxSize: CGSize? = nil) throws -> CGImage {
        NSLog("[BGCodeParser] Starting BGCode parsing (%d bytes)", data.count)
        logger.info("Parsing BGCode file (\(data.count) bytes)")

        guard data.count >= 10 else {
            NSLog("[BGCodeParser] File too small")
            throw ThumbnailExtractorError.invalidFileFormat
        }

        // Verify magic number
        let magic = readUInt32(from: data, at: 0)
        guard magic == magicNumber else {
            NSLog("[BGCodeParser] Invalid magic: 0x%08x", magic)
            logger.error("Invalid BGCode magic: 0x\(String(magic, radix: 16))")
            throw ThumbnailExtractorError.invalidFileFormat
        }
        NSLog("[BGCodeParser] Magic verified")

        // Parse file header (10 bytes)
        // Bytes 0-3: Magic "GCDE"
        // Byte 4: Version
        // Byte 5: Reserved
        // Bytes 6-7: Reserved
        // Bytes 8-9: Checksum type
        let version = data[4]
        NSLog("[BGCodeParser] Version: %d", version)
        logger.debug("BGCode version: \(version)")

        // Find all thumbnail blocks and select largest
        var thumbnails: [(width: Int, height: Int, image: CGImage)] = []
        var offset = 10  // Start after file header

        var blockCount = 0
        while offset + 8 <= data.count {
            // Read block header
            let blockType = readUInt16(from: data, at: offset)
            let compression = readUInt16(from: data, at: offset + 2)
            let uncompressedSize = readUInt32(from: data, at: offset + 4)

            // Determine header size based on compression
            let headerSize: Int
            let compressedSize: UInt32
            if compression == compressionNone {
                headerSize = 8
                compressedSize = uncompressedSize
            } else {
                headerSize = 12
                guard offset + 12 <= data.count else { break }
                compressedSize = readUInt32(from: data, at: offset + 8)
            }

            // Block-type-specific parameter sizes (NOT included in uncompressed_size)
            // Type 0-3: Metadata blocks have 2-byte encoding param
            // Type 4: GCode block has 2-byte encoding param
            // Type 5: Thumbnail block has 6-byte params (format, width, height)
            let paramSize: Int
            switch blockType {
            case 0, 1, 2, 3, 4:  // Metadata and GCode blocks
                paramSize = 2
            case 5:  // Thumbnail
                paramSize = 6
            default:
                paramSize = 0
            }

            blockCount += 1
            NSLog("[BGCodeParser] Block %d at offset 0x%x: type=%d, compression=%d, size=%d, paramSize=%d",
                  blockCount, offset, blockType, compression, compressedSize, paramSize)

            // Skip to block parameters
            let paramsOffset = offset + headerSize

            if blockType == blockTypeThumbnail {
                NSLog("[BGCodeParser] Found thumbnail block!")
                // Parse thumbnail block
                if let thumbnail = parseThumbnailBlock(
                    from: data,
                    at: paramsOffset,
                    compression: compression,
                    compressedSize: Int(compressedSize),
                    uncompressedSize: Int(uncompressedSize),
                    maxSize: maxSize
                ) {
                    NSLog("[BGCodeParser] Thumbnail parsed: %dx%d", thumbnail.width, thumbnail.height)
                    thumbnails.append(thumbnail)
                } else {
                    NSLog("[BGCodeParser] Failed to parse thumbnail block")
                }
            }

            // Move to next block: header + params + data + CRC(4)
            offset = paramsOffset + paramSize + Int(compressedSize) + 4

            // Safety check to prevent infinite loops
            if compressedSize == 0 && blockType != 5 {
                NSLog("[BGCodeParser] Zero-size block (type %d), stopping", blockType)
                break
            }
        }
        NSLog("[BGCodeParser] Finished parsing %d blocks, found %d thumbnails", blockCount, thumbnails.count)

        guard !thumbnails.isEmpty else {
            logger.warning("No thumbnails found in BGCode file")
            throw ThumbnailExtractorError.thumbnailNotFound
        }

        // Select largest thumbnail
        let largest = thumbnails.max(by: { ($0.width * $0.height) < ($1.width * $1.height) })!
        logger.debug("Selected thumbnail: \(largest.width)x\(largest.height)")

        return largest.image
    }

    private static func parseThumbnailBlock(
        from data: Data,
        at offset: Int,
        compression: UInt16,
        compressedSize: Int,
        uncompressedSize: Int,
        maxSize: CGSize?
    ) -> (width: Int, height: Int, image: CGImage)? {
        // Thumbnail block parameters (6 bytes) - NOT included in compressedSize
        // Bytes 0-1: Format (0=PNG, 1=JPG, 2=QOI)
        // Bytes 2-3: Width
        // Bytes 4-5: Height
        guard offset + 6 <= data.count else { return nil }

        let format = readUInt16(from: data, at: offset)
        let width = Int(readUInt16(from: data, at: offset + 2))
        let height = Int(readUInt16(from: data, at: offset + 4))

        NSLog("[BGCodeParser] Thumbnail params: format=%d, size=%dx%d, compression=%d", format, width, height, compression)
        logger.debug("Thumbnail block: format=\(format), size=\(width)x\(height), compression=\(compression)")

        // Image data starts after parameters (params are NOT in compressedSize)
        let imageDataOffset = offset + 6
        let imageDataSize = compressedSize  // compressedSize is the actual image data size

        guard imageDataOffset + imageDataSize <= data.count else { return nil }

        let compressedData = data.subdata(in: imageDataOffset..<(imageDataOffset + imageDataSize))

        // Decompress if needed
        let imageData: Data
        do {
            switch compression {
            case compressionNone:
                imageData = compressedData
            case compressionDeflate:
                imageData = try deflateDecompress(data: compressedData, expectedSize: uncompressedSize)
            case compressionHeatshrink11:
                imageData = try heatshrinkDecompress(data: compressedData, windowBits: 11, lookaheadBits: 4)
            case compressionHeatshrink12:
                imageData = try heatshrinkDecompress(data: compressedData, windowBits: 12, lookaheadBits: 4)
            default:
                logger.warning("Unsupported compression type: \(compression)")
                return nil
            }
        } catch {
            logger.warning("Decompression failed: \(error.localizedDescription)")
            return nil
        }

        // Decode image based on format
        let image: CGImage?
        switch format {
        case formatPNG, formatJPG:
            image = createImage(from: imageData, maxSize: maxSize)
        case formatQOI:
            image = QOIDecoder.decode(from: imageData, maxSize: maxSize)
        default:
            logger.warning("Unsupported thumbnail format: \(format)")
            return nil
        }

        guard let image = image else { return nil }
        return (width: width, height: height, image: image)
    }
}

// MARK: - QOI Image Decoder

/// Decoder for QOI (Quite OK Image) format
/// Spec: https://qoiformat.org/qoi-specification.pdf
struct QOIDecoder {
    private static let logger = Logger(
        subsystem: "org.slicercompanion",
        category: "QOIDecoder"
    )

    // QOI magic number: "qoif"
    private static let magic: UInt32 = 0x66696F71  // "qoif" little-endian

    // QOI op codes
    private static let opRGB: UInt8 = 0xFE
    private static let opRGBA: UInt8 = 0xFF
    private static let opIndex: UInt8 = 0x00  // 2-bit tag: 00xxxxxx
    private static let opDiff: UInt8 = 0x40   // 2-bit tag: 01xxxxxx
    private static let opLuma: UInt8 = 0x80   // 2-bit tag: 10xxxxxx
    private static let opRun: UInt8 = 0xC0    // 2-bit tag: 11xxxxxx

    static func decode(from data: Data, maxSize: CGSize? = nil) -> CGImage? {
        guard data.count >= 14 else {
            logger.error("QOI data too small")
            return nil
        }

        // Parse header - check for magic in either endianness
        let magic = data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        let magicBE = UInt32(bigEndian: magic)

        guard magic == self.magic || magicBE == 0x716F6966 else {
            logger.error("Invalid QOI magic")
            return nil
        }

        // Width and height are big-endian in QOI
        let width = Int(UInt32(bigEndian: readUInt32BE(from: data, at: 4)))
        let height = Int(UInt32(bigEndian: readUInt32BE(from: data, at: 8)))
        let channels = data[12]  // 3 = RGB, 4 = RGBA
        // let colorspace = data[13]  // 0 = sRGB, 1 = linear

        logger.debug("QOI: \(width)x\(height), channels=\(channels)")

        guard width > 0, height > 0, width < 32768, height < 32768 else {
            logger.error("Invalid QOI dimensions")
            return nil
        }

        // Decode pixels
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        var index = [RGBA](repeating: RGBA(r: 0, g: 0, b: 0, a: 0), count: 64)
        var prev = RGBA(r: 0, g: 0, b: 0, a: 255)

        var dataPos = 14
        var pixelPos = 0
        let pixelCount = width * height

        while pixelPos < pixelCount && dataPos < data.count - 8 {
            let byte = data[dataPos]
            dataPos += 1

            if byte == opRGB {
                prev.r = data[dataPos]
                prev.g = data[dataPos + 1]
                prev.b = data[dataPos + 2]
                dataPos += 3
            } else if byte == opRGBA {
                prev.r = data[dataPos]
                prev.g = data[dataPos + 1]
                prev.b = data[dataPos + 2]
                prev.a = data[dataPos + 3]
                dataPos += 4
            } else {
                let tag = byte & 0xC0

                switch tag {
                case opIndex:
                    let idx = Int(byte & 0x3F)
                    prev = index[idx]

                case opDiff:
                    let dr = Int8(bitPattern: ((byte >> 4) & 0x03)) - 2
                    let dg = Int8(bitPattern: ((byte >> 2) & 0x03)) - 2
                    let db = Int8(bitPattern: (byte & 0x03)) - 2
                    prev.r = UInt8(truncatingIfNeeded: Int(prev.r) + Int(dr))
                    prev.g = UInt8(truncatingIfNeeded: Int(prev.g) + Int(dg))
                    prev.b = UInt8(truncatingIfNeeded: Int(prev.b) + Int(db))

                case opLuma:
                    let byte2 = data[dataPos]
                    dataPos += 1
                    let dg = Int(byte & 0x3F) - 32
                    let dr = Int((byte2 >> 4) & 0x0F) - 8 + dg
                    let db = Int(byte2 & 0x0F) - 8 + dg
                    prev.r = UInt8(truncatingIfNeeded: Int(prev.r) + dr)
                    prev.g = UInt8(truncatingIfNeeded: Int(prev.g) + dg)
                    prev.b = UInt8(truncatingIfNeeded: Int(prev.b) + db)

                case opRun:
                    let run = Int(byte & 0x3F) + 1
                    for _ in 0..<run {
                        if pixelPos >= pixelCount { break }
                        let offset = pixelPos * 4
                        pixels[offset] = prev.r
                        pixels[offset + 1] = prev.g
                        pixels[offset + 2] = prev.b
                        pixels[offset + 3] = prev.a
                        pixelPos += 1
                    }
                    // Update index and continue (skip the normal pixel write)
                    index[prev.hashIndex] = prev
                    continue

                default:
                    break
                }
            }

            // Update index
            index[prev.hashIndex] = prev

            // Write pixel
            let offset = pixelPos * 4
            pixels[offset] = prev.r
            pixels[offset + 1] = prev.g
            pixels[offset + 2] = prev.b
            pixels[offset + 3] = prev.a
            pixelPos += 1
        }

        // Create CGImage
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            logger.error("Failed to create CGContext for QOI")
            return nil
        }

        guard let image = context.makeImage() else {
            logger.error("Failed to create CGImage from QOI")
            return nil
        }

        // Scale if needed
        if let maxSize = maxSize {
            return scaleImage(image, toFit: maxSize)
        }

        return image
    }

    private struct RGBA {
        var r: UInt8
        var g: UInt8
        var b: UInt8
        var a: UInt8

        var hashIndex: Int {
            let rPart = UInt8(r &* 3)
            let gPart = UInt8(g &* 5)
            let bPart = UInt8(b &* 7)
            let aPart = UInt8(a &* 11)
            let sum = rPart &+ gPart &+ bPart &+ aPart
            return Int(sum % 64)
        }
    }
}

// MARK: - Heatshrink Decompressor

/// Pure Swift implementation of Heatshrink decompression
/// Used by BGCode for thumbnail compression
struct HeatshrinkDecompressor {
    private static let logger = Logger(
        subsystem: "org.slicercompanion",
        category: "Heatshrink"
    )

    static func decompress(
        data: Data,
        windowBits: Int,
        lookaheadBits: Int
    ) throws -> Data {
        let windowSize = 1 << windowBits
        // let lookaheadSize = 1 << lookaheadBits

        var output = Data()
        var window = [UInt8](repeating: 0, count: windowSize)
        var windowPos = 0

        var bitBuffer: UInt32 = 0
        var bitsAvailable = 0
        var dataPos = 0

        func readBits(_ count: Int) -> UInt32? {
            while bitsAvailable < count {
                guard dataPos < data.count else { return nil }
                bitBuffer = (bitBuffer << 8) | UInt32(data[dataPos])
                dataPos += 1
                bitsAvailable += 8
            }
            bitsAvailable -= count
            let mask = (UInt32(1) << count) - 1
            return (bitBuffer >> bitsAvailable) & mask
        }

        while true {
            // Read tag bit
            guard let tag = readBits(1) else { break }

            if tag == 1 {
                // Literal byte
                guard let byte = readBits(8) else { break }
                let byteValue = UInt8(byte)
                output.append(byteValue)
                window[windowPos % windowSize] = byteValue
                windowPos += 1
            } else {
                // Backreference
                guard let offset = readBits(windowBits) else { break }
                guard let length = readBits(lookaheadBits) else { break }

                let actualLength = Int(length) + 1
                let backOffset = Int(offset) + 1

                for _ in 0..<actualLength {
                    let idx = (windowPos - backOffset + windowSize) % windowSize
                    let byte = window[idx]
                    output.append(byte)
                    window[windowPos % windowSize] = byte
                    windowPos += 1
                }
            }
        }

        return output
    }
}

// MARK: - ZIP Parsing Helpers

private func findEndOfCentralDirectory(in data: Data) -> ZIPEndOfCentralDir? {
    let dataCount = data.count
    guard dataCount >= ZIPEndOfCentralDir.size else { return nil }

    let searchStart = dataCount - ZIPEndOfCentralDir.size
    let maxSearch = min(searchStart, 65535 + ZIPEndOfCentralDir.size)

    for i in 0...maxSearch {
        let pos = searchStart - i
        guard pos + ZIPEndOfCentralDir.size <= dataCount else { continue }

        let signature = data.subdata(in: pos..<(pos + 4))
            .withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }

        if signature == ZIPConstants.endOfCentralDirSignature {
            return parseEndOfCentralDir(from: data, at: pos)
        }
    }

    return nil
}

private func parseEndOfCentralDir(from data: Data, at offset: Int) -> ZIPEndOfCentralDir {
    let eocdData = data.subdata(in: offset..<(offset + ZIPEndOfCentralDir.size))

    return ZIPEndOfCentralDir(
        signature: readUInt32(from: eocdData, at: 0),
        diskNumber: readUInt16(from: eocdData, at: 4),
        centralDirDisk: readUInt16(from: eocdData, at: 6),
        entriesOnDisk: readUInt16(from: eocdData, at: 8),
        totalEntries: readUInt16(from: eocdData, at: 10),
        centralDirSize: readUInt32(from: eocdData, at: 12),
        centralDirOffset: readUInt32(from: eocdData, at: 16),
        commentLength: readUInt16(from: eocdData, at: 20)
    )
}

private func extractFile(
    from zipData: Data,
    endOfCentralDir: ZIPEndOfCentralDir,
    filename: String
) throws -> Data {
    let filenameData = filename.data(using: .utf8)!
    let centralDirOffset = Int(endOfCentralDir.centralDirOffset)
    let totalEntries = Int(endOfCentralDir.totalEntries)

    var currentOffset = centralDirOffset

    for _ in 0..<totalEntries {
        guard currentOffset + ZIPCentralDirHeader.size <= zipData.count else {
            break
        }

        let centralHeader = parseCentralDirHeader(from: zipData, at: currentOffset)

        guard centralHeader.signature == ZIPConstants.centralDirSignature else {
            break
        }

        let filenameOffset = currentOffset + ZIPCentralDirHeader.size
        let filenameLength = Int(centralHeader.filenameLength)

        guard filenameOffset + filenameLength <= zipData.count else {
            throw ThumbnailExtractorError.corruptedFile
        }

        let entryFilenameData = zipData.subdata(
            in: filenameOffset..<(filenameOffset + filenameLength))

        if entryFilenameData == filenameData {
            return try extractFileData(from: zipData, centralHeader: centralHeader)
        }

        currentOffset +=
            ZIPCentralDirHeader.size + Int(centralHeader.filenameLength)
            + Int(centralHeader.extraFieldLength) + Int(centralHeader.commentLength)
    }

    throw ThumbnailExtractorError.thumbnailNotFound
}

private func parseCentralDirHeader(from data: Data, at offset: Int) -> ZIPCentralDirHeader {
    let headerData = data.subdata(in: offset..<(offset + ZIPCentralDirHeader.size))

    return ZIPCentralDirHeader(
        signature: readUInt32(from: headerData, at: 0),
        versionMadeBy: readUInt16(from: headerData, at: 4),
        versionNeeded: readUInt16(from: headerData, at: 6),
        flags: readUInt16(from: headerData, at: 8),
        compression: readUInt16(from: headerData, at: 10),
        modTime: readUInt16(from: headerData, at: 12),
        modDate: readUInt16(from: headerData, at: 14),
        crc32: readUInt32(from: headerData, at: 16),
        compressedSize: readUInt32(from: headerData, at: 20),
        uncompressedSize: readUInt32(from: headerData, at: 24),
        filenameLength: readUInt16(from: headerData, at: 28),
        extraFieldLength: readUInt16(from: headerData, at: 30),
        commentLength: readUInt16(from: headerData, at: 32),
        diskNumber: readUInt16(from: headerData, at: 34),
        internalAttributes: readUInt16(from: headerData, at: 36),
        externalAttributes: readUInt32(from: headerData, at: 38),
        localHeaderOffset: readUInt32(from: headerData, at: 42)
    )
}

private func extractFileData(from zipData: Data, centralHeader: ZIPCentralDirHeader) throws -> Data {
    let localHeaderOffset = Int(centralHeader.localHeaderOffset)

    guard localHeaderOffset + ZIPLocalFileHeader.size <= zipData.count else {
        throw ThumbnailExtractorError.corruptedFile
    }

    let localHeader = parseLocalFileHeader(from: zipData, at: localHeaderOffset)

    guard localHeader.signature == ZIPConstants.localFileSignature else {
        throw ThumbnailExtractorError.corruptedFile
    }

    let dataOffset =
        localHeaderOffset + ZIPLocalFileHeader.size + Int(localHeader.filenameLength)
        + Int(localHeader.extraFieldLength)

    // Use sizes from central directory header, not local header
    // Local header may have zeros if bit 3 of flags is set (data descriptor present)
    let compressedSize = Int(centralHeader.compressedSize)
    let uncompressedSize = Int(centralHeader.uncompressedSize)

    guard dataOffset + compressedSize <= zipData.count else {
        throw ThumbnailExtractorError.corruptedFile
    }

    let compressedData = zipData.subdata(
        in: dataOffset..<(dataOffset + compressedSize))

    switch centralHeader.compression {
    case ZIPConstants.compressionStored:
        return compressedData

    case ZIPConstants.compressionDeflate:
        return try deflateDecompress(
            data: compressedData,
            expectedSize: uncompressedSize
        )

    default:
        throw ThumbnailExtractorError.decompressionFailed
    }
}

private func parseLocalFileHeader(from data: Data, at offset: Int) -> ZIPLocalFileHeader {
    let headerData = data.subdata(in: offset..<(offset + ZIPLocalFileHeader.size))

    return ZIPLocalFileHeader(
        signature: readUInt32(from: headerData, at: 0),
        version: readUInt16(from: headerData, at: 4),
        flags: readUInt16(from: headerData, at: 6),
        compression: readUInt16(from: headerData, at: 8),
        modTime: readUInt16(from: headerData, at: 10),
        modDate: readUInt16(from: headerData, at: 12),
        crc32: readUInt32(from: headerData, at: 14),
        compressedSize: readUInt32(from: headerData, at: 18),
        uncompressedSize: readUInt32(from: headerData, at: 22),
        filenameLength: readUInt16(from: headerData, at: 26),
        extraFieldLength: readUInt16(from: headerData, at: 28)
    )
}

// MARK: - Decompression Helpers

private func deflateDecompress(data: Data, expectedSize: Int) throws -> Data {
    NSLog("[Deflate] Starting decompression: %d bytes -> expected %d bytes", data.count, expectedSize)
    guard !data.isEmpty else {
        NSLog("[Deflate] Input data is empty")
        throw ThumbnailExtractorError.decompressionFailed
    }

    var outputBuffer = Data(count: expectedSize)
    NSLog("[Deflate] Allocated output buffer")

    let actualSize = try data.withUnsafeBytes { inputBytes in
        try outputBuffer.withUnsafeMutableBytes { outputBytes in
            let inputPtr = inputBytes.bindMemory(to: UInt8.self)
            let outputPtr = outputBytes.bindMemory(to: UInt8.self)

            NSLog("[Deflate] Calling compression_decode_buffer...")
            let result = compression_decode_buffer(
                outputPtr.baseAddress!, expectedSize,
                inputPtr.baseAddress!, data.count,
                nil, COMPRESSION_ZLIB
            )
            NSLog("[Deflate] compression_decode_buffer returned: %d", result)

            guard result > 0 else {
                NSLog("[Deflate] Decompression failed")
                throw ThumbnailExtractorError.decompressionFailed
            }

            return result
        }
    }

    if actualSize != expectedSize {
        NSLog("[Deflate] Actual size (%d) differs from expected (%d)", actualSize, expectedSize)
        outputBuffer = outputBuffer.prefix(actualSize)
    }

    NSLog("[Deflate] Decompression successful: %d bytes", outputBuffer.count)
    return outputBuffer
}

private func heatshrinkDecompress(data: Data, windowBits: Int, lookaheadBits: Int) throws -> Data {
    return try HeatshrinkDecompressor.decompress(
        data: data,
        windowBits: windowBits,
        lookaheadBits: lookaheadBits
    )
}

// MARK: - Binary Reading Helpers

private func readUInt32(from data: Data, at offset: Int) -> UInt32 {
    let subdata = data.subdata(in: offset..<(offset + 4))
    return subdata.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
}

private func readUInt16(from data: Data, at offset: Int) -> UInt16 {
    let subdata = data.subdata(in: offset..<(offset + 2))
    return subdata.withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
}

private func readUInt32BE(from data: Data, at offset: Int) -> UInt32 {
    return UInt32(data[offset]) << 24
        | UInt32(data[offset + 1]) << 16
        | UInt32(data[offset + 2]) << 8
        | UInt32(data[offset + 3])
}

// MARK: - Image Creation Helpers

private func createImage(from imageData: Data, maxSize: CGSize?) -> CGImage? {
    guard !imageData.isEmpty else { return nil }

    // Try to create image using ImageIO (handles both PNG and JPEG)
    guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
    else {
        return nil
    }

    if let maxSize = maxSize {
        return scaleImage(image, toFit: maxSize)
    }

    return image
}

private func scaleImage(_ image: CGImage, toFit maxSize: CGSize) -> CGImage? {
    let originalSize = CGSize(width: image.width, height: image.height)

    let widthRatio = maxSize.width / originalSize.width
    let heightRatio = maxSize.height / originalSize.height
    let scaleFactor = min(widthRatio, heightRatio)

    // Don't upscale
    guard scaleFactor < 1.0 else { return image }

    let newSize = CGSize(
        width: originalSize.width * scaleFactor,
        height: originalSize.height * scaleFactor
    )

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

    guard let context = CGContext(
        data: nil,
        width: Int(newSize.width),
        height: Int(newSize.height),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo.rawValue
    ) else {
        return nil
    }

    context.interpolationQuality = .high
    context.draw(image, in: CGRect(origin: .zero, size: newSize))

    return context.makeImage()
}
