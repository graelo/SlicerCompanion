import Cocoa
import Quartz
import SceneKit

class PreviewViewController: NSViewController, QLPreviewingController {

    override var nibName: NSNib.Name? {
        return NSNib.Name("PreviewViewController")
    }

    override func loadView() {
        super.loadView()
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let fileExtension = url.pathExtension.lowercased()
        if fileExtension == "gcode" || fileExtension == "gco" {
            let fileData = try Data(contentsOf: url)
            let text = String(data: fileData, encoding: .utf8)
                ?? String(data: fileData, encoding: .isoLatin1)
                ?? ""
            let toolpath = GCodeToolpath.parse(text)
            if let scene = makeScene(from: toolpath) {
                let sceneView = SCNView(frame: view.bounds)
                sceneView.autoresizingMask = [.width, .height]
                sceneView.scene = scene
                sceneView.backgroundColor = .windowBackgroundColor
                sceneView.autoenablesDefaultLighting = true
                sceneView.allowsCameraControl = true
                sceneView.antialiasingMode = .multisampling4X
                view.addSubview(sceneView)
                return
            }

            showText(text)
            return
        }

        let image = try ThumbnailExtractor.extractThumbnail(from: url)
        let imageView = NSImageView(frame: view.bounds)
        imageView.autoresizingMask = [.width, .height]
        imageView.image = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        view.addSubview(imageView)
    }

    private func showText(_ text: String) {
        let scrollView = NSScrollView(frame: view.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.string = text
        scrollView.documentView = textView
        view.addSubview(scrollView)
    }

    private func makeScene(from toolpath: GCodeToolpath) -> SCNScene? {
        let moves = Array(toolpath.moves.prefix(150_000))
        guard !moves.isEmpty else { return nil }

        var extrusionVertices: [SCNVector3] = []
        var travelVertices: [SCNVector3] = []
        extrusionVertices.reserveCapacity(moves.count)
        travelVertices.reserveCapacity(moves.count / 4)

        for move in moves {
            let start = SCNVector3(Float(move.start.x), Float(move.start.z), Float(move.start.y))
            let end = SCNVector3(Float(move.end.x), Float(move.end.z), Float(move.end.y))
            if move.extrudes {
                extrusionVertices.append(contentsOf: [start, end])
            } else {
                travelVertices.append(contentsOf: [start, end])
            }
        }

        let scene = SCNScene()
        addLines(extrusionVertices, color: NSColor(calibratedRed: 0.88, green: 0.31, blue: 0.20, alpha: 1), to: scene)
        addLines(travelVertices, color: NSColor(calibratedRed: 0.48, green: 0.53, blue: 0.58, alpha: 0.7), to: scene)

        let minX = moves.reduce(Float.infinity) { min($0, min(Float($1.start.x), Float($1.end.x))) }
        let maxX = moves.reduce(-Float.infinity) { max($0, max(Float($1.start.x), Float($1.end.x))) }
        let minY = moves.reduce(Float.infinity) { min($0, min(Float($1.start.z), Float($1.end.z))) }
        let maxY = moves.reduce(-Float.infinity) { max($0, max(Float($1.start.z), Float($1.end.z))) }
        let minZ = moves.reduce(Float.infinity) { min($0, min(Float($1.start.y), Float($1.end.y))) }
        let maxZ = moves.reduce(-Float.infinity) { max($0, max(Float($1.start.y), Float($1.end.y))) }
        let center = SCNVector3((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2)
        let extent = max(maxX - minX, max(maxY - minY, maxZ - minZ))
        let distance = max(extent * 1.8, 40)

        let camera = SCNCamera()
        camera.zNear = 0.1
        camera.zFar = Double(distance * 10)
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        let cameraDistance = CGFloat(distance)
        let cameraX = center.x + cameraDistance * 0.8
        let cameraY = center.y + cameraDistance * 0.8
        let cameraZ = center.z + cameraDistance * 1.2
        cameraNode.position = SCNVector3(cameraX, cameraY, cameraZ)
        cameraNode.look(at: center)
        scene.rootNode.addChildNode(cameraNode)

        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 500
        scene.rootNode.addChildNode(ambientLight)

        return scene
    }

    private func addLines(_ vertices: [SCNVector3], color: NSColor, to scene: SCNScene) {
        guard !vertices.isEmpty else { return }
        let indices = (0..<vertices.count).map(Int32.init)
        let indexData = indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .line,
            primitiveCount: vertices.count / 2,
            bytesPerIndex: MemoryLayout<Int32>.size
        )
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .constant
        geometry.materials = [material]
        scene.rootNode.addChildNode(SCNNode(geometry: geometry))
    }
}
