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

class WebSocketGameManager: NSObject, ObservableObject, GameManagerProtocol {
    @Published var gameSession: GameSession?
    @Published var currentUser: Player?
    @Published var isHost: Bool = false
    @Published var isConnected: Bool = false
    @Published var connectionError: String?
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private let notificationManager = PushNotificationManager.shared
    
    // Server configuration
    private let serverHost = "192.168.1.200" // Change to your Mac's IP
    private let serverPort = 3001
    
    override init() {
        super.init()
        setupURLSession()
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
        connectToServer { [weak self] success in
            guard success else { return }
            
            let player = Player(id: UUID().uuidString, name: playerName, isHost: true)
            self?.currentUser = player
            self?.isHost = true
            
            let message = [
                "type": "createSession",
                "playerName": playerName,
                "playerId": player.id
            ]
            
            self?.sendMessage(message)
        }
    }
    
    func joinSession(code: String, playerName: String) {
        connectToServer { [weak self] success in
            guard success else { return }
            
            let player = Player(id: UUID().uuidString, name: playerName, isHost: false)
            self?.currentUser = player
            self?.isHost = false
            
            let message = [
                "type": "joinSession", 
                "sessionCode": code.uppercased(),
                "playerName": playerName,
                "playerId": player.id
            ]
            
            self?.sendMessage(message)
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
        }
    }
    
    // MARK: - Game Actions
    
    func updatePlayerLocation(_ location: PlayerLocation) {
        guard let currentUser = currentUser,
              let sessionCode = gameSession?.code else { return }
        
        // Update local user first
        self.currentUser?.location = location
        if var session = gameSession {
            session.players[currentUser.id]?.location = location
            self.gameSession = session
            print("📍 WebSocket: Updated local location for \(currentUser.name)")
        }
        
        let message = [
            "type": "locationUpdate",
            "sessionCode": sessionCode,
            "playerId": currentUser.id,
            "location": [
                "latitude": location.latitude,
                "longitude": location.longitude,
                "heading": location.heading ?? 0,
                "timestamp": ISO8601DateFormatter().string(from: location.timestamp)
            ]
        ] as [String : Any]
        
        sendMessage(message)
    }
    
    func addPin(type: PinType, coordinate: PinCoordinate) {
        guard let currentUser = currentUser,
              let sessionCode = gameSession?.code else { return }
        
        let pin = Pin(
            type: type.rawValue,
            name: type.displayName,
            coordinate: coordinate,
            playerId: currentUser.id,
            teamId: currentUser.teamId
        )
        
        // Add to local session first
        if var session = gameSession {
            session.pins.append(pin)
            self.gameSession = session
            print("📍 WebSocket: Added pin locally: \(pin.name)")
        }
        
        let message = [
            "type": "addPin",
            "sessionCode": sessionCode,
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
        ] as [String : Any]
        
        sendMessage(message)
    }
    
    func removePin(_ pinId: String) {
        guard let sessionCode = gameSession?.code else { return }
        
        let message = [
            "type": "removePin",
            "sessionCode": sessionCode,
            "pinId": pinId
        ]
        
        sendMessage(message)
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
            completion(true)
            return
        }
        
        let url = URL(string: "ws://\(serverHost):\(serverPort)")!
        webSocketTask = urlSession?.webSocketTask(with: url)
        
        DispatchQueue.main.async {
            self.connectionError = nil
        }
        
        webSocketTask?.resume()
        startListening()
        
        // Wait a moment for connection
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            completion(self.webSocketTask != nil)
        }
    }
    
    private func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        
        DispatchQueue.main.async {
            self.isConnected = false
        }
    }
    
    private func startListening() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self?.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                
                // Continue listening
                self?.startListening()
                
            case .failure(let error):
                DispatchQueue.main.async {
                    self?.connectionError = "Connection lost: \(error.localizedDescription)"
                    self?.isConnected = false
                }
            }
        }
    }
    
    private func sendMessage(_ message: [String: Any]) {
        guard let webSocketTask = webSocketTask else { return }
        
        do {
            let data = try JSONSerialization.data(withJSONObject: message)
            let string = String(data: data, encoding: .utf8) ?? ""
            
            webSocketTask.send(.string(string)) { error in
                if let error = error {
                    DispatchQueue.main.async {
                        self.connectionError = "Failed to send message: \(error.localizedDescription)"
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.connectionError = "Failed to encode message: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Message Handling
    
    private func handleMessage(_ messageString: String) {
        guard let data = messageString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }
        
        DispatchQueue.main.async {
            self.processMessage(type: type, data: json)
        }
    }
    
    private func processMessage(type: String, data: [String: Any]) {
        switch type {
        case "sessionCreated":
            handleSessionCreated(data)
        case "sessionJoined":
            handleSessionJoined(data)
        case "playerJoined":
            handlePlayerJoined(data)
        case "locationUpdate":
            handleLocationUpdate(data)
        case "pinAdded":
            handlePinAdded(data)
        case "pinRemoved":
            handlePinRemoved(data)
        case "messageReceived":
            handleMessageReceived(data)
        case "teamAssigned":
            handleTeamAssigned(data)
        case "error":
            handleError(data)
        default:
            print("Unknown message type: \(type)")
        }
    }
    
    // MARK: - Message Handlers
    
    private func handleSessionCreated(_ data: [String: Any]) {
        guard let sessionCode = data["sessionCode"] as? String,
              let currentUser = currentUser else { return }
        
        let session = GameSession(code: sessionCode, name: "Game \(sessionCode)", hostId: currentUser.id)
        var updatedSession = session
        updatedSession.players[currentUser.id] = currentUser
        
        self.gameSession = updatedSession
        self.isConnected = true
        
        print("✅ Session created: \(sessionCode)")
    }
    
    private func handleSessionJoined(_ data: [String: Any]) {
        guard let sessionData = data["session"] as? [String: Any],
              let code = sessionData["code"] as? String,
              let name = sessionData["name"] as? String,
              let hostId = sessionData["hostId"] as? String else { 
            print("❌ WebSocket: Invalid sessionJoined data structure")
            return 
        }
        
        // Debug: Check what data we received
        let playersCount = (sessionData["players"] as? [Any])?.count ?? 0
        let pinsCount = (sessionData["pins"] as? [Any])?.count ?? 0
        let messagesCount = (sessionData["messages"] as? [Any])?.count ?? 0
        print("📥 WebSocket: Received session data - \(playersCount) players, \(pinsCount) pins, \(messagesCount) messages")
        
        var session = GameSession(code: code, name: name, hostId: hostId)
        
        // Add current user
        if let currentUser = self.currentUser {
            session.players[currentUser.id] = currentUser
        }
        
        // Add existing players
        if let players = sessionData["players"] as? [[String: Any]] {
            for playerData in players {
                if let id = playerData["id"] as? String,
                   let name = playerData["name"] as? String,
                   let isHost = playerData["isHost"] as? Bool {
                    let teamId = playerData["teamId"] as? String
                    var player = Player(id: id, name: name, teamId: teamId, isHost: isHost)
                    
                    // Add location if available
                    if let locationData = playerData["location"] as? [String: Any],
                       let latitude = locationData["latitude"] as? Double,
                       let longitude = locationData["longitude"] as? Double {
                        let heading = locationData["heading"] as? Double
                        let location = PlayerLocation(latitude: latitude, longitude: longitude, heading: heading)
                        player.location = location
                    }
                    
                    session.players[id] = player
                }
            }
        }
        
        // Add existing pins
        if let pins = sessionData["pins"] as? [[String: Any]] {
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
                        name: name,
                        coordinate: coordinate,
                        playerId: playerId,
                        teamId: teamId
                    )
                    
                    session.pins.append(pin)
                }
            }
        }
        
        // Add existing messages
        if let messages = sessionData["messages"] as? [[String: Any]] {
            for messageData in messages {
                if let text = messageData["text"] as? String,
                   let playerId = messageData["playerId"] as? String,
                   let playerName = messageData["playerName"] as? String {
                    let teamId = messageData["teamId"] as? String
                    
                    let message = GameMessage(
                        text: text,
                        playerId: playerId,
                        playerName: playerName,
                        teamId: teamId
                    )
                    
                    session.messages.append(message)
                }
            }
        }
        
        self.gameSession = session
        self.isConnected = true
        
        print("✅ Joined session: \(code) with \(session.players.count) players, \(session.pins.count) pins, \(session.messages.count) messages")
    }
    
    private func handlePlayerJoined(_ data: [String: Any]) {
        guard let playerData = data["player"] as? [String: Any],
              let id = playerData["id"] as? String,
              let name = playerData["name"] as? String,
              let isHost = playerData["isHost"] as? Bool else { return }
        
        let teamId = playerData["teamId"] as? String
        var player = Player(id: id, name: name, teamId: teamId, isHost: isHost)
        
        // Add location if available
        if let locationData = playerData["location"] as? [String: Any],
           let latitude = locationData["latitude"] as? Double,
           let longitude = locationData["longitude"] as? Double {
            let heading = locationData["heading"] as? Double
            let location = PlayerLocation(latitude: latitude, longitude: longitude, heading: heading)
            player.location = location
        }
        
        if var session = gameSession {
            session.players[id] = player
            self.gameSession = session
            print("✅ WebSocket: Added player \(name) to session with location: \(player.location != nil)")
            
            if player.location == nil {
                print("⚠️ WebSocket: Player \(name) joined without location data - they may not have started sharing location yet")
            }
        }
    }
    
    private func handleLocationUpdate(_ data: [String: Any]) {
        guard let playerId = data["playerId"] as? String,
              let locationData = data["location"] as? [String: Any],
              let latitude = locationData["latitude"] as? Double,
              let longitude = locationData["longitude"] as? Double else { return }
        
        let heading = locationData["heading"] as? Double
        let location = PlayerLocation(latitude: latitude, longitude: longitude, heading: heading)
        
        if var session = gameSession {
            session.players[playerId]?.location = location
            self.gameSession = session
            print("📍 WebSocket: Updated location for player \(playerId)")
            
            // Force UI update to refresh map annotations
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
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
            name: name,
            coordinate: coordinate,
            playerId: playerId,
            teamId: teamId
        )
        
        if var session = gameSession {
            // Avoid duplicates
            if !session.pins.contains(where: { $0.id == pin.id }) {
                session.pins.append(pin)
                self.gameSession = session
                print("📍 WebSocket: Added pin from server: \(pin.name)")
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
    
    private func handleError(_ data: [String: Any]) {
        let message = data["message"] as? String ?? "Unknown error"
        self.connectionError = message
        print("❌ Server error: \(message)")
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
}

// MARK: - URLSessionWebSocketDelegate
extension WebSocketGameManager: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        DispatchQueue.main.async {
            self.isConnected = true
            self.connectionError = nil
        }
        print("✅ WebSocket connected")
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        DispatchQueue.main.async {
            self.isConnected = false
        }
        print("❌ WebSocket disconnected")
    }
} 