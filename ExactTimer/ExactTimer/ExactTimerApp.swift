import SwiftUI
import SwiftData

@main
struct ExactTimerApp: App {
    @StateObject private var ntpService = NTPService.shared
    @State private var showSplash = true

    // SwiftData model container
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Watch.self,
            WatchReading.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        // Configure navigation bar appearance
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .black
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance

        // Configure tab bar appearance
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = .black
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                MainTabView()
                    .environmentObject(ntpService)

                if showSplash {
                    SplashScreenView()
                        .zIndex(1)
                        .onAppear {
                            // Dismiss splash screen after 3 seconds
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    showSplash = false
                                }
                            }
                        }
                }
            }
        }
        .modelContainer(sharedModelContainer)
    }
}

/// Main tab view for navigating between features
struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ContentView()
                .tabItem {
                    Label("Time", systemImage: "clock.fill")
                }
                .tag(0)

            WatchListView()
                .tabItem {
                    Label("Accuracy", systemImage: "gauge.with.needle.fill")
                }
                .tag(1)
        }
        .tint(.terminalGreen)
    }
}

#Preview {
    MainTabView()
        .environmentObject(NTPService.shared)
        .modelContainer(for: [Watch.self, WatchReading.self], inMemory: true)
}
