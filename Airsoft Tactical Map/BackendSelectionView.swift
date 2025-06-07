//
//  BackendSelectionView.swift
//  Airsoft Tactical Map
//
//  Created by Jaroslavs Krots on 05/06/2025.
//

import SwiftUI

struct BackendSelectionView: View {
    let onMultipeerSelected: () -> Void
    let onWebSocketSelected: () -> Void
    let webSocketManager: WebSocketGameManager
    
    @State private var showingServerConfiguration = false
    
    // Connection status computed properties
    private var connectionIcon: String {
        switch webSocketManager.connectionState {
        case .connected:
            return "checkmark.circle.fill"
        case .connecting, .reconnecting:
            return "clock.circle.fill"
        case .disconnected:
            return "circle"
        case .failed:
            return "xmark.circle.fill"
        }
    }
    
    private var connectionColor: Color {
        switch webSocketManager.connectionState {
        case .connected:
            return .green
        case .connecting, .reconnecting:
            return .orange
        case .disconnected:
            return .gray
        case .failed:
            return .red
        }
    }
    
    private var connectionText: String {
        switch webSocketManager.connectionState {
        case .connected:
            return "CONNECTED"
        case .connecting:
            return "CONNECTING"
        case .reconnecting:
            return "RECONNECTING"
        case .disconnected:
            return "DISCONNECTED"
        case .failed(let message):
            return "FAILED: \(message)"
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Dark gradient background
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black,
                        Color.gray.opacity(0.3),
                        Color.black
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: geometry.size.height < 700 ? 20 : 40) {
                        Spacer(minLength: geometry.size.height < 700 ? 20 : 40)
                    
                        // Title - more compact on smaller screens
                        VStack(spacing: geometry.size.height < 700 ? 8 : 10) {
                        Image(systemName: "gear")
                                .font(.system(size: geometry.size.height < 700 ? 35 : 50))
                            .foregroundColor(.green)
                        
                            Text(geometry.size.height < 700 ? "CONNECTION MODE" : "SELECT CONNECTION MODE")
                                .font(.system(size: geometry.size.height < 700 ? 18 : 24, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                    }
                    
                        VStack(spacing: geometry.size.height < 700 ? 12 : 20) {
                        // MultipeerConnectivity Option
                        Button(action: onMultipeerSelected) {
                                VStack(spacing: geometry.size.height < 700 ? 8 : 16) {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                        .font(.system(size: geometry.size.height < 700 ? 30 : 40))
                                    .foregroundColor(.blue)
                                
                                Text("PEER-TO-PEER")
                                        .font(.system(size: geometry.size.height < 700 ? 16 : 18, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                
                                    Text(geometry.size.height < 700 ? "Direct connection\nReal devices only" : "Direct device connection\nIdeal for real devices\nNo server required")
                                        .font(.system(size: geometry.size.height < 700 ? 11 : 12, weight: .medium, design: .monospaced))
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                                
                                Text("RECOMMENDED FOR REAL DEVICES")
                                        .font(.system(size: geometry.size.height < 700 ? 9 : 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.blue)
                            }
                            .frame(maxWidth: .infinity)
                                .padding(geometry.size.height < 700 ? 16 : 20)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.blue.opacity(0.5), lineWidth: 2)
                            )
                        }
                        
                        // WebSocket Option
                            VStack(spacing: geometry.size.height < 700 ? 8 : 12) {
                        Button(action: onWebSocketSelected) {
                                    VStack(spacing: geometry.size.height < 700 ? 8 : 16) {
                                Image(systemName: "server.rack")
                                            .font(.system(size: geometry.size.height < 700 ? 30 : 40))
                                    .foregroundColor(.orange)
                                
                                Text("SERVER-BASED")
                                            .font(.system(size: geometry.size.height < 700 ? 16 : 18, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                
                                        Text(geometry.size.height < 700 ? "WebSocket server\nSimulator & real devices" : "WebSocket connection\nWorks in simulator\nRequires backend server")
                                            .font(.system(size: geometry.size.height < 700 ? 11 : 12, weight: .medium, design: .monospaced))
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                                
                                        // Server Status
                                        HStack(spacing: 6) {
                                            Image(systemName: connectionIcon)
                                                .foregroundColor(connectionColor)
                                                .font(.system(size: 10))
                                            
                                            Text(connectionText)
                                                .font(.system(size: geometry.size.height < 700 ? 9 : 10, weight: .medium, design: .monospaced))
                                                .foregroundColor(connectionColor)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.black.opacity(0.2))
                                        .cornerRadius(4)
                                        
                                Text("RECOMMENDED FOR SIMULATOR")
                                            .font(.system(size: geometry.size.height < 700 ? 9 : 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.orange)
                            }
                            .frame(maxWidth: .infinity)
                                    .padding(geometry.size.height < 700 ? 16 : 20)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.orange.opacity(0.5), lineWidth: 2)
                            )
                                }
                                .disabled(webSocketManager.serverHost.isEmpty)
                                
                                // Server Configuration Button
                                Button(action: { showingServerConfiguration = true }) {
                                    HStack {
                                        Image(systemName: "gear")
                                            .font(.system(size: geometry.size.height < 700 ? 12 : 14))
                                        Text("CONFIGURE SERVER")
                                            .font(.system(size: geometry.size.height < 700 ? 11 : 12, weight: .bold, design: .monospaced))
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, geometry.size.height < 700 ? 6 : 8)
                                    .background(Color.blue.opacity(0.8))
                                    .cornerRadius(8)
                                }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                        // Instructions - simplified for smaller screens
                        if geometry.size.height >= 650 {
                    VStack(spacing: 8) {
                        Text("CONNECTION GUIDE")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                        
                        VStack(spacing: 4) {
                            Text("• Use PEER-TO-PEER for real iPhone/iPad devices")
                            Text("• Use SERVER-BASED for iOS Simulator testing")
                                    Text("• Configure server IP manually or scan QR code")
                                    Text("• Share server QR code with other team members")
                        }
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 20)
                        }
                    
                        Spacer(minLength: 20)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingServerConfiguration) {
            ServerConfigurationView(webSocketManager: webSocketManager)
        }
    }
}

#Preview {
    BackendSelectionView(
        onMultipeerSelected: {},
        onWebSocketSelected: {},
        webSocketManager: WebSocketGameManager()
    )
} 