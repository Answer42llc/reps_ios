//
//  SelfLieApp.swift
//  SelfLie
//
//  Created by lw on 7/18/25.
//

import SwiftUI
import CoreData
import UserNotifications
import RevenueCat

@main
struct SelfLieApp: App {
    let persistenceController = PersistenceController.shared
    @State private var cloudSyncService: CloudSyncService
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let service = CloudSyncService(
            context: persistenceController.container.viewContext
        )
        _cloudSyncService = State(initialValue: service)

        //初始化 RevenueCat
        Purchases.logLevel = .debug
        Purchases.configure(withAPIKey: "appl_SbSlEYBLSPjipOgJiHXhsegMbXo")
        Purchases.proxyURL = URL(string: "https://api.rc-backup.com/")!
        // 获取 serif 风格的大标题字体
        if let descriptor = UIFontDescriptor
            .preferredFontDescriptor(withTextStyle: .largeTitle)
            .withDesign(.serif)?
            .withSymbolicTraits(.traitBold) {
            
            let serifFont = UIFont(descriptor: descriptor, size: 34)

            let appearance = UINavigationBarAppearance()
            
            appearance.configureWithTransparentBackground()


            appearance.largeTitleTextAttributes = [
                .font: serifFont,
                .foregroundColor: UIColor.label
            ]

            // 可选：也自定义普通 title 字体
            if let titleDescriptor = UIFontDescriptor
                .preferredFontDescriptor(withTextStyle: .headline)
                .withDesign(.serif) {
                let titleFont = UIFont(descriptor: titleDescriptor, size: 17)
                appearance.titleTextAttributes = [
                    .font: titleFont,
                    .foregroundColor: UIColor.label
                ]
            }

            // 应用样式
            let navBar = UINavigationBar.appearance()
            navBar.standardAppearance = appearance
            navBar.scrollEdgeAppearance = appearance
            navBar.compactAppearance = appearance
        }

        Task {
            NotificationManager.shared.registerCategories()
            if UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
                NotificationManager.shared.scheduleDailyNotifications()
            }
        }

        // Set notification center delegate
        UNUserNotificationCenter.current().delegate = NotificationManager.shared
    }


    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environment(cloudSyncService)
                .fontDesign(.serif)
        }
        .onChange(of: scenePhase) { newPhase in
            guard newPhase == .active else { return }
            Task { @MainActor in
                cloudSyncService.requestFullSync()
            }
        }
    }
}
