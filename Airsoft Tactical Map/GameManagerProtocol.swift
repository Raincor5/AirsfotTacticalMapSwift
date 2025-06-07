//
//  GameManagerProtocol.swift
//  Airsoft Tactical Map
//
//  Created by Jaroslavs Krots on 05/06/2025.
//

import Foundation
import Combine

protocol GameManagerProtocol: ObservableObject {
    var gameSession: GameSession? { get }
    var currentUser: Player? { get }
    var isHost: Bool { get }
    var isConnected: Bool { get }
    var connectionError: String? { get }
    var sessionCode: String? { get }
    var otherPlayers: [Player] { get }
    
    func createSession(playerName: String)
    func joinSession(code: String, playerName: String)
    func endSession()
    func updatePlayerLocation(_ location: PlayerLocation)
    func addPin(type: PinType, coordinate: PinCoordinate)
    func removePin(_ pinId: String)
    func sendGameMessage(_ text: String)
    func assignPlayerToTeam(_ playerId: String, teamId: String)
} 