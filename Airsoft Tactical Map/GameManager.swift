//
//  GameManager.swift
//  Airsoft Tactical Map
//
//  Created by Jaroslavs Krots on 05/06/2025.
//

import Foundation
import Combine

class GameManager: ObservableObject {
    @Published var gameSession: GameSession?
    @Published var currentUser: Player?
    @Published var isHost: Bool = false
    @Published var isConnected: Bool = false
    @Published var connectionError: String?
    
    private var webSocketTask: URLSessionWebSocketTask?
    private let baseURL = "ws://192.168.1.200:3001" // Your Mac's IP address
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupLocationUpdates()
    }
    
    deinit {
        disconnect()
    }
    
    // MARK: - Session Management
    
    func createSession(playerName: String) {
        let sessionCode = generateSessionCode()
        let player = Player(name: playerName, isHost: true)
        let session = GameSession(code: sessionCode, name: "Game \(sessionCode)", hostId: player.id)
        
        self.currentUser = player
        self.gameSession = session
        self.isHost = true
        
        connectToServer(sessionId: session.id, sessionName: session.name, player: player)
    }
    
    func joinSession(code: String, playerName: String) {
        let player = Player(name: playerName, isHost: false)
        self.currentUser = player
        self.isHost = false
        
        // For now, create a temporary session - the real session data will come from server
        let tempSession = GameSession(code: code, name: "Game \(code)", hostId: "unknown")
        self.gameSession = tempSession
        
        connectToServer(sessionId: tempSession.id, sessionName: nil, player: player)
    }
    
    func endSession() {
        disconnect()
        gameSession = nil
        currentUser = nil
        isHost = false
    }
    
    // MARK: - Server Communication
    
    private func connectToServer(sessionId: String, sessionName: String?, player: Player) {
        guard let url = URL(string: baseURL) else {
            connectionError = "Invalid server URL"
            return
        }
        
        webSocketTask = URLSession.shared.webSocketTask(with: url)
        webSocketTask?.resume()
        
        // Send initial connection message
        let connectMessage: [String: Any] = [
            "type": "connect",
            "sessionId": sessionId,
            "sessionName": sessionName ?? "Game \(sessionId)",
            "player": [
                "id": player.id,
                "name": player.name,
                "isHost": player.isHost
            ]
        ]
        
        sendMessage(connectMessage)
        startListening()
        isConnected = true
    }
    
    private func startListening() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleMessage(message)
                self?.startListening() // Continue listening
            case .failure(let error):
                DispatchQueue.main.async {
                    self?.connectionError = error.localizedDescription
                    self?.isConnected = false
                }
            }
        }
    }
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            guard let data = text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else {
                return
            }
            
            DispatchQueue.main.async {
                self.processServerMessage(type: type, data: json)
            }
            
        case .data(_):
            // Handle binary data if needed
            break
        @unknown default:
            break
        }
    }
    
    private func processServerMessage(type: String, data: [String: Any]) {
        switch type {
        case "sessionUpdate":
            updateSessionFromServer(data)
        case "locationUpdate":
            updatePlayerLocationFromServer(data)
        case "pinAdded":
            addPinFromServer(data)
        case "pinRemoved":
            removePinFromServer(data)
        case "messageReceived":
            addMessageFromServer(data)
        case "playerJoined":
            addPlayerFromServer(data)
        case "playerLeft":
            removePlayerFromServer(data)
        case "teamAssignment":
            updateTeamAssignmentFromServer(data)
        default:
            print("Unknown message type: \(type)")
        }
    }
    
    private func sendMessage(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let string = String(data: data, encoding: .utf8) else {
            return
        }
        
        webSocketTask?.send(.string(string)) { error in
            if let error = error {
                DispatchQueue.main.async {
                    self.connectionError = error.localizedDescription
                }
            }
        }
    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
    }
    
    // MARK: - Game Actions
    
    func updatePlayerLocation(_ location: PlayerLocation) {
        guard let currentUser = currentUser else { return }
        
        // Update local user
        self.currentUser?.location = location
        if var session = gameSession {
            session.players[currentUser.id]?.location = location
            self.gameSession = session
        }
        
        // Send to server
        let message: [String: Any] = [
            "type": "updateLocation",
            "playerId": currentUser.id,
            "location": [
                "latitude": location.latitude,
                "longitude": location.longitude,
                "heading": location.heading ?? 0,
                "timestamp": ISO8601DateFormatter().string(from: location.timestamp)
            ]
        ]
        sendMessage(message)
    }
    
    func addPin(type: PinType, coordinate: PinCoordinate) {
        guard let currentUser = currentUser else { return }
        
        let pin = Pin(
            type: type.rawValue,
            name: type.displayName,
            coordinate: coordinate,
            playerId: currentUser.id,
            teamId: currentUser.teamId
        )
        
        let message: [String: Any] = [
            "type": "addPin",
            "pin": [
                "id": pin.id,
                "type": pin.type,
                "name": pin.name,
                "coordinate": [
                    "latitude": pin.coordinate.latitude,
                    "longitude": pin.coordinate.longitude
                ],
                "playerId": pin.playerId,
                "teamId": pin.teamId as Any,
                "timestamp": ISO8601DateFormatter().string(from: pin.timestamp)
            ]
        ]
        sendMessage(message)
    }
    
    func removePin(_ pinId: String) {
        let message: [String: Any] = [
            "type": "removePin",
            "pinId": pinId
        ]
        sendMessage(message)
    }
    
    func sendGameMessage(_ text: String) {
        guard let currentUser = currentUser else { return }
        
        let message: [String: Any] = [
            "type": "sendMessage",
            "message": [
                "text": text,
                "playerId": currentUser.id,
                "playerName": currentUser.name,
                "teamId": currentUser.teamId as Any,
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ]
        ]
        sendMessage(message)
    }
    
    func assignPlayerToTeam(_ playerId: String, teamId: String) {
        guard isHost else { return }
        
        let message: [String: Any] = [
            "type": "assignTeam",
            "playerId": playerId,
            "teamId": teamId
        ]
        sendMessage(message)
    }
    
    // MARK: - Server Response Handlers
    
    private func updateSessionFromServer(_ data: [String: Any]) {
        // Parse and update the full session state from server
        // This would involve parsing the session data structure
        print("Session update from server: \(data)")
    }
    
    private func updatePlayerLocationFromServer(_ data: [String: Any]) {
        guard let playerId = data["playerId"] as? String,
              let locationData = data["location"] as? [String: Any],
              let latitude = locationData["latitude"] as? Double,
              let longitude = locationData["longitude"] as? Double else {
            return
        }
        
        let heading = locationData["heading"] as? Double
        let location = PlayerLocation(latitude: latitude, longitude: longitude, heading: heading)
        
        if var session = gameSession {
            session.players[playerId]?.location = location
            self.gameSession = session
        }
    }
    
    private func addPinFromServer(_ data: [String: Any]) {
        // Parse pin data and add to session
        print("Pin added from server: \(data)")
    }
    
    private func removePinFromServer(_ data: [String: Any]) {
        guard let pinId = data["pinId"] as? String else { return }
        
        if var session = gameSession {
            session.pins.removeAll { $0.id == pinId }
            self.gameSession = session
        }
    }
    
    private func addMessageFromServer(_ data: [String: Any]) {
        // Parse message data and add to session
        print("Message received from server: \(data)")
    }
    
    private func addPlayerFromServer(_ data: [String: Any]) {
        // Parse player data and add to session
        print("Player joined from server: \(data)")
    }
    
    private func removePlayerFromServer(_ data: [String: Any]) {
        guard let playerId = data["playerId"] as? String else { return }
        
        if var session = gameSession {
            session.players.removeValue(forKey: playerId)
            self.gameSession = session
        }
    }
    
    private func updateTeamAssignmentFromServer(_ data: [String: Any]) {
        // Parse team assignment data and update session
        print("Team assignment from server: \(data)")
    }
    
    // MARK: - Location Updates
    
    private func setupLocationUpdates() {
        // This will be called from the location manager
    }
    
    // MARK: - Utilities
    
    private func generateSessionCode() -> String {
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<6).map { _ in letters.randomElement()! })
    }
    
    // Computed properties for easy access
    var sessionCode: String? {
        gameSession?.code
    }
    
    var otherPlayers: [Player] {
        guard let session = gameSession,
              let currentUserId = currentUser?.id else {
            return []
        }
        
        return Array(session.players.values.filter { $0.id != currentUserId })
    }
    
    var teamPlayers: [String: [Player]] {
        guard let session = gameSession else { return [:] }
        
        var teamGroups: [String: [Player]] = [:]
        for player in session.players.values {
            let teamId = player.teamId ?? "unassigned"
            if teamGroups[teamId] == nil {
                teamGroups[teamId] = []
            }
            teamGroups[teamId]?.append(player)
        }
        
        return teamGroups
    }
} 