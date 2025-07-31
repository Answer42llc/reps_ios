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
            .withDesign(.serif)?
            .withSymbolicTraits(.traitBold) {
            
            let serifFont = UIFont(descriptor: descriptor, size: 34)

            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            
            appearance.backgroundColor = UIColor(red: 0.976, green: 0.976, blue: 0.976, alpha: 1.0) // #f9f9f9
            
            // 去除底部边框（阴影）
            appearance.shadowColor = .clear


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
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .fontDesign(.serif)
        }
    }
}
