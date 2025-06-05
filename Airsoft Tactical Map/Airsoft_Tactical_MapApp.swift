//
//  Airsoft_Tactical_MapApp.swift
//  Airsoft Tactical Map
//
//  Created by Jaroslavs Krots on 05/06/2025.
//

import SwiftUI

@main
struct Airsoft_Tactical_MapApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
