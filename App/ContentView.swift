import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            // Your logo (from Assets)
            Image("Logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 120, height: 120)
                .padding(.top, 32)

            // App name and version
            Text("Slicer Companion")
                .font(.title)
                .fontWeight(.bold)

            // Supported formats
            Text("3MF / GCode / BGCode")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Version info
            Text(
                "Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")"
            )
            .font(.footnote)
            .foregroundColor(.gray)

            // Developer info
            Text("Made with ❤️ by graelo")
                .font(.footnote)
                .foregroundColor(.gray)
                .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ContentView: View {

    var body: some View {
        VStack {
            AboutView()
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
