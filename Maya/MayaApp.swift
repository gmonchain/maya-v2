//
//  MayaApp.swift
//  Maya
//
//  Created by Ronaldo Avalos on 16/05/26.
//

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let mayaProject = UTType(exportedAs: "ai.maya.project")
}

@main
struct MayaApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project") {
                    NotificationCenter.default.post(name: .newProject, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
                
                Button("Open Project...") {
                    NotificationCenter.default.post(name: .openProject, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
                
                Divider()
                
                Button("Save Project") {
                    NotificationCenter.default.post(name: .saveProject, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let newProject = Notification.Name("newProject")
    static let openProject = Notification.Name("openProject")
    static let saveProject = Notification.Name("saveProject")
}
