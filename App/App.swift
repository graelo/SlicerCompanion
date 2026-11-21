import SwiftUI

@main
struct SlicerCompanionApp: App {
    var body: some Scene {
        DocumentGroup(viewing: GCodeDocument.self) { configuration in
            ContentView(document: configuration.document)
        }
    }
}
