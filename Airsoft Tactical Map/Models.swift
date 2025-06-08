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
    let altitude: Double?
    let accuracy: Double?
    let speed: Double?
    let timestamp: Date
    
    init(latitude: Double, longitude: Double, heading: Double? = nil, altitude: Double? = nil, accuracy: Double? = nil, speed: Double? = nil, timestamp: Date = Date()) {
        self.latitude = latitude
        self.longitude = longitude
        self.heading = heading
        self.altitude = altitude
        self.accuracy = accuracy
        self.speed = speed
        self.timestamp = timestamp
    }
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    // Convenience initializer for CLLocation
    init(from location: CLLocation, heading: Double? = nil) {
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.heading = heading
        self.altitude = location.altitude
        self.accuracy = location.horizontalAccuracy
        self.speed = location.speed >= 0 ? location.speed : nil
        self.timestamp = location.timestamp
    }
}

// MARK: - Team Model
struct Team: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let color: String
    
    var swiftUIColor: Color {
        switch color.lowercased() {
        case "red": return Color(red: 0.9, green: 0.2, blue: 0.2)
        case "blue": return Color(red: 0.2, green: 0.4, blue: 0.9)
        case "green": return Color(red: 0.2, green: 0.8, blue: 0.3)
        case "yellow": return Color(red: 0.9, green: 0.8, blue: 0.2)
        case "purple": return Color(red: 0.6, green: 0.2, blue: 0.9)
        case "orange": return Color(red: 0.9, green: 0.5, blue: 0.2)
        case "#ff0000": return Color(red: 1.0, green: 0.0, blue: 0.0)
        case "#0000ff": return Color(red: 0.0, green: 0.0, blue: 1.0)
        default: return .gray
        }
    }
    
    static func == (lhs: Team, rhs: Team) -> Bool {
        lhs.id == rhs.id
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

// MARK: - Game Phase
enum GamePhase: String, Codable {
    case waiting = "waiting"
    case active = "active"
    case paused = "paused"
    case ended = "ended"
}

// Add after existing models in Models.swift

// MARK: - Server Communication Models
struct ServerInput: Codable {
    let sequence: Int
    let type: String
    let data: InputData
    let timestamp: Date
}

struct InputData: Codable {
    // For movement
    var latitude: Double?
    var longitude: Double?
    var heading: Double?
    var speed: Double?
    var timestamp: Date?
    
    // For pins
    var type: String?
    var position: PinCoordinate?
    var pinId: String?
}

struct GameSnapshot: Codable {
    let tick: Int
    let timestamp: Date
    var players: [PlayerState]
    var pins: [Pin]
    let objectives: [Objective]
    let gamePhase: String
    let scores: [String: Int]
}

struct GameDelta: Codable {
    let fromTick: Int
    let toTick: Int
    let timestamp: Date
    let changes: DeltaChanges
}

struct DeltaChanges: Codable {
    let players: [String: PlayerState]
    let pins: PinChanges
    let events: [GameEvent]
}

struct PinChanges: Codable {
    let added: [Pin]
    let removed: [String]
}

struct PlayerState: Codable {
    let id: String
    let name: String
    let teamId: String?
    let isHost: Bool
    var position: PlayerPosition?
    let health: Int
    let score: Int
}

struct PlayerPosition: Codable {
    let latitude: Double
    let longitude: Double
    let heading: Double
    let speed: Double
    let lastUpdate: Date
    let clientTimestamp: Date?
}

struct Objective: Codable {
    let id: String
    let name: String
    let position: PinCoordinate
    let teamId: String?
    let status: String
}

struct GameEvent: Codable {
    let type: String
    let data: EventData
    let tick: Int
}

struct EventData: Codable {
    // Generic container for event-specific data
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