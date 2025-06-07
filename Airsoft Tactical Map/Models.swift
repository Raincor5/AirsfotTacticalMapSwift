//
//  Models.swift
//  Airsoft Tactical Map
//
//  Created by Jaroslavs Krots on 05/06/2025.
//

import Foundation
import CoreLocation
import SwiftUI

// MARK: - Player Model
struct Player: Codable, Identifiable {
    let id: String
    var name: String
    var teamId: String?
    var location: PlayerLocation?
    var isHost: Bool
    
    init(id: String = UUID().uuidString, name: String, teamId: String? = nil, location: PlayerLocation? = nil, isHost: Bool = false) {
        self.id = id
        self.name = name
        self.teamId = teamId
        self.location = location
        self.isHost = isHost
    }
}

// MARK: - Player Location
struct PlayerLocation: Codable {
    let latitude: Double
    let longitude: Double
    let heading: Double?
    let timestamp: Date
    
    init(latitude: Double, longitude: Double, heading: Double? = nil, timestamp: Date = Date()) {
        self.latitude = latitude
        self.longitude = longitude
        self.heading = heading
        self.timestamp = timestamp
    }
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Team Model
struct Team: Codable, Identifiable {
    let id: String
    let name: String
    let color: String
    
    var swiftUIColor: Color {
        switch color.lowercased() {
        case "red": return .red
        case "blue": return .blue
        case "green": return .green
        case "yellow": return .yellow
        case "purple": return .purple
        case "orange": return .orange
        default: return .gray
        }
    }
}

// MARK: - Pin Model
struct Pin: Codable, Identifiable {
    let id: String
    let type: String
    let name: String
    let coordinate: PinCoordinate
    let playerId: String
    let teamId: String?
    let timestamp: Date
    
    init(id: String = UUID().uuidString, type: String, name: String, coordinate: PinCoordinate, playerId: String, teamId: String? = nil, timestamp: Date = Date()) {
        self.id = id
        self.type = type
        self.name = name
        self.coordinate = coordinate
        self.playerId = playerId
        self.teamId = teamId
        self.timestamp = timestamp
    }
}

struct PinCoordinate: Codable {
    let latitude: Double
    let longitude: Double
    
    var coreLocationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Message Model
struct GameMessage: Codable, Identifiable {
    let id: String
    let text: String
    let playerId: String
    let playerName: String
    let teamId: String?
    let timestamp: Date
    
    init(id: String = UUID().uuidString, text: String, playerId: String, playerName: String, teamId: String? = nil, timestamp: Date = Date()) {
        self.id = id
        self.text = text
        self.playerId = playerId
        self.playerName = playerName
        self.teamId = teamId
        self.timestamp = timestamp
    }
}

// MARK: - Game Session Model
struct GameSession: Codable {
    let id: String
    let code: String
    let name: String
    var players: [String: Player]
    var teams: [Team]
    var pins: [Pin]
    var messages: [GameMessage]
    let hostId: String
    let createdAt: Date
    
    init(id: String = UUID().uuidString, code: String, name: String, hostId: String, createdAt: Date = Date()) {
        self.id = id
        self.code = code
        self.name = name
        self.players = [:]
        self.teams = [
            Team(id: "team1", name: "Team Alpha", color: "red"),
            Team(id: "team2", name: "Team Bravo", color: "blue")
        ]
        self.pins = []
        self.messages = []
        self.hostId = hostId
        self.createdAt = createdAt
    }
}

// MARK: - Pin Types
enum PinType: String, CaseIterable {
    case enemy = "enemy"
    case friendly = "friendly"
    case objective = "objective"
    case hazard = "hazard"
    case waypoint = "waypoint"
    case cover = "cover"
    
    var displayName: String {
        switch self {
        case .enemy: return "Enemy"
        case .friendly: return "Friendly"
        case .objective: return "Objective"
        case .hazard: return "Hazard"
        case .waypoint: return "Waypoint"
        case .cover: return "Cover"
        }
    }
    
    var systemImage: String {
        switch self {
        case .enemy: return "exclamationmark.triangle.fill"
        case .friendly: return "checkmark.circle.fill"
        case .objective: return "target"
        case .hazard: return "exclamationmark.triangle.fill"
        case .waypoint: return "location.circle.fill"
        case .cover: return "shield.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .enemy: return .red
        case .friendly: return .green
        case .objective: return .blue
        case .hazard: return .orange
        case .waypoint: return .purple
        case .cover: return .brown
        }
    }
}

// MARK: - Quick Messages
enum QuickMessage: String, CaseIterable {
    case moving = "Moving!"
    case inPosition = "In position"
    case needBackup = "Need backup!"
    case enemySpotted = "Enemy spotted!"
    case allClear = "All clear"
    case objective = "Objective secured"
    
    var displayText: String {
        return self.rawValue
    }
} 