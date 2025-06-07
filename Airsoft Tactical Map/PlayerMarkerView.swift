//
//  PlayerMarkerView.swift
//  Airsoft Tactical Map
//
//  Created by Jaroslavs Krots on 05/06/2025.
//

import SwiftUI

struct PlayerMarkerView: View {
    let player: Player
    let isCurrentUser: Bool
    let currentUserTeamId: String?
    let teams: [Team]
    
    // Better team color logic using actual team data
    private var teamColor: Color {
        guard let teamId = player.teamId,
              let team = teams.first(where: { $0.id == teamId }) else {
            return isCurrentUser ? .blue : .gray
        }
        return team.swiftUIColor
    }
    
    // Determine if this player is an ally (same team as current user)
    private var isAlly: Bool {
        guard let currentTeam = currentUserTeamId,
              let playerTeam = player.teamId else {
            return false
        }
        return currentTeam == playerTeam && !isCurrentUser
    }
    
    // Determine if this player is an enemy (different team from current user)
    private var isEnemy: Bool {
        guard let currentTeam = currentUserTeamId,
              let playerTeam = player.teamId else {
            return false
        }
        return currentTeam != playerTeam
    }
    
    private var borderColor: Color {
        if isCurrentUser {
            return .white
        } else if isAlly {
            return .green // Green border for allies
        } else if isEnemy {
            return .red // Red border for enemies
        } else {
            return .black // Default for unassigned
        }
    }
    
    var body: some View {
        ZStack {
            // Outer border with ally/enemy indication
            Circle()
                .fill(borderColor)
                .frame(width: 32, height: 32)
            
            // Inner circle with team color
            Circle()
                .fill(teamColor)
                .frame(width: 28, height: 28)
            
            // Player indicator
            if isCurrentUser {
                // Conal radar-like direction pointer (similar to Apple Maps)
                ConalDirectionPointer(heading: player.location?.heading ?? 0)
            } else {
                // Player initial or icon
                Text(String(player.name.prefix(1).uppercased()))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
            }
            
            // Name label with team-appropriate background
            Text(player.name)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(teamColor.opacity(0.6), lineWidth: 1)
                        )
                )
                .offset(y: 22)
        }
    }
}

// Conal radar-like direction pointer similar to Apple Maps
struct ConalDirectionPointer: View {
    let heading: Double
    
    var body: some View {
        ZStack {
            // Main directional cone
            Path { path in
                let center = CGPoint(x: 12, y: 12)
                let radius: CGFloat = 8
                let coneAngle: CGFloat = 45 // degrees
                let halfCone = coneAngle / 2
                
                // Start from center
                path.move(to: center)
                
                // Draw cone arc
                path.addArc(
                    center: center,
                    radius: radius,
                    startAngle: Angle(degrees: -halfCone),
                    endAngle: Angle(degrees: halfCone),
                    clockwise: false
                )
                
                // Close the path back to center
                path.closeSubpath()
            }
            .fill(Color.white.opacity(0.9))
            .frame(width: 24, height: 24)
            .rotationEffect(.degrees(heading - 90)) // Adjust for SwiftUI coordinate system
            
            // Small center dot
            Circle()
                .fill(Color.white)
                .frame(width: 4, height: 4)
            
            // Outer pulse ring for better visibility
            Circle()
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                .frame(width: 20, height: 20)
        }
    }
}

#Preview {
    let sampleTeams = [
        Team(id: "team1", name: "Team Alpha", color: "red"),
        Team(id: "team2", name: "Team Bravo", color: "blue")
    ]
    
    VStack(spacing: 20) {
        // Current user
        PlayerMarkerView(
            player: Player(name: "You", teamId: "team1", location: PlayerLocation(latitude: 0, longitude: 0, heading: 45)),
            isCurrentUser: true,
            currentUserTeamId: "team1",
            teams: sampleTeams
        )
        
        // Ally
        PlayerMarkerView(
            player: Player(name: "Ally", teamId: "team1"),
            isCurrentUser: false,
            currentUserTeamId: "team1",
            teams: sampleTeams
        )
        
        // Enemy
        PlayerMarkerView(
            player: Player(name: "Enemy", teamId: "team2"),
            isCurrentUser: false,
            currentUserTeamId: "team1",
            teams: sampleTeams
        )
        
        // Unassigned
        PlayerMarkerView(
            player: Player(name: "Unknown"),
            isCurrentUser: false,
            currentUserTeamId: "team1",
            teams: sampleTeams
        )
    }
    .padding()
} 