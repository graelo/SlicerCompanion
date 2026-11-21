import SwiftUI
import UniformTypeIdentifiers

struct GCodeDocument: FileDocument {
    static var readableContentTypes: [UTType] = [
        UTType(importedAs: "org.slicercompanion.gcode", conformingTo: .plainText)
    ]

    let text: String

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

struct ContentView: View {
    let document: GCodeDocument
    @State private var toolpath: GCodeToolpath?
    @State private var previewImage: CGImage?
    @State private var selectedLayer = 0.0
    @State private var zoomScale = 1.0
    @State private var rotation = Angle.zero
    @GestureState private var magnificationDelta = 1.0
    @GestureState private var rotationDelta = Angle.zero

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Toolpath", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.headline)
                Spacer()
                Button {
                    zoomScale = 1
                    rotation = .zero
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .help("Reset view")
                .disabled(zoomScale == 1 && rotation == .zero)
                if let toolpath {
                    Text("Layer \(Int(selectedLayer) + 1) of \(toolpath.layerCount)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            Divider()

            Group {
                if let previewImage {
                    Image(decorative: previewImage, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(zoomScale * magnificationDelta)
                        .rotationEffect(rotation + rotationDelta)
                        .contentShape(Rectangle())
                        .gesture(
                            MagnificationGesture()
                                .updating($magnificationDelta) { value, state, _ in
                                    state = value
                                }
                                .onEnded { value in
                                    zoomScale = min(max(zoomScale * value, 0.25), 8)
                                }
                        )
                        .simultaneousGesture(
                            RotationGesture()
                                .updating($rotationDelta) { value, state, _ in
                                    state = value
                                }
                                .onEnded { value in
                                    rotation = rotation + value
                                }
                        )
                        .padding(24)
                } else if toolpath != nil {
                    ContentUnavailableView("No toolpath found", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                } else {
                    ProgressView("Reading G-code…")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack(spacing: 12) {
                Button {
                    selectedLayer = max(0, selectedLayer - 1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .help("Previous layer")
                .disabled(selectedLayer <= 0)

                Slider(value: $selectedLayer, in: 0...Double(max(1, (toolpath?.layerCount ?? 1) - 1)), step: 1)
                    .disabled((toolpath?.layerCount ?? 0) <= 1)

                Button {
                    selectedLayer = min(Double((toolpath?.layerCount ?? 1) - 1), selectedLayer + 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .help("Next layer")
                .disabled(selectedLayer >= Double((toolpath?.layerCount ?? 1) - 1))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .task(id: document.text) {
            let text = document.text
            let parsed = await Task.detached(priority: .userInitiated) {
                GCodeToolpath.parse(text)
            }.value
            guard !Task.isCancelled else { return }
            toolpath = parsed
            selectedLayer = Double(max(0, parsed.layerCount - 1))
            previewImage = parsed.makeImage(layer: Int(selectedLayer))
        }
        .onChange(of: selectedLayer) { _, layer in
            previewImage = toolpath?.makeImage(layer: Int(layer))
        }
    }
}
