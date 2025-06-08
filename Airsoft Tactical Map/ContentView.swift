//
//  ContentView.swift
//  Airsoft Tactical Map
//
//  Created by Jaroslavs Krots on 05/06/2025.
//

import SwiftUI
import MapKit

struct ContentView: View {
    @StateObject private var webSocketGameManager = WebSocketGameManager()
    @StateObject private var locationManager = LocationManager()
    
    var body: some View {
        Group {
            if webSocketGameManager.gameSession == nil {
                SetupView(gameManager: webSocketGameManager)
            } else {
                GameMapView(
                    gameManager: webSocketGameManager,
                    locationManager: locationManager,
                    networkManager: webSocketGameManager.networkManager
                )
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            locationManager.requestLocationPermission()
            webSocketGameManager.networkManager.startInterpolation()
        }
        .environmentObject(webSocketGameManager.networkManager)
    }
}
