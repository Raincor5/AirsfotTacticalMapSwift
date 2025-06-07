//
//  TeamManagerView.swift
//  Airsoft Tactical Map
//
//  Created by Jaroslavs Krots on 05/06/2025.
//

import SwiftUI

struct TeamManagerView<GameManager: GameManagerProtocol>: View {
    @ObservedObject var gameManager: GameManager
    @Environment(\.presentationMode) var presentationMode
    @State private var debugAlert: String = ""
    @State private var showingDebugAlert = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Dark background
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        VStack(spacing: 8) {
                            Image(systemName: "person.3.sequence.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.green)
                            
                            Text("TEAM MANAGEMENT")
                                .font(.system(size: 24, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                            
                            Text("Assign operatives to teams")
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundColor(.gray)
                        }
                        .padding(.top, 20)
                        
                        if let session = gameManager.gameSession {
                            LazyVStack(spacing: 16) {
                                ForEach(session.teams) { team in
                                    TacticalTeamSectionView(
                                        team: team,
                                        players: playersForTeam(team.id),
                                        allPlayers: allPlayers,
                                        onAssignPlayer: { playerId in
                                            gameManager.assignPlayerToTeam(playerId, teamId: team.id)
                                        }
                                    )
                                }
                                
                                // Unassigned players
                                if !unassignedPlayers.isEmpty {
                                    TacticalTeamSectionView(
                                        team: Team(id: "unassigned", name: "UNASSIGNED", color: "gray"),
                                        players: unassignedPlayers,
                                        allPlayers: allPlayers,
                                        onAssignPlayer: { _ in }
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                        } else {
                            VStack(spacing: 16) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 40))
                                    .foregroundColor(.red)
                                
                                Text("NO SESSION DATA")
                                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                                    .foregroundColor(.red)
                                
                                Text("Cannot load session information")
                                    .font(.system(size: 14, design: .monospaced))
                                    .foregroundColor(.gray)
                            }
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.red.opacity(0.3), lineWidth: 1)
                            )
                            .padding(.horizontal, 20)
                        }
                        
                        Spacer(minLength: 100)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: HStack {
                    Image(systemName: "shield.lefthalf.fill")
                        .foregroundColor(.green)
                    Text("TACTICAL OPS")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                },
                trailing: Button("DONE") {
                    presentationMode.wrappedValue.dismiss()
                }
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(.green)
            )
        }
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowDebugAlert"))) { notification in
            if let message = notification.object as? String {
                debugAlert = message
                showingDebugAlert = true
            }
        }
        .alert("Debug Info", isPresented: $showingDebugAlert) {
            Button("OK") { }
        } message: {
            Text(debugAlert)
        }
    }
    
    private var allPlayers: [Player] {
        var players: [Player] = []
        if let currentUser = gameManager.currentUser {
            players.append(currentUser)
        }
        players.append(contentsOf: gameManager.otherPlayers)
        return players
    }
    
    private var unassignedPlayers: [Player] {
        allPlayers.filter { $0.teamId == nil }
    }
    
    private func playersForTeam(_ teamId: String) -> [Player] {
        allPlayers.filter { $0.teamId == teamId }
    }
}

struct TacticalTeamSectionView: View {
    let team: Team
    let players: [Player]
    let allPlayers: [Player]
    let onAssignPlayer: (String) -> Void
    
    @State private var showingPlayerPicker = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Team Header
            HStack {
                // Team indicator
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(team.swiftUIColor)
                        .frame(width: 20, height: 20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                    
                    Text(team.name)
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    
                    Text("[\(players.count)]")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                // Add player button
                if team.id != "unassigned" && !availablePlayers.isEmpty {
                    Button(action: {
                        showingPlayerPicker = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                            Text("ADD")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                        }
                        .foregroundColor(.green)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.green.opacity(0.3), lineWidth: 1)
                        )
                    }
                }
            }
            
            // Players in team
            if players.isEmpty {
                HStack {
                    Image(systemName: "person.slash")
                        .foregroundColor(.gray)
                        .font(.title3)
                    
                    Text("NO OPERATIVES ASSIGNED")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            } else {
                VStack(spacing: 8) {
                    ForEach(players, id: \.id) { player in
                        HStack {
                            // Player status indicator
                            Circle()
                                .fill(player.isHost ? Color.gold : Color.green)
                                .frame(width: 8, height: 8)
                            
                            Text(player.name)
                                .font(.system(size: 16, weight: .medium, design: .monospaced))
                                .foregroundColor(.white)
                            
                            if player.isHost {
                                Text("CMD")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.gold)
                                    .cornerRadius(4)
                            }
                            
                            Spacer()
                            
                            // Connection status
                            Image(systemName: "wifi")
                                .foregroundColor(.green)
                                .font(.caption)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(team.swiftUIColor.opacity(0.3), lineWidth: 1)
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color.black.opacity(0.3))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(team.swiftUIColor.opacity(0.4), lineWidth: 2)
        )
        .confirmationDialog("Assign Operative to \(team.name)", isPresented: $showingPlayerPicker, titleVisibility: .visible) {
            ForEach(availablePlayers, id: \.id) { player in
                Button(player.name) {
                    onAssignPlayer(player.id)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Select an operative to assign to this team.")
        }
    }
    
    private var availablePlayers: [Player] {
        allPlayers.filter { player in
            player.teamId != team.id
        }
    }
}

extension Color {
    static let gold = Color(red: 1.0, green: 0.843, blue: 0.0)
}

#Preview {
    TeamManagerView<MultipeerGameManager>(gameManager: MultipeerGameManager())
} 