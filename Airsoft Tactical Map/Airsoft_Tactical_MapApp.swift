//
//  Airsoft_Tactical_MapApp.swift
//  Airsoft Tactical Map
//
//  Created by Jaroslavs Krots on 05/06/2025.
//

import SwiftUI
import UIKit

@main
struct Airsoft_Tactical_MapApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate: AppDelegate
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .onAppear {
                    // Request push notification permission on app launch
                    PushNotificationManager.shared.requestPermission()
                }
        }
    }
}
