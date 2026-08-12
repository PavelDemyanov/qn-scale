import SwiftUI
import SwiftData

@main
struct LibraApp: App {
    @State private var scale = ScaleManager()
    @State private var profileStore = ProfileStore()
    @State private var health = HealthStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(scale)
                .environment(profileStore)
                .environment(health)
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: WeighIn.self)
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            WeighView()
                .tabItem { Label("Взвешивание", systemImage: "scalemass") }
            HistoryView()
                .tabItem { Label("История", systemImage: "chart.xyaxis.line") }
            ProfileView()
                .tabItem { Label("Профиль", systemImage: "person") }
        }
    }
}
