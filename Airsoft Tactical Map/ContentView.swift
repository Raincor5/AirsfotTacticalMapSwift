//
//  ContentView.swift
//  Airsoft Tactical Map
//
//  Created by Jaroslavs Krots on 05/06/2025.
//

import SwiftUI
import MapKit

struct ContentView: View {
    @StateObject private var multipeerGameManager = MultipeerGameManager()
    @StateObject private var webSocketGameManager = WebSocketGameManager()
    @StateObject private var locationManager = LocationManager()
    @State private var useWebSocket = false
    @State private var showingBackendSelection = true
    
    var body: some View {
        Group {
            if showingBackendSelection {
                BackendSelectionView(
                    onMultipeerSelected: {
                        useWebSocket = false
                        showingBackendSelection = false
                    },
                    onWebSocketSelected: {
                        useWebSocket = true
                        showingBackendSelection = false
                    }
                )
            } else if useWebSocket && webSocketGameManager.gameSession == nil || !useWebSocket && multipeerGameManager.gameSession == nil {
                if useWebSocket {
                    SetupView(gameManager: webSocketGameManager)
                } else {
                    SetupView(gameManager: multipeerGameManager)
                }
            } else {
                if useWebSocket {
                    GameMapView(
                        gameManager: webSocketGameManager,
                        locationManager: locationManager
                    )
                } else {
                    GameMapView(
                        gameManager: multipeerGameManager,
                        locationManager: locationManager
                    )
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            locationManager.requestLocationPermission()
        }
    }
}

#Preview {
    ContentView()
}
