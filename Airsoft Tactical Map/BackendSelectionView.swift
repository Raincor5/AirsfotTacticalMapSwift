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
                
                VStack(spacing: 40) {
                    Spacer()
                    
                    // Title
                    VStack(spacing: 10) {
                        Image(systemName: "gear")
                            .font(.system(size: 50))
                            .foregroundColor(.green)
                        
                        Text("SELECT CONNECTION MODE")
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                    }
                    
                    VStack(spacing: 20) {
                        // MultipeerConnectivity Option
                        Button(action: onMultipeerSelected) {
                            VStack(spacing: 16) {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 40))
                                    .foregroundColor(.blue)
                                
                                Text("PEER-TO-PEER")
                                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                
                                Text("Direct device connection\nIdeal for real devices\nNo server required")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                                
                                Text("RECOMMENDED FOR REAL DEVICES")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.blue)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(20)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.blue.opacity(0.5), lineWidth: 2)
                            )
                        }
                        
                        // WebSocket Option
                        Button(action: onWebSocketSelected) {
                            VStack(spacing: 16) {
                                Image(systemName: "server.rack")
                                    .font(.system(size: 40))
                                    .foregroundColor(.orange)
                                
                                Text("SERVER-BASED")
                                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                
                                Text("WebSocket connection\nWorks in simulator\nRequires backend server")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                                
                                Text("RECOMMENDED FOR SIMULATOR")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.orange)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(20)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.orange.opacity(0.5), lineWidth: 2)
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Instructions
                    VStack(spacing: 8) {
                        Text("CONNECTION GUIDE")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                        
                        VStack(spacing: 4) {
                            Text("• Use PEER-TO-PEER for real iPhone/iPad devices")
                            Text("• Use SERVER-BASED for iOS Simulator testing")
                            Text("• Server must be running on port 3001")
                        }
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer()
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    BackendSelectionView(
        onMultipeerSelected: {},
        onWebSocketSelected: {}
    )
} 