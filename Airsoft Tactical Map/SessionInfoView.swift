//
//  SessionInfoView.swift
//  Airsoft Tactical Map
//
//  Created by Jaroslavs Krots on 05/06/2025.
//

import SwiftUI

struct SessionInfoView<GameManager: GameManagerProtocol>: View {
    @ObservedObject var gameManager: GameManager
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            ZStack {
                // Dark background
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 20) {
                    // Session Header
                    VStack(spacing: 16) {
                        HStack {
                            Image(systemName: "shield.lefthalf.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.green)
                            
                            Text("OPERATION STATUS")
                                .font(.system(size: 22, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                        }
                        
                        if let sessionCode = gameManager.sessionCode {
                            VStack(spacing: 8) {
                                Text("OPERATION CODE")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.gray)
                                
                                Text(sessionCode)
                                    .font(.system(size: 28, weight: .black, design: .monospaced))
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background(Color.black.opacity(0.3))
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.green.opacity(0.5), lineWidth: 2)
                                    )
                                    .shadow(color: .green.opacity(0.3), radius: 5)
                            }
                        }
                    }
                    .padding(.top)
                    
                    // Connection Status
                    HStack(spacing: 8) {
                        Image(systemName: gameManager.isConnected ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                            .foregroundColor(gameManager.isConnected ? .green : .red)
                            .font(.title2)
                        
                        Text(gameManager.isConnected ? "NETWORK ONLINE" : "NETWORK OFFLINE")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(gameManager.isConnected ? .green : .red)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke((gameManager.isConnected ? Color.green : Color.red).opacity(0.3), lineWidth: 1)
                    )
                    
                    // Debug Status (for TestFlight troubleshooting)
                    if let multipeerManager = gameManager as? MultipeerGameManager {
                        VStack(spacing: 4) {
                            Text("DEBUG STATUS:")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.yellow)
                            
                            Text(multipeerManager.debugStatus)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(.yellow)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.4))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
                        )
                    }
                    
                    // Players List
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "person.2.fill")
                                .foregroundColor(.green)
                                .font(.title3)
                            
                            Text("OPERATIVES [\(totalPlayerCount)]")
                                .font(.system(size: 18, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                // Current user
                                if let currentUser = gameManager.currentUser {
                                    TacticalPlayerRowView(
                                        player: currentUser,
                                        isCurrentUser: true,
                                        isHost: gameManager.isHost,
                                        teams: gameManager.gameSession?.teams ?? []
                                    )
                                }
                                
                                // Other players
                                ForEach(gameManager.otherPlayers, id: \.id) { player in
                                    TacticalPlayerRowView(
                                        player: player,
                                        isCurrentUser: false,
                                        isHost: gameManager.isHost,
                                        teams: gameManager.gameSession?.teams ?? []
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    
                    Spacer()
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        if gameManager.isHost {
                            Button(action: {
                                gameManager.endSession()
                                presentationMode.wrappedValue.dismiss()
                            }) {
                                HStack {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title2)
                                    Text("TERMINATE OPERATION")
                                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.red, Color.red.opacity(0.8)]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(12)
                                .shadow(color: .red.opacity(0.3), radius: 3)
                            }
                        } else {
                            Button(action: {
                                gameManager.endSession()
                                presentationMode.wrappedValue.dismiss()
                            }) {
                                HStack {
                                    Image(systemName: "arrow.left.circle.fill")
                                        .font(.title2)
                                    Text("LEAVE OPERATION")
                                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.orange, Color.orange.opacity(0.8)]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(12)
                                .shadow(color: .orange.opacity(0.3), radius: 3)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom)
                }
            }
            .navigationBarHidden(true)
            .overlay(
                // Close button
                VStack {
                    HStack {
                        Spacer()
                        Button(action: {
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.gray)
                                .background(
                                    Circle()
                                        .fill(Color.black.opacity(0.6))
                                        .frame(width: 32, height: 32)
                                )
                        }
                        .padding(.trailing, 20)
                        .padding(.top, 20)
                    }
                    Spacer()
                }
            )
        }
        .preferredColorScheme(.dark)
    }
    
    private var totalPlayerCount: Int {
        1 + gameManager.otherPlayers.count
    }
}

struct TacticalPlayerRowView: View {
    let player: Player
    let isCurrentUser: Bool
    let isHost: Bool
    let teams: [Team]
    
    private var teamName: String {
        guard let teamId = player.teamId,
              let team = teams.first(where: { $0.id == teamId }) else {
            return "UNASSIGNED"
        }
        return team.name
    }
    
    private var teamColor: Color {
        guard let teamId = player.teamId,
              let team = teams.first(where: { $0.id == teamId }) else {
            return .gray
        }
        return team.swiftUIColor
    }
    
    var body: some View {
        HStack {
            // Player status indicator
            VStack {
                Circle()
                    .fill(teamColor)
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
                
                // Connection pulse
                if player.location != nil {
                    Circle()
                        .fill(Color.green.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .scaleEffect(1.2)
                        .animation(
                            Animation.easeInOut(duration: 1.0)
                                .repeatForever(autoreverses: true),
                            value: UUID()
                        )
                }
            }
            
            // Player info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(player.name)
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                    
                    if isCurrentUser {
                        Text("[YOU]")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(4)
                    }
                    
                    if player.isHost {
                        Text("CMD")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gold)
                            .cornerRadius(4)
                    }
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "shield.lefthalf.fill")
                        .foregroundColor(teamColor)
                        .font(.caption)
                    
                    Text(teamName)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
            
            // Connection status
            VStack(spacing: 4) {
                if let location = player.location {
                    Image(systemName: "location.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                    
                    Text("GPS")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "location.slash")
                        .foregroundColor(.red)
                        .font(.title3)
                    
                    Text("NO GPS")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.red)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color.black.opacity(0.3))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(teamColor.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview {
    SessionInfoView<MultipeerGameManager>(gameManager: MultipeerGameManager())
} 