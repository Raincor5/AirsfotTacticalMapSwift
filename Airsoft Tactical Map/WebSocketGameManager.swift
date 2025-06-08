//
//  WebSocketGameManager.swift
//  Airsoft Tactical Map
//
//  Created by Jaroslavs Krots on 05/06/2025.
//

import Foundation
import Combine
import Network
import UIKit

// MARK: - Connection State
enum ConnectionState {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case failed(String)
}

class WebSocketGameManager: NSObject, ObservableObject, GameManagerProtocol {
    @Published var gameSession: GameSession?
    @Published var currentUser: Player?
    @Published var isHost: Bool = false
    @Published var isConnected: Bool = false
    @Published var connectionError: String?
    @Published var connectionState: ConnectionState = .disconnected
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private let notificationManager = PushNotificationManager.shared
    
    // Network manager for client-side prediction and interpolation
    let networkManager = NetworkManager()
    
    // Server configuration
    @Published var serverHost = "192.168.1.200" // Change to your Mac's IP
    @Published var serverPort = 3001
    
    // Server status computed property
    var serverStatus: String {
        switch connectionState {
        case .connected:
            return "Connected to \(serverHost):\(serverPort)"
        case .connecting:
            return "Connecting to \(serverHost):\(serverPort)..."
        case .reconnecting:
            return "Reconnecting to \(serverHost):\(serverPort)..."
        case .disconnected:
            return "Not connected"
        case .failed(let message):
            return "Connection failed: \(message)"
        }
    }
    
    override init() {
        super.init()
        setupURLSession()
        setupNetworkManager()
    }
    
    private func setupNetworkManager() {
        // Set up communication between NetworkManager and WebSocketGameManager
        networkManager.sendToServer = { [weak self] message in
            self?.sendMessage(message)
        }
        
        // Handle message acknowledgments
        networkManager.onMessageSent = { [weak self] sequence in
            self?.networkManager.lastAcknowledgedInput = sequence
        }
    }
    
    deinit {
        disconnect()
    }
    
    private func setupURLSession() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    // MARK: - Session Management
    
    func createSession(playerName: String) {
        let player = Player(id: UUID().uuidString, name: playerName, isHost: true)
        self.currentUser = player
        self.isHost = true
        
        // Update network manager with current user ID
        networkManager.currentUserId = player.id
        
        connectToServer { [weak self] success in
            guard success else { return }
            
            // Create session directly
            self?.sendMessage([
                "type": "createSession",
                "playerName": playerName,
                "playerId": player.id
            ])
        }
    }

    func joinSession(code: String, playerName: String) {
        let player = Player(id: UUID().uuidString, name: playerName, isHost: false)
        self.currentUser = player
        self.isHost = false
        
        // Update network manager with current user ID
        networkManager.currentUserId = player.id
        
        connectToServer { [weak self] success in
            guard success else { return }
            
            // Join session directly
            self?.sendMessage([
                "type": "joinSession",
                "sessionCode": code.uppercased(),
                "playerName": playerName,
                "playerId": player.id
            ])
        }
    }    
    func endSession() {
        if let sessionCode = gameSession?.code {
            let message = [
                "type": "leaveSession",
                "sessionCode": sessionCode
            ]
            sendMessage(message)
        }
        
        disconnect()
        
        DispatchQueue.main.async {
            self.gameSession = nil
            self.currentUser = nil
            self.isHost = false
            self.isConnected = false
            self.connectionState = .disconnected
        }
    }
    
    // MARK: - Game Actions
    
    func updatePlayerLocation(_ location: PlayerLocation) {
        guard let currentUser = currentUser else { return }
        
        let inputData = InputData(
            latitude: location.latitude,
            longitude: location.longitude,
            heading: location.heading,
            speed: location.speed,
            timestamp: location.timestamp
        )
        
        // Send to authoritative server - server will broadcast back the update
        let sequence = networkManager.sendInput(type: "move", data: inputData)
        
        // Store locally for prediction/rollback but don't update UI yet
        applyClientSidePrediction(for: currentUser.id, with: location)
        }

        private func applyClientSidePrediction(for playerId: String, with location: PlayerLocation) {
        // Update local state immediately for responsive feel
        DispatchQueue.main.async {
            if var snapshot = self.networkManager.currentSnapshot {
                if let index = snapshot.players.firstIndex(where: { $0.id == playerId }) {
                    snapshot.players[index].position = PlayerPosition(
                        latitude: location.latitude,
                        longitude: location.longitude,
                        heading: location.heading ?? 0,
                        speed: location.speed ?? 0,
                        lastUpdate: location.timestamp,
                        clientTimestamp: location.timestamp
                    )
                    // This will be corrected by server if needed
                    self.networkManager.currentSnapshot = snapshot
                }
            }
        }
    }
            
    func addPin(type: PinType, coordinate: PinCoordinate) {
        guard let currentUserId = currentUser?.id else { return }
        
        let message: [String: Any] = [
            "type": "addPin",
            "pin": [
                "type": type.rawValue,
                "name": "",
                "coordinate": [
                    "latitude": coordinate.latitude,
                    "longitude": coordinate.longitude
                ],
                "playerId": currentUserId,
                "teamId": currentUser?.teamId
            ]
        ]
        sendMessage(message)
    }

    func removePin(_ pinId: String) {
        let inputData = InputData(pinId: pinId)
        networkManager.sendInput(type: "removePin", data: inputData)
    }
    
    func sendGameMessage(_ text: String) {
        guard let currentUser = currentUser,
              let sessionCode = gameSession?.code else { return }
        
        let gameMessage = GameMessage(
            text: text,
            playerId: currentUser.id,
            playerName: currentUser.name,
            teamId: currentUser.teamId
        )
        
        // Add to local session first
        if var session = gameSession {
            session.messages.append(gameMessage)
            self.gameSession = session
            print("💬 WebSocket: Added message locally: \(text)")
        }
        
        let message = [
            "type": "sendMessage",
            "sessionCode": sessionCode,
            "message": [
                "text": text,
                "playerId": currentUser.id,
                "playerName": currentUser.name,
                "teamId": currentUser.teamId as Any
            ]
        ] as [String : Any]
        
        sendMessage(message)
    }
    
    func assignPlayerToTeam(_ playerId: String, teamId: String) {
        guard isHost, let sessionCode = gameSession?.code else { 
            print("❌ WebSocket: Cannot assign player to team: Not host or no session")
            return 
        }
        
        print("🔄 WebSocket: Assigning player \(playerId) to team \(teamId)")
        
        // Update local session first for immediate UI feedback
        if var session = gameSession {
            if session.players[playerId] != nil {
                session.players[playerId]?.teamId = teamId
                print("✅ WebSocket: Updated local session for player \(playerId)")
                
                // Update current user if it's them - ensure both references are updated
                if playerId == currentUser?.id {
                    currentUser?.teamId = teamId
                    print("✅ WebSocket: Updated current user team assignment locally")
                }
                
                self.gameSession = session
            }
        }
        
        let message = [
            "type": "assignTeam",
            "sessionCode": sessionCode,
            "playerId": playerId,
            "teamId": teamId
        ]
        
        sendMessage(message)
        print("📤 WebSocket: Sent team assignment message to server")
        
        // Force UI update
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
        
        // Broadcast current location to ensure allies can see each other immediately
        if let currentUser = self.currentUser, let location = currentUser.location {
            self.updatePlayerLocation(location)
        }
    }
    
    // MARK: - WebSocket Connection
    
    private func connectToServer(completion: @escaping (Bool) -> Void) {
        guard webSocketTask == nil else {
            print("🔌 WebSocket: Already connected, skipping connection")
            completion(true)
            return
        }
        
        DispatchQueue.main.async {
            self.connectionState = .connecting
            self.connectionError = nil
        }
        
        let url = URL(string: "ws://\(serverHost):\(serverPort)")!
        print("🔌 WebSocket: Connecting to \(url)")
        webSocketTask = urlSession?.webSocketTask(with: url)
        
        webSocketTask?.resume()
        startListening()
        
        // Wait a moment for connection
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            print("🔌 WebSocket: Connection check - task exists: \(self.webSocketTask != nil)")
            completion(self.webSocketTask != nil)
        }
    }
    
    private func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectionState = .disconnected
        }
    }
    
    private func startListening() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleMessage(message)
                
                // Continue listening
                self?.startListening()
                
            case .failure(let error):
                DispatchQueue.main.async {
                    self?.connectionError = "Connection lost: \(error.localizedDescription)"
                    self?.isConnected = false
                    self?.connectionState = .failed(error.localizedDescription)
                }
            }
        }
    }
    
    private func sendMessage(_ message: [String: Any]) {
        guard let webSocketTask = webSocketTask else {
            print("❌ WebSocket: Cannot send message - no active connection")
            return
        }
        
        do {
            let data = try JSONSerialization.data(withJSONObject: message)
            let string = String(data: data, encoding: .utf8) ?? ""
            
            print("📤 WebSocket: Sending message: \(string)")
            
            webSocketTask.send(.string(string)) { error in
                if let error = error {
                    print("❌ WebSocket: Failed to send message: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.connectionError = "Failed to send message: \(error.localizedDescription)"
                    }
                } else {
                    print("✅ WebSocket: Message sent successfully")
                }
            }
        } catch {
            print("❌ WebSocket: Failed to encode message: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.connectionError = "Failed to encode message: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Message Handling
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        print("📥 WebSocket: Received message")
        
        switch message {
        case .string(let text):
            print("📥 WebSocket: Received string message: \(text)")
            guard let data = text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else {
                print("❌ WebSocket: Invalid message format")
                return
            }
            
            print("📥 WebSocket: Processing message type: \(type)")
            
            switch type {
            case "gameSnapshot":
                print("📥 WebSocket: Handling gameSnapshot")
                handleGameSnapshot(json)
            case "gameDelta":
                print("📥 WebSocket: Handling gameDelta")
                handleGameDelta(json)
            case "inputAck":
                print("📥 WebSocket: Handling inputAck")
                handleInputAck(json)
            case "error":
                if let errorMessage = json["message"] as? String {
                    print("❌ WebSocket error: \(errorMessage)")
                    DispatchQueue.main.async {
                        self.connectionError = errorMessage
                    }
                }
            default:
                print("⚠️ WebSocket: Unknown message type: \(type)")
            }
            
        case .data(let data):
            print("📥 WebSocket: Received binary message")
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let type = json["type"] as? String {
                print("📥 WebSocket: Processing binary message type: \(type)")
                // Handle binary messages similarly to string messages
            }
            
        @unknown default:
            print("⚠️ WebSocket: Unknown message type")
        }
    }
    
    private func handleGameSnapshot(_ data: [String: Any]) {
        print("📥 WebSocket: Starting handleGameSnapshot")
        guard let sessionData = data["session"] as? [String: Any],
              let tick = data["tick"] as? Int,
              let timestamp = data["timestamp"] as? TimeInterval else {
            print("❌ WebSocket: Invalid gameSnapshot data")
            return
        }
        
        print("📥 WebSocket: Processing snapshot for tick \(tick)")
        
        // Create a new snapshot
        var snapshot = GameSnapshot(
            tick: tick,
            timestamp: Date(timeIntervalSince1970: timestamp / 1000),
            players: [],
            pins: [],
            objectives: [],
            gamePhase: GamePhase.waiting.rawValue,
            scores: [:]
        )
        
        // Parse session data
        if let players = sessionData["players"] as? [[String: Any]] {
            for playerData in players {
                if let id = playerData["id"] as? String,
                   let name = playerData["name"] as? String {
                    let isHost = playerData["isHost"] as? Bool ?? false
                    let teamId = playerData["teamId"] as? String
                    
                    var player = Player(id: id, name: name, teamId: teamId, isHost: isHost)
                    
                    // Add location if available
                    if let locationData = playerData["location"] as? [String: Any],
                       let latitude = locationData["latitude"] as? Double,
                       let longitude = locationData["longitude"] as? Double {
                        let heading = locationData["heading"] as? Double
                        let speed = locationData["speed"] as? Double
                        let timestamp = locationData["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970
                        let location = PlayerLocation(
                            latitude: latitude,
                            longitude: longitude,
                            heading: heading,
                            speed: speed,
                            timestamp: Date(timeIntervalSince1970: timestamp / 1000)
                        )
                        player.location = location
                    }
                    
                    // Convert Player to PlayerState
                    let playerState = PlayerState(
                        id: player.id,
                        name: player.name,
                        teamId: player.teamId,
                        isHost: player.isHost,
                        position: player.location.map { location in
                            PlayerPosition(
                                latitude: location.latitude,
                                longitude: location.longitude,
                                heading: location.heading ?? 0,
                                speed: location.speed ?? 0,
                                lastUpdate: location.timestamp,
                                clientTimestamp: nil
                            )
                        },
                        health: 100, // Default health
                        score: 0 // Default score
                    )
                    snapshot.players.append(playerState)
                }
            }
        }
        
        // Update network manager with new snapshot
        networkManager.handleSnapshot(snapshot)
        
        // Update local game state
        updateLocalGameState(from: snapshot)
        
        print("✅ WebSocket: Processed snapshot with \(snapshot.players.count) players")
    }

    private func handleGameDelta(_ data: [String: Any]) {
        print("📥 WebSocket: Starting handleGameDelta")
        guard let changes = data["changes"] as? [String: Any],
              let tick = data["tick"] as? Int,
              let timestamp = data["timestamp"] as? TimeInterval else {
            print("❌ WebSocket: Invalid gameDelta data")
            return
        }
        
        print("📥 WebSocket: Processing delta for tick \(tick)")
        
        // Create delta object
        var delta = GameDelta(
            fromTick: networkManager.serverTick,
            toTick: tick,
            timestamp: Date(timeIntervalSince1970: timestamp / 1000),
            changes: DeltaChanges(
                players: [:],
                pins: PinChanges(added: [], removed: []),
                events: []
            )
        )
        
        // Parse player changes
        if let playerStates = changes["playerStates"] as? [String: [String: Any]] {
            var updatedPlayers: [String: PlayerState] = [:]
            for (playerId, state) in playerStates {
                if let player = parsePlayerState(state) {
                    // Convert Player to PlayerState
                    let playerState = PlayerState(
                        id: player.id,
                        name: player.name,
                        teamId: player.teamId,
                        isHost: player.isHost,
                        position: player.location.map { location in
                            PlayerPosition(
                                latitude: location.latitude,
                                longitude: location.longitude,
                                heading: location.heading ?? 0,
                                speed: location.speed ?? 0,
                                lastUpdate: location.timestamp,
                                clientTimestamp: nil
                            )
                        },
                        health: 100, // Default health
                        score: 0 // Default score
                    )
                    updatedPlayers[playerId] = playerState
                }
            }
            
            // Create a new DeltaChanges with updated players
            delta = GameDelta(
                fromTick: delta.fromTick,
                toTick: delta.toTick,
                timestamp: delta.timestamp,
                changes: DeltaChanges(
                    players: updatedPlayers,
                    pins: delta.changes.pins,
                    events: delta.changes.events
                )
            )
        }
        
        // Parse pin changes
        if let pins = changes["pins"] as? [[String: Any]] {
            var addedPins: [Pin] = []
            for pinData in pins {
                if let pin = parsePin(pinData) {
                    addedPins.append(pin)
                }
            }
            
            // Create a new DeltaChanges with updated pins
            delta = GameDelta(
                fromTick: delta.fromTick,
                toTick: delta.toTick,
                timestamp: delta.timestamp,
                changes: DeltaChanges(
                    players: delta.changes.players,
                    pins: PinChanges(added: addedPins, removed: []),
                    events: delta.changes.events
                )
            )
        }
        
        // Update network manager with delta
        networkManager.handleDelta(delta)
        
        // Update local game state
        if let snapshot = networkManager.currentSnapshot {
            updateLocalGameState(from: snapshot)
        }
        
        print("✅ WebSocket: Processed delta with \(delta.changes.players.count) player changes")
    }

    private func handleInputAck(_ data: [String: Any]) {
        guard let sequence = data["sequence"] as? Int else { return }
        networkManager.lastAcknowledgedInput = sequence
    }

    private func updateLocalGameState(from snapshot: GameSnapshot) {
        DispatchQueue.main.async {
            // Update session with new state
            if let session = self.gameSession {
                // Create a new dictionary for players
                var newPlayers: [String: Player] = [:]
                for playerState in snapshot.players {
                    let player = Player(
                        id: playerState.id,
                        name: playerState.name,
                        teamId: playerState.teamId,
                        location: playerState.position.map { pos in
                            PlayerLocation(
                                latitude: pos.latitude,
                                longitude: pos.longitude,
                                heading: pos.heading,
                                speed: pos.speed,
                                timestamp: pos.lastUpdate
                            )
                        },
                        isHost: playerState.isHost
                    )
                    newPlayers[player.id] = player
                }
                
                // Create a new session with all values set during initialization
                let updatedSession = GameSession(
                    id: session.id,
                    code: session.code,
                    name: session.name,
                    hostId: session.hostId,
                    createdAt: session.createdAt
                )
                
                // Create a new session with the updated values
                var mutableSession = updatedSession
                mutableSession.players = newPlayers
                mutableSession.pins = snapshot.pins
                mutableSession.teams = session.teams
                mutableSession.messages = session.messages
                
                // Assign the new session to trigger @Published update
                self.gameSession = mutableSession
                
                // Force UI update
                self.objectWillChange.send()
            }
        }
    }
    
    // MARK: - Authoritative Server Handlers
    
    private func handleSessionCreated(_ data: [String: Any]) {
        guard let sessionCode = data["sessionCode"] as? String,
              let sessionData = data["session"] as? [String: Any],
              let currentUser = currentUser else {
            return
        }
        
        // Create a new session with default values
        var session = GameSession(
            id: UUID().uuidString,
            code: sessionCode,
            name: "Game \(sessionCode)",
            hostId: currentUser.id
        )
        
        // Add current user to the session
        session.players[currentUser.id] = currentUser
        
        // Parse server data but preserve default values if not provided
        if let serverPlayers = sessionData["players"] as? [String: [String: Any]] {
            for (playerId, playerData) in serverPlayers {
                if playerId != currentUser.id { // Don't overwrite current user
                    if let name = playerData["name"] as? String {
                        let isHost = playerData["isHost"] as? Bool ?? false
                        let teamId = playerData["teamId"] as? String
                        session.players[playerId] = Player(id: playerId, name: name, teamId: teamId, isHost: isHost)
                    }
                }
            }
        }
        
        // Update teams if provided by server
        if let serverTeams = sessionData["teams"] as? [[String: Any]] {
            session.teams = serverTeams.compactMap { teamData in
                guard let id = teamData["id"] as? String,
                      let name = teamData["name"] as? String,
                      let color = teamData["color"] as? String else {
                    return nil
                }
                return Team(id: id, name: name, color: color)
            }
        }
        
        // Update pins if provided by server
        if let serverPins = sessionData["pins"] as? [[String: Any]] {
            session.pins = serverPins.compactMap { pinData in
                guard let id = pinData["id"] as? String,
                      let type = pinData["type"] as? String,
                      let name = pinData["name"] as? String,
                      let coordData = pinData["coordinate"] as? [String: Any],
                      let latitude = coordData["latitude"] as? Double,
                      let longitude = coordData["longitude"] as? Double,
                      let playerId = pinData["playerId"] as? String else {
                    return nil
                }
                let coordinate = PinCoordinate(latitude: latitude, longitude: longitude)
                let teamId = pinData["teamId"] as? String
                return Pin(id: id, type: type, name: name, coordinate: coordinate, playerId: playerId, teamId: teamId)
            }
        }
        
        DispatchQueue.main.async {
            self.gameSession = session
            self.isConnected = true
            self.connectionState = .connected
            
            // Force UI update
            self.objectWillChange.send()
        }
    }

    private func handlePlayerJoined(_ data: [String: Any]) {
        print("👤 WebSocket: Starting handlePlayerJoined")
        guard let playerData = data["player"] as? [String: Any],
              let id = playerData["id"] as? String,
              let name = playerData["name"] as? String else {
            print("❌ WebSocket: Invalid player data in playerJoined")
            return
        }
        
        // Don't add ourselves again
        if id == currentUser?.id {
            print("📥 WebSocket: Ignoring playerJoined for self")
            return
        }
        
        let isHost = playerData["isHost"] as? Bool ?? false
        let teamId = playerData["teamId"] as? String
        var player = Player(id: id, name: name, teamId: teamId, isHost: isHost)
        
        // Add location if available
        if let locationData = playerData["location"] as? [String: Any],
           let latitude = locationData["latitude"] as? Double,
           let longitude = locationData["longitude"] as? Double {
            let heading = locationData["heading"] as? Double
            let location = PlayerLocation(
                latitude: latitude,
                longitude: longitude,
                heading: heading,
                speed: 0,
                timestamp: Date(timeIntervalSince1970: 0)
            )
            player.location = location
        }
        
        // Add player to session
        if var session = gameSession {
            session.players[id] = player
            self.gameSession = session
            print("✅ WebSocket: Added player \(name) to session with location: \(player.location != nil)")
            
            // Force UI update
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        } else {
            print("❌ WebSocket: No active session when adding player")
        }
    }
    
    private func handleSessionJoined(_ data: [String: Any]) {
        guard let sessionData = data["session"] as? [String: Any],
              let code = sessionData["code"] as? String,
              let name = sessionData["name"] as? String,
              let hostId = sessionData["hostPlayerId"] as? String else { 
            print("❌ WebSocket: Invalid sessionJoined data structure")
            return 
        }
        
        var session = GameSession(code: code, name: name, hostId: hostId)
        
        // Parse the full session data
        parseSessionData(sessionData, into: &session)
        
        // Add current user if not already in session
        if let currentUser = self.currentUser {
            if var existingPlayer = session.players[currentUser.id] {
                // Update existing player with current user's data but keep server's team assignment
                existingPlayer.name = currentUser.name
                existingPlayer.isHost = currentUser.isHost
                session.players[currentUser.id] = existingPlayer
                
                // Update current user with server's team assignment
                self.currentUser?.teamId = existingPlayer.teamId
            } else {
                // Add as new player
                session.players[currentUser.id] = currentUser
            }
        }
        
        self.gameSession = session
        self.isConnected = true
        self.connectionState = .connected
        
        // Force UI update
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
        
        print("✅ Joined session: \(code) with \(session.players.count) players, \(session.pins.count) pins, \(session.messages.count) messages")
        
        // Request a full sync after joining to ensure we have latest data
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.sendMessage(["type": "syncRequest", "sessionCode": code])
        }
    }
    
    private func handlePlayerLeft(_ data: [String: Any]) {
        guard let playerId = data["playerId"] as? String else { return }
        
        if var session = gameSession {
            session.players.removeValue(forKey: playerId)
            self.gameSession = session
            print("👤 Player \(playerId) left the session")
        }
    }
    
    private func handleLocationUpdate(_ data: [String: Any]) {
        print("📍 WebSocket: Handling location update")
        guard let playerId = data["playerId"] as? String,
              let locationData = data["location"] as? [String: Any],
              let latitude = locationData["latitude"] as? Double,
              let longitude = locationData["longitude"] as? Double else {
            print("❌ WebSocket: Invalid location data")
            return
        }
        
        let heading = locationData["heading"] as? Double
        let location = PlayerLocation(
            latitude: latitude,
            longitude: longitude,
            heading: heading,
            speed: 0,
            timestamp: Date(timeIntervalSince1970: 0)
        )
        
        if var session = gameSession {
            if var player = session.players[playerId] {
                player.location = location
                session.players[playerId] = player
                self.gameSession = session
                print("✅ WebSocket: Updated location for player \(player.name)")
                
                // Force UI update for map
                DispatchQueue.main.async {
                    self.objectWillChange.send()
                }
            } else {
                print("❌ WebSocket: Player \(playerId) not found in session")
            }
        } else {
            print("❌ WebSocket: No active session for location update")
        }
    }
    
    private func handlePinAdded(_ data: [String: Any]) {
        guard let pinData = data["pin"] as? [String: Any],
              let id = pinData["id"] as? String,
              let type = pinData["type"] as? String,
              let name = pinData["name"] as? String,
              let coordData = pinData["coordinate"] as? [String: Any],
              let latitude = coordData["latitude"] as? Double,
              let longitude = coordData["longitude"] as? Double,
              let playerId = pinData["playerId"] as? String else { return }
        
        let coordinate = PinCoordinate(latitude: latitude, longitude: longitude)
        let teamId = pinData["teamId"] as? String
        
        let pin = Pin(
            id: id,
            type: type,
            name: name ?? "",
            coordinate: coordinate,
            playerId: playerId,
            teamId: teamId,
            timestamp: Date(timeIntervalSince1970: 0)
        )
        
        if var session = gameSession {
            // Avoid duplicates
            if !session.pins.contains(where: { $0.id == pin.id }) {
                session.pins.append(pin)
                self.gameSession = session
                print("📍 WebSocket: Added pin from server: \(pin.name)")
                
                // If this is our pin, acknowledge the input
                if playerId == currentUser?.id {
                    // Find and acknowledge the pending pin input
                    for input in networkManager.pendingInputs {
                        if input.type == "addPin" {
                            networkManager.lastAcknowledgedInput = input.sequence
                            // Trigger NetworkManager callback for acknowledgment
                            networkManager.onMessageSent?(input.sequence)
                            break
                        }
                    }
                }
            }
        }
    }
    
    private func handlePinRemoved(_ data: [String: Any]) {
        guard let pinId = data["pinId"] as? String else { return }
        
        if var session = gameSession {
            session.pins.removeAll { $0.id == pinId }
            self.gameSession = session
        }
    }
    
    private func handleMessageReceived(_ data: [String: Any]) {
        guard let messageData = data["message"] as? [String: Any],
              let text = messageData["text"] as? String,
              let playerId = messageData["playerId"] as? String,
              let playerName = messageData["playerName"] as? String else { return }
        
        // Don't add our own messages back from the server (already added locally)
        if playerId == currentUser?.id {
            print("💬 WebSocket: Ignoring own message from server: \(text)")
            return
        }
        
        let teamId = messageData["teamId"] as? String
        
        let message = GameMessage(
            text: text,
            playerId: playerId,
            playerName: playerName,
            teamId: teamId
        )
        
        if var session = gameSession {
            // Avoid duplicates
            if !session.messages.contains(where: { $0.id == message.id }) {
                session.messages.append(message)
                self.gameSession = session
                print("💬 WebSocket: Added message from server: \(message.text)")
                
                // Send push notification if app is in background
                if UIApplication.shared.applicationState == .background {
                    notificationManager.sendTeamMessage(text, from: playerName, teamId: teamId)
                }
            }
        }
    }
    
    private func handleTeamAssigned(_ data: [String: Any]) {
        guard let playerId = data["playerId"] as? String,
              let teamId = data["teamId"] as? String else { return }
        
        print("🔄 WebSocket: Handling team assignment: Player \(playerId) to team \(teamId)")
        
        if var session = gameSession {
            session.players[playerId]?.teamId = teamId
            
            // Update current user if it's them and ensure both references are updated
            if playerId == currentUser?.id {
                currentUser?.teamId = teamId
                // Also update in session to maintain consistency
                session.players[playerId]?.teamId = teamId
                print("✅ WebSocket: Updated current user team assignment")
            }
            
            self.gameSession = session
            
            // Force UI update
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }
    
    private func handleFullSync(_ data: [String: Any]) {
        guard let sessionData = data["session"] as? [String: Any] else { return }
        
        if var session = gameSession {
            parseSessionData(sessionData, into: &session)
            self.gameSession = session
            print("🔄 Full sync completed")
        }
    }
    
    private func handleError(_ data: [String: Any]) {
        let message = data["message"] as? String ?? "Unknown error"
        self.connectionError = message
        self.connectionState = .failed(message)
        print("❌ Server error: \(message)")
    }
    
    // MARK: - Helper Methods
    
    private func updateLocalGameState(from snapshot: GameSnapshot?) {
        guard let snapshot = snapshot else { return }
        
        // Update game session with server state if needed
        // This method can be expanded to sync server-authoritative data with local game session
        
        // For now, we rely on the NetworkManager's interpolated state for rendering
        // The GameSession remains the source of truth for UI elements
    }
    
    private func parseSessionData(_ sessionData: [String: Any], into session: inout GameSession) {
        // Parse players
        if let players = sessionData["players"] as? [[String: Any]] {
            for playerData in players {
                if let id = playerData["id"] as? String,
                   let name = playerData["name"] as? String {
                    let isHost = playerData["isHost"] as? Bool ?? false
                    let teamId = playerData["teamId"] as? String
                    var player = Player(id: id, name: name, teamId: teamId, isHost: isHost)
                    
                    // Add location if available
                    if let locationData = playerData["location"] as? [String: Any],
                       let latitude = locationData["latitude"] as? Double,
                       let longitude = locationData["longitude"] as? Double {
                        let heading = locationData["heading"] as? Double
                        let speed = locationData["speed"] as? Double
                        let timestamp = locationData["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970
                        let location = PlayerLocation(
                            latitude: latitude,
                            longitude: longitude,
                            heading: heading,
                            speed: speed,
                            timestamp: Date(timeIntervalSince1970: timestamp / 1000)
                        )
                        player.location = location
                    }
                    
                    session.players[id] = player
                }
            }
        }
        
        // Parse teams
        if let teams = sessionData["teams"] as? [[String: Any]] {
            session.teams = []
            for teamData in teams {
                if let id = teamData["id"] as? String,
                   let name = teamData["name"] as? String,
                   let color = teamData["color"] as? String {
                    let team = Team(id: id, name: name, color: color)
                    session.teams.append(team)
                }
            }
        }
        
        // Parse pins
        if let pins = sessionData["pins"] as? [[String: Any]] {
            session.pins = []
            for pinData in pins {
                if let id = pinData["id"] as? String,
                   let type = pinData["type"] as? String,
                   let name = pinData["name"] as? String,
                   let coordData = pinData["coordinate"] as? [String: Any],
                   let latitude = coordData["latitude"] as? Double,
                   let longitude = coordData["longitude"] as? Double,
                   let playerId = pinData["playerId"] as? String {
                    let coordinate = PinCoordinate(latitude: latitude, longitude: longitude)
                    let teamId = pinData["teamId"] as? String
                    
                    let pin = Pin(
                        id: id,
                        type: type,
                        name: name ?? "",
                        coordinate: coordinate,
                        playerId: playerId,
                        teamId: teamId,
                        timestamp: Date(timeIntervalSince1970: 0)
                    )
                    
                    session.pins.append(pin)
                }
            }
        }
        
        // Parse messages
        if let messages = sessionData["messages"] as? [[String: Any]] {
            session.messages = []
            for messageData in messages {
                if let id = messageData["id"] as? String,
                   let text = messageData["text"] as? String,
                   let playerId = messageData["playerId"] as? String,
                   let playerName = messageData["playerName"] as? String {
                    let teamId = messageData["teamId"] as? String
                    
                    let message = GameMessage(
                        id: id,
                        text: text,
                        playerId: playerId,
                        playerName: playerName,
                        teamId: teamId
                    )
                    
                    session.messages.append(message)
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
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
    
    // MARK: - Server Configuration Methods
    
    func configureServer(host: String, port: Int) {
        DispatchQueue.main.async {
            self.serverHost = host
            self.serverPort = port
        }
        print("🔧 Server configured: \(host):\(port)")
    }
    
    func testConnection(completion: @escaping (Bool, String) -> Void) {
        DispatchQueue.main.async {
            self.connectionState = .connecting
        }
        
        // Create a temporary WebSocket connection to test
        let testURL = URL(string: "ws://\(serverHost):\(serverPort)")!
        let testConfig = URLSessionConfiguration.default
        testConfig.timeoutIntervalForRequest = 5
        let testSession = URLSession(configuration: testConfig)
        let testTask = testSession.webSocketTask(with: testURL)
        
        testTask.resume()
        
        // Send a ping to test connectivity
        testTask.sendPing { error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(false, "Connection test failed: \(error.localizedDescription)")
                    self.connectionState = .failed(error.localizedDescription)
                } else {
                    completion(true, "Connection test successful! Server is reachable.")
                    self.connectionState = .disconnected // Reset to disconnected after test
                }
            }
            testTask.cancel()
        }
    }
}

// MARK: - URLSessionWebSocketDelegate
extension WebSocketGameManager: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        DispatchQueue.main.async {
            self.isConnected = true
            self.connectionError = nil
            self.connectionState = .connected
        }
        print("✅ WebSocket connected")
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectionState = .disconnected
        }
        print("❌ WebSocket disconnected")
    }
}

// MARK: - Helper Methods

private func parsePlayerState(_ data: [String: Any]) -> Player? {
    guard let id = data["id"] as? String,
          let name = data["name"] as? String else {
        return nil
    }
    
    let isHost = data["isHost"] as? Bool ?? false
    let teamId = data["teamId"] as? String
    
    var player = Player(id: id, name: name, teamId: teamId, isHost: isHost)
    
    if let locationData = data["location"] as? [String: Any],
       let latitude = locationData["latitude"] as? Double,
       let longitude = locationData["longitude"] as? Double {
        let heading = locationData["heading"] as? Double
        let speed = locationData["speed"] as? Double
        let timestamp = locationData["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970
        player.location = PlayerLocation(
            latitude: latitude,
            longitude: longitude,
            heading: heading,
            speed: speed,
            timestamp: Date(timeIntervalSince1970: timestamp / 1000)
        )
    }
    
    return player
}

private func parsePin(_ data: [String: Any]) -> Pin? {
    guard let id = data["id"] as? String,
          let typeRaw = data["type"] as? String,
          let coordinateData = data["coordinate"] as? [String: Any],
          let latitude = coordinateData["latitude"] as? Double,
          let longitude = coordinateData["longitude"] as? Double else {
        return nil
    }
    
    let coordinate = PinCoordinate(latitude: latitude, longitude: longitude)
    let playerId = data["playerId"] as? String
    let teamId = data["teamId"] as? String
    let timestamp = data["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970
    
    return Pin(
        id: id,
        type: typeRaw,
        name: data["name"] as? String ?? "",
        coordinate: coordinate,
        playerId: playerId ?? "",
        teamId: teamId,
        timestamp: Date(timeIntervalSince1970: timestamp / 1000)
    )
}