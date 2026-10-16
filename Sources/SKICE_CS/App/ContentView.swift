import SwiftUI

public struct ContentView: View {
    @State private var selectedTab: AppTab = .profile
    @State private var sessionStore = SteamSessionStore()
    @State private var statsModel = StatsViewModel()
    @State private var authSession = SteamAuthSession()

    public init() {}

    public var body: some View {
        TabView(selection: $selectedTab) {
            // TAB 1: Home dashboard
            NavigationStack {
                ProfileView(
                    sessionStore: sessionStore,
                    statsModel: statsModel,
                    authSession: authSession,
                    selectedTab: $selectedTab
                )
            }
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }
            .tag(AppTab.profile)

            // TAB 2: CS2 Inventory
            NavigationStack {
                if let steamID64 = sessionStore.storedSteamID64, !steamID64.isEmpty {
                    InventoryView(steamID64: steamID64, authSession: authSession)
                } else {
                    missingSteamIDPlaceholder
                }
            }
            .tabItem {
                Label("Inventory", systemImage: "shippingbox.fill")
            }
            .tag(AppTab.inventory)

            // TAB 3: CS2 & FACEIT Stats
            NavigationStack {
                StatsDashboardView(
                    steamID64: sessionStore.storedSteamID64,
                    viewModel: statsModel,
                    selectedTab: $selectedTab
                )
            }
            .tabItem {
                Label("Stats", systemImage: "chart.bar.doc.horizontal.fill")
            }
            .tag(AppTab.stats)

            // TAB 4: Settings
            NavigationStack {
                SettingsView(
                    sessionStore: sessionStore,
                    statsModel: statsModel,
                    authSession: authSession
                )
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .tag(AppTab.settings)
        }
        .tint(AppTheme.Colors.csOrange)
        .preferredColorScheme(.dark)
    }

    // MARK: - Subviews

    private var missingSteamIDPlaceholder: some View {
        ZStack {
            AppTheme.Colors.oledBlack
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "person.badge.key.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(AppTheme.Colors.csOrange)

                Text("STEAMID64 NOT CONFIGURED")
                    .font(AppTheme.Fonts.headerTitle)
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text("Please save your 17-digit SteamID64 in Settings to fetch your public CS2 inventory.")
                    .font(AppTheme.Fonts.bodyRegular)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button {
                    selectedTab = .settings
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "gearshape.fill")
                        Text("OPEN SETTINGS")
                    }
                    .padding(.horizontal, 20)
                }
                .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.Colors.csOrange))
                .frame(maxWidth: 260)
            }
        }
        .navigationTitle("CS2 Inventory")
        .navigationBarTitleDisplayMode(.inline)
    }
}
