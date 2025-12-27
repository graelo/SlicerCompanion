# Makefile for SlicerCompanion
# Uses Xcode's toolchain for testing (required for XCTest)

XCODE_DEV_DIR := /Applications/Xcode.app/Contents/Developer

.PHONY: test build clean

# Run tests using Xcode's toolchain (provides XCTest)
test:
	DEVELOPER_DIR=$(XCODE_DEV_DIR) swift test

# Build the library
build:
	DEVELOPER_DIR=$(XCODE_DEV_DIR) swift build

# Clean build artifacts
clean:
	swift package clean
