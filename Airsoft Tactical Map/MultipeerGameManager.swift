//
//  MultipeerGameManager.swift
//  Airsoft Tactical Map
//
//  Created by Jaroslavs Krots on 05/06/2025.
//

import Foundation
import MultipeerConnectivity
import Combine

// MARK: - Debug Session Store for Simulator Testing
class DebugSessionStore {
    static let shared = DebugSessionStore()
    private var sessions: [String: GameSession] = [:]
    
    func store(session: GameSession) {
        sessions[session.code] = session
        print("🐛 DEBUG: Stored session \(session.code)")
    }
    
    func find(code: String) -> GameSession? {
        let session = sessions[code.uppercased()]
        print("🐛 DEBUG: Looking for session \(code), found: \(session != nil)")
        return session
    }
    
    func remove(code: String) {
        sessions.removeValue(forKey: code.uppercased())
        print("🐛 DEBUG: Removed session \(code)")
    }
}

class MultipeerGameManager: NSObject, ObservableObject, GameManagerProtocol {
    @Published var gameSession: GameSession?
    @Published var currentUser: Player?
    @Published var isHost: Bool = false
    @Published var isConnected: Bool = false
    @Published var connectionError: String?
    @Published var nearbyPlayers: [String] = [] // Players discovered but not yet connected
    @Published var connectedPeers: [MCPeerID] = []
    
    // Check if running in simulator
    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
    
    private let serviceType = "tactical-map"
    private var peerID: MCPeerID
    private var mcSession: MCSession
    private var mcAdvertiserAssistant: MCAdvertiserAssistant?
    private var mcNearbyServiceBrowser: MCNearbyServiceBrowser?
    
    override init() {
        // Create peer ID with device name + random suffix for uniqueness
        let deviceName = UIDevice.current.name
        self.peerID = MCPeerID(displayName: "\(deviceName)_\(String(Int.random(in: 1000...9999)))")
        
        // Create session
        self.mcSession = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        
        super.init()
        
        mcSession.delegate = self
    }
    
    deinit {
        stopHosting()
        stopBrowsing()
        mcSession.disconnect()
    }
    
    // MARK: - Session Management
    
    func createSession(playerName: String) {
        let sessionCode = generateSessionCode()
        let player = Player(id: peerID.displayName, name: playerName, isHost: true)
        let session = GameSession(code: sessionCode, name: "Game \(sessionCode)", hostId: player.id)
        
        self.currentUser = player
        self.gameSession = session
        self.isHost = true
        
        // Add host to session
        var updatedSession = session
        updatedSession.players[player.id] = player
        self.gameSession = updatedSession
        
        // Store in debug mode for simulator testing
        if isSimulator {
            DebugSessionStore.shared.store(session: updatedSession)
            self.isConnected = true
            print("🐛 SIMULATOR: Session stored in debug mode")
        }
        
        startHosting()
        print("🎮 Started hosting session: \(sessionCode)")
    }
    
    private var searchingForSessionCode: String?
    
    func joinSession(code: String, playerName: String) {
        let player = Player(id: peerID.displayName, name: playerName, isHost: false)
        self.currentUser = player
        self.isHost = false
        self.searchingForSessionCode = code.uppercased()
        self.connectionError = nil
        
        // In simulator, try debug session store first
        if isSimulator {
            if let session = DebugSessionStore.shared.find(code: code) {
                var joinedSession = session
                joinedSession.players[player.id] = player
                self.gameSession = joinedSession
                self.isConnected = true
                self.searchingForSessionCode = nil
                
                // Update the stored session with new player
                DebugSessionStore.shared.store(session: joinedSession)
                
                print("🐛 SIMULATOR: Successfully joined session \(code) in debug mode")
                return
            } else {
                self.connectionError = "Session '\(code)' not found. Make sure the host has created the session first."
                print("🐛 SIMULATOR: Session \(code) not found in debug store")
                return
            }
        }
        
        startBrowsing()
        print("🔍 Looking for session with code: \(code)")
        
        // Set a timeout to stop searching if no session found
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            if !self.isConnected && self.searchingForSessionCode != nil {
                self.connectionError = "Session '\(code)' not found. Make sure the host has started the session."
                self.searchingForSessionCode = nil
                self.stopBrowsing()
                print("⏰ Session search timed out for code: \(code)")
            }
        }
    }
    
    func endSession() {
        // Clean up debug session if in simulator
        if isSimulator, let sessionCode = gameSession?.code {
            DebugSessionStore.shared.remove(code: sessionCode)
        }
        
        stopHosting()
        stopBrowsing()
        mcSession.disconnect()
        
        gameSession = nil
        currentUser = nil
        isHost = false
        connectedPeers.removeAll()
        nearbyPlayers.removeAll()
        isConnected = false
    }
    
    // MARK: - Multipeer Connectivity
    
    private func startHosting() {
        mcAdvertiserAssistant = MCAdvertiserAssistant(serviceType: serviceType, discoveryInfo: [
            "sessionCode": gameSession?.code ?? "",
            "hostName": currentUser?.name ?? ""
        ], session: mcSession)
        mcAdvertiserAssistant?.start()
        print("📡 Started advertising session")
    }
    
    private func stopHosting() {
        mcAdvertiserAssistant?.stop()
        mcAdvertiserAssistant = nil
    }
    
    private func startBrowsing() {
        mcNearbyServiceBrowser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        mcNearbyServiceBrowser?.delegate = self
        mcNearbyServiceBrowser?.startBrowsingForPeers()
        print("🔍 Started browsing for sessions")
    }
    
    private func stopBrowsing() {
        mcNearbyServiceBrowser?.stopBrowsingForPeers()
        mcNearbyServiceBrowser = nil
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
        
        // Send to connected peers
        let message: [String: Any] = [
            "type": "locationUpdate",
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
        
        // Add to local session
        if var session = gameSession {
            session.pins.append(pin)
            self.gameSession = session
        }
        
        // Send to connected peers
        let message: [String: Any] = [
            "type": "pinAdded",
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
        // Remove from local session
        if var session = gameSession {
            session.pins.removeAll { $0.id == pinId }
            self.gameSession = session
        }
        
        // Send to connected peers
        let message: [String: Any] = [
            "type": "pinRemoved",
            "pinId": pinId
        ]
        sendMessage(message)
    }
    
    func sendGameMessage(_ text: String) {
        guard let currentUser = currentUser else { return }
        
        let gameMessage = GameMessage(
            text: text,
            playerId: currentUser.id,
            playerName: currentUser.name,
            teamId: currentUser.teamId
        )
        
        // Add to local session
        if var session = gameSession {
            session.messages.append(gameMessage)
            self.gameSession = session
        }
        
        // Send to connected peers
        let message: [String: Any] = [
            "type": "messageReceived",
            "message": [
                "id": gameMessage.id,
                "text": gameMessage.text,
                "playerId": gameMessage.playerId,
                "playerName": gameMessage.playerName,
                "teamId": gameMessage.teamId as Any,
                "timestamp": ISO8601DateFormatter().string(from: gameMessage.timestamp)
            ]
        ]
        sendMessage(message)
    }
    
    func assignPlayerToTeam(_ playerId: String, teamId: String) {
        guard isHost else { 
            print("❌ Cannot assign player to team: Not host")
            return 
        }
        
        print("🔄 Assigning player \(playerId) to team \(teamId)")
        
        // Update local session first
        if var session = gameSession {
            if session.players[playerId] != nil {
                session.players[playerId]?.teamId = teamId
                print("✅ Updated local session for player \(playerId)")
                
                // Update current user if it's them - ensure both references are updated
                if playerId == currentUser?.id {
                    currentUser?.teamId = teamId
                    print("✅ Updated current user team assignment locally")
                }
                
                self.gameSession = session
            } else {
                print("❌ Player \(playerId) not found in session")
                return
            }
        }
        
        // Send to connected peers
        let message: [String: Any] = [
            "type": "teamAssignment",
            "playerId": playerId,
            "teamId": teamId
        ]
        sendMessage(message)
        print("📤 Sent team assignment message to peers")
        
        // Force UI update
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
        
        // Broadcast current location to ensure allies can see each other immediately
        if let currentUser = self.currentUser, let location = currentUser.location {
            self.updatePlayerLocation(location)
        }
    }
    
    // MARK: - Message Handling
    
    private func sendMessage(_ message: [String: Any]) {
        guard !connectedPeers.isEmpty else { return }
        
        do {
            let data = try JSONSerialization.data(withJSONObject: message)
            try mcSession.send(data, toPeers: connectedPeers, with: .reliable)
        } catch {
            print("❌ Failed to send message: \(error)")
            connectionError = "Failed to send message: \(error.localizedDescription)"
        }
    }
    
    private func handleReceivedMessage(_ data: Data) {
        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let type = json?["type"] as? String else { return }
            
            DispatchQueue.main.async {
                self.processMessage(type: type, data: json ?? [:])
            }
        } catch {
            print("❌ Failed to parse message: \(error)")
        }
    }
    
    private func processMessage(type: String, data: [String: Any]) {
        switch type {
        case "locationUpdate":
            handleLocationUpdate(data)
        case "pinAdded":
            handlePinAdded(data)
        case "pinRemoved":
            handlePinRemoved(data)
        case "messageReceived":
            handleMessageReceived(data)
        case "teamAssignment":
            handleTeamAssignment(data)
        case "playerJoined":
            handlePlayerJoined(data)
        case "sessionInfo":
            handleSessionInfo(data)
        default:
            print("Unknown message type: \(type)")
        }
    }
    
    // MARK: - Message Handlers
    
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
            print("📍 Updated location for player \(playerId)")
            
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
              let id = messageData["id"] as? String,
              let text = messageData["text"] as? String,
              let playerId = messageData["playerId"] as? String,
              let playerName = messageData["playerName"] as? String else { return }
        
        let teamId = messageData["teamId"] as? String
        
        let message = GameMessage(
            id: id,
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
            }
        }
    }
    
    private func handleTeamAssignment(_ data: [String: Any]) {
        guard let playerId = data["playerId"] as? String,
              let teamId = data["teamId"] as? String else { return }
        
        print("🔄 Handling team assignment: Player \(playerId) to team \(teamId)")
        
        if var session = gameSession {
            // Update in session players dictionary
            if session.players[playerId] != nil {
                session.players[playerId]?.teamId = teamId
                print("✅ Updated player \(playerId) in session")
            }
            
            // Update current user if it's them and ensure both references are updated
            if playerId == currentUser?.id {
                currentUser?.teamId = teamId
                // Also update in session to maintain consistency
                session.players[playerId]?.teamId = teamId
                print("✅ Updated current user team assignment")
            }
            
            self.gameSession = session
            
            // Force UI update
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
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
        
        // Add player to session
        if var session = gameSession {
            session.players[id] = player
            self.gameSession = session
            print("✅ Added player \(name) to session with location: \(player.location != nil)")
        }
        
        // If we're the host, send back all existing players' data to the new joiner
        if isHost && id != currentUser?.id {
            sendAllPlayersDataTo(newPeerId: nil) // Send to all peers including the new one
        }
    }
    
    private func handleSessionInfo(_ data: [String: Any]) {
        guard let sessionData = data["session"] as? [String: Any],
              let code = sessionData["code"] as? String,
              let name = sessionData["name"] as? String,
              let hostId = sessionData["hostId"] as? String else { 
            print("❌ Multipeer: Invalid sessionInfo data structure")
            return 
        }
        
        // Debug: Check what data we received
        let teamsCount = (sessionData["teams"] as? [Any])?.count ?? 0
        let pinsCount = (sessionData["pins"] as? [Any])?.count ?? 0
        let messagesCount = (sessionData["messages"] as? [Any])?.count ?? 0
        print("📥 Multipeer: Received session info for \(code) - \(teamsCount) teams, \(pinsCount) pins, \(messagesCount) messages")
        
        var session = GameSession(code: code, name: name, hostId: hostId)
        
        // Add teams
        if let teamsData = sessionData["teams"] as? [[String: Any]] {
            for teamData in teamsData {
                if let id = teamData["id"] as? String,
                   let name = teamData["name"] as? String,
                   let color = teamData["color"] as? String {
                    let team = Team(id: id, name: name, color: color)
                    session.teams.append(team)
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
        
        // Add current user to session
        if let currentUser = self.currentUser {
            session.players[currentUser.id] = currentUser
        }
        
        self.gameSession = session
        print("✅ Joined session: \(code) with \(session.teams.count) teams, \(session.pins.count) pins, \(session.messages.count) messages")
    }
    
    // MARK: - Utilities
    
    private func generateSessionCode() -> String {
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<6).map { _ in letters.randomElement()! })
    }
    
    private func sendAllPlayersDataTo(newPeerId: MCPeerID?) {
        guard let session = gameSession else { return }
        
        // Send all existing players' current data to all peers (or specific peer)
        for player in session.players.values {
            // Skip sending the joining player's data back to themselves
            if let newPeer = newPeerId, player.id == newPeer.displayName {
                continue
            }
            
            var playerData: [String: Any] = [
                "id": player.id,
                "name": player.name,
                "isHost": player.isHost,
                "teamId": player.teamId as Any
            ]
            
            // Include location if available
            if let location = player.location {
                playerData["location"] = [
                    "latitude": location.latitude,
                    "longitude": location.longitude,
                    "heading": location.heading ?? 0,
                    "timestamp": ISO8601DateFormatter().string(from: location.timestamp)
                ]
            }
            
            let playerMessage: [String: Any] = [
                "type": "playerJoined",
                "player": playerData
            ]
            
            if let targetPeer = newPeerId {
                // Send to specific peer
                do {
                    let data = try JSONSerialization.data(withJSONObject: playerMessage)
                    try mcSession.send(data, toPeers: [targetPeer], with: .reliable)
                } catch {
                    print("❌ Failed to send player data to new peer: \(error)")
                }
            } else {
                // Send to all peers
                sendMessage(playerMessage)
            }
        }
        
        print("📤 Sent all players' data (\(session.players.count) players)")
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

// MARK: - MCSessionDelegate
extension MultipeerGameManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                print("✅ Connected to: \(peerID.displayName)")
                if !self.connectedPeers.contains(peerID) {
                    self.connectedPeers.append(peerID)
                }
                self.isConnected = true
                self.connectionError = nil
                
                // Clear search when connected as a client
                if !self.isHost {
                    self.searchingForSessionCode = nil
                    self.stopBrowsing()
                }
                
                // Send session info and current player info to newly connected peer
                if let currentUser = self.currentUser {
                    if self.isHost, let session = self.gameSession {
                        // Host sends full session info to joining player
                        let sessionMessage: [String: Any] = [
                            "type": "sessionInfo",
                            "session": [
                                "code": session.code,
                                "name": session.name,
                                "hostId": session.hostId,
                                "teams": session.teams.map { team in
                                    [
                                        "id": team.id,
                                        "name": team.name,
                                        "color": team.color
                                    ]
                                },
                                "pins": session.pins.map { pin in
                                    [
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
                                },
                                "messages": session.messages.map { message in
                                    [
                                        "id": message.id,
                                        "text": message.text,
                                        "playerId": message.playerId,
                                        "playerName": message.playerName,
                                        "teamId": message.teamId as Any,
                                        "timestamp": ISO8601DateFormatter().string(from: message.timestamp)
                                    ]
                                }
                            ]
                        ]
                        self.sendMessage(sessionMessage)
                        
                        // Send all existing players' data to the new peer
                        self.sendAllPlayersDataTo(newPeerId: peerID)
                    }
                    
                    // Send full player data including location
                    var playerData: [String: Any] = [
                        "id": currentUser.id,
                        "name": currentUser.name,
                        "isHost": currentUser.isHost,
                        "teamId": currentUser.teamId as Any
                    ]
                    
                    // Include location if available
                    if let location = currentUser.location {
                        playerData["location"] = [
                            "latitude": location.latitude,
                            "longitude": location.longitude,
                            "heading": location.heading ?? 0,
                            "timestamp": ISO8601DateFormatter().string(from: location.timestamp)
                        ]
                    }
                    
                    let playerMessage: [String: Any] = [
                        "type": "playerJoined",
                        "player": playerData
                    ]
                    self.sendMessage(playerMessage)
                }
                
            case .connecting:
                print("🔄 Connecting to: \(peerID.displayName)")
                
            case .notConnected:
                print("❌ Disconnected from: \(peerID.displayName)")
                self.connectedPeers.removeAll { $0 == peerID }
                if self.connectedPeers.isEmpty {
                    self.isConnected = false
                }
                
                // Remove player from session
                if var gameSession = self.gameSession {
                    gameSession.players.removeValue(forKey: peerID.displayName)
                    self.gameSession = gameSession
                }
                
            @unknown default:
                break
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        handleReceivedMessage(data)
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Not used for this app
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // Not used for this app
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // Not used for this app
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension MultipeerGameManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        print("🔍 Found peer: \(peerID.displayName) with info: \(info ?? [:])")
        
        // Only join if we're looking for a session and the session code matches
        if !isHost, let searchCode = searchingForSessionCode {
            if let sessionCode = info?["sessionCode"], 
               sessionCode.uppercased() == searchCode {
                print("✅ Found matching session! Code: \(sessionCode)")
                print("📱 Inviting peer: \(peerID.displayName)")
                browser.invitePeer(peerID, to: mcSession, withContext: nil, timeout: 10)
            } else {
                print("❌ Session code mismatch. Expected: \(searchCode), Found: \(info?["sessionCode"] ?? "none")")
            }
        } else if !isHost {
            print("❌ Not searching for any session code")
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("❌ Lost peer: \(peerID.displayName)")
        DispatchQueue.main.async {
            self.nearbyPlayers.removeAll { $0 == peerID.displayName }
        }
    }
} 