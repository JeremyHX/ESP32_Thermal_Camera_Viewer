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
    @State private var selectedTab: AppTab = .simple

    var body: some View {
        if connectionManager.isConnected {
            MainTabView(selectedTab: $selectedTab)
        } else {
            ConnectionView(initialTab: $selectedTab)
        }
    }
}

enum AppTab: String, CaseIterable {
    case simple = "Simple"
    case advanced = "Advanced"
}

struct MainTabView: View {
    @Environment(ConnectionManager.self) private var connectionManager
    @Binding var selectedTab: AppTab

    var body: some View {
        TabView(selection: $selectedTab) {
            SimpleView()
                .tabItem {
                    Label("Simple", systemImage: "gauge.with.dots.needle.33percent")
                }
                .tag(AppTab.simple)

            ThermalViewerView()
                .tabItem {
                    Label("Advanced", systemImage: "camera.viewfinder")
                }
                .tag(AppTab.advanced)
        }
        .onChange(of: selectedTab) { oldTab, newTab in
            // Enable/disable frame stream based on tab
            if newTab == .advanced {
                connectionManager.setFrameStreamEnabled(true)
            } else {
                connectionManager.setFrameStreamEnabled(false)
            }
        }
    }
}
