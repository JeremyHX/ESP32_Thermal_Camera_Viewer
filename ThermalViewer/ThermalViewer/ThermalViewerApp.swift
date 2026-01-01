import SwiftUI

@main
struct ThermalViewerApp: App {
    @State private var connectionManager = ConnectionManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(connectionManager)
        }
    }
}

struct ContentView: View {
    @Environment(ConnectionManager.self) private var connectionManager

    var body: some View {
        if connectionManager.isConnected {
            ThermalViewerView()
        } else {
            ConnectionView()
        }
    }
}
