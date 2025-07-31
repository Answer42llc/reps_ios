//
//  SelfLieApp.swift
//  SelfLie
//
//  Created by lw on 7/18/25.
//

import SwiftUI
import CoreData

@main
struct SelfLieApp: App {
    let persistenceController = PersistenceController.shared
    init() {
        // 获取 serif 风格的大标题字体
        if let descriptor = UIFontDescriptor
            .preferredFontDescriptor(withTextStyle: .largeTitle)
            .withDesign(.serif) {
            
            let serifFont = UIFont(descriptor: descriptor, size: 34)

            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
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

            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .fontDesign(.serif)
        }
    }
}
