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
enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case failed(String)
}

// MARK: - Message Queue Item
struct QueuedMessage {
    let id = UUID()
    let message: [String: Any]
    let timestamp = Date()
    var retryCount = 0
    let maxRetries = 3
}

// MARK: - WebSocket Game Manager
class WebSocketGameManager: NSObject, ObservableObject, GameManagerProtocol {
    // MARK: - Published Properties
    @Published var gameSession: GameSession?
    @Published var currentUser: Player?
    @Published var isHost: Bool = false
    @Published var connectionState: ConnectionState = .disconnected
    @Published var connectionError: String?
    
    // Server configuration
    @Published var serverHost: String = ""
    @Published var serverPort: Int = 3001
    @Published var serverStatus: String = "Not connected"
    
    // MARK: - Private Properties
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var reconnectionTimer: Timer?
    private var heartbeatTimer: Timer?
    private var messageQueue: [QueuedMessage] = []
    private var lastHeartbeat: Date?
    private var reconnectionAttempts = 0
    private var maxReconnectionAttempts = 5
    private var heartbeatInterval: TimeInterval = 30.0
    private var reconnectionDelay: TimeInterval = 2.0
    private let notificationManager = PushNotificationManager.shared
    
    // Connection state tracking
    private var isManualDisconnect = false
    private var connectionStartTime: Date?
    
    override init() {
        super.init()
        setupURLSession()
        setupNotificationObservers()
    }
    
    deinit {
        disconnect(manual: true)
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Setup
    
    private func setupURLSession() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = true
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    @objc private func appDidEnterBackground() {
        // Notify server of app state change
        print("🌙 App entering background - notifying server")
        sendAppStateChange(state: "background")
        
        // Keep connection alive but reduce activity
        heartbeatInterval = 60.0 // Increase heartbeat interval for background
        restartHeartbeat()
    }
    
    @objc private func appWillEnterForeground() {
        print("☀️ App entering foreground")
        
        // Restore normal heartbeat interval
        heartbeatInterval = 30.0
        
        // CRITICAL: Force reconnection since iOS likely killed the WebSocket
        // Even if connectionState shows "connected", the actual socket is probably dead
        print("🔄 Forcing reconnection after background (iOS likely killed WebSocket)")
        
        // Clean up existing connection
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        stopHeartbeat()
        
        // Reset connection state and force reconnect
        updateConnectionState(.reconnecting)
        
        // Attempt immediate reconnection with our existing session
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.connectToServer { [weak self] success in
                if success {
                    // Rejoin our existing session if we have one
                    if let sessionCode = self?.sessionCode,
                       let playerId = self?.currentUser?.id,
                       let playerName = self?.currentUser?.name {
                        print("🔄 Rejoining session \(sessionCode) after reconnection")
                        self?.joinSession(code: sessionCode, playerId: playerId, playerName: playerName)
                    }
                    
                    // Notify server we're back
                    self?.sendAppStateChange(state: "active")
                    
                    // Request full sync to catch up on missed data
                    self?.requestFullSync()
                    
                    // Flush any queued messages
                    self?.flushQueuedMessages()
                } else {
                    print("❌ Failed to reconnect after foreground")
                }
            }
        }
    }
    
    // MARK: - Server Configuration
    
    func configureServer(host: String, port: Int = 3001) {
        self.serverHost = host
        self.serverPort = port
        self.serverStatus = "Server configured: \(host):\(port)"
        print("🔧 Server configured: \(host):\(port)")
    }
    
    func testConnection(completion: @escaping (Bool, String) -> Void) {
        guard !serverHost.isEmpty else {
            completion(false, "Server host not configured")
            return
        }
        
        serverStatus = "Testing connection..."
        
        connectToServer { [weak self] success in
            DispatchQueue.main.async {
                if success {
                    self?.serverStatus = "Connected to \(self?.serverHost ?? ""):\(self?.serverPort ?? 0)"
                    completion(true, "Connection successful")
                } else {
                    self?.serverStatus = "Connection failed"
                    completion(false, "Failed to connect to \(self?.serverHost ?? ""):\(self?.serverPort ?? 0)")
                }
            }
        }
    }
    
    // MARK: - Connection Management
    
    private func connectToServer(completion: @escaping (Bool) -> Void) {
        guard !serverHost.isEmpty else {
            updateConnectionState(.failed("Server host not configured"))
            completion(false)
            return
        }
        
        // Disconnect if already connected
        if webSocketTask != nil {
            disconnect()
        }
        
        // Build WebSocket URL
        let isNgrok = serverHost.contains(".ngrok") || serverHost.contains(".ngrok-free.app")
        let scheme = isNgrok ? "wss" : "ws"
        let urlString = isNgrok ? "\(scheme)://\(serverHost)" : "\(scheme)://\(serverHost):\(serverPort)"
        
        guard let url = URL(string: urlString) else {
            updateConnectionState(.failed("Invalid server URL"))
            completion(false)
            return
        }
        
        print("🔗 Connecting to WebSocket: \(urlString)")
        
        webSocketTask = urlSession?.webSocketTask(with: url)
        webSocketTask?.resume()
        
        startListening()
        
        // Send a ping to verify connection before marking as connected
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let testMessage = ["type": "ping", "timestamp": Date().timeIntervalSince1970] as [String: Any]
            
            do {
                let data = try JSONSerialization.data(withJSONObject: testMessage)
                let string = String(data: data, encoding: .utf8) ?? ""
                
                self.webSocketTask?.send(.string(string)) { error in
                    DispatchQueue.main.async {
                        if let error = error {
                            print("❌ Connection test failed: \(error)")
                            self.updateConnectionState(.failed("Connection test failed"))
                            completion(false)
                        } else {
                            print("✅ Connection verified")
                            self.updateConnectionState(.connected)
                            self.startHeartbeat()
                            completion(true)
                        }
                    }
                }
            } catch {
                print("❌ Failed to encode test message: \(error)")
                self.updateConnectionState(.failed("Connection test failed"))
                completion(false)
            }
        }
    }
    
    private func disconnect(manual: Bool = false) {
        isManualDisconnect = manual
        
        stopHeartbeat()
        stopReconnectionTimer()
        
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        
        if manual {
            updateConnectionState(.disconnected)
            clearSession()
        }
        
        print("🔌 WebSocket disconnected (manual: \(manual))")
    }
    
    private func updateConnectionState(_ newState: ConnectionState) {
        DispatchQueue.main.async {
            let oldState = self.connectionState
            self.connectionState = newState
            
            switch newState {
            case .connected:
                self.connectionError = nil
                self.reconnectionAttempts = 0
                self.processMessageQueue()
                print("✅ Connection established")
                
            case .failed(let error):
                self.connectionError = error
                print("❌ Connection failed: \(error)")
                
            case .reconnecting:
                print("🔄 Attempting to reconnect...")
                
            default:
                break
            }
            
            // Auto-reconnect if not manual disconnect
            if case .failed = newState, !self.isManualDisconnect {
                self.scheduleReconnection()
            }
        }
    }
    
    // MARK: - Reconnection Logic
    
    private func scheduleReconnection() {
        guard reconnectionAttempts < maxReconnectionAttempts else {
            updateConnectionState(.failed("Max reconnection attempts reached"))
            return
        }
        
        stopReconnectionTimer()
        
        let delay = reconnectionDelay * Double(reconnectionAttempts + 1)
        print("📅 Scheduling reconnection in \(delay) seconds (attempt \(reconnectionAttempts + 1)/\(maxReconnectionAttempts))")
        
        reconnectionTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.attemptReconnection()
        }
    }
    
    private func attemptReconnection() {
        guard !isManualDisconnect else { return }
        
        reconnectionAttempts += 1
        updateConnectionState(.reconnecting)
        
        connectToServer { [weak self] success in
            if !success {
                self?.updateConnectionState(.failed("Reconnection failed"))
            }
        }
    }
    
    private func stopReconnectionTimer() {
        reconnectionTimer?.invalidate()
        reconnectionTimer = nil
    }
    
    // MARK: - Message Handling
    
    private func startListening() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleWebSocketMessage(message)
                self?.startListening() // Continue listening
                
            case .failure(let error):
                print("❌ WebSocket receive error: \(error)")
                self?.handleConnectionError(error)
            }
        }
    }
    
    private func handleWebSocketMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            handleMessage(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                handleMessage(text)
            }
        @unknown default:
            break
        }
    }
    
    private func handleMessage(_ messageString: String) {
        guard let data = messageString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            print("❌ Invalid message format: \(messageString)")
            return
        }
        
        print("📥 Received \(type) message")
        
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
        case "playerJoined", "playerReconnected":
            handlePlayerJoined(data)
        case "playerLeft":
            handlePlayerLeft(data)
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
        case "realtimeSync":
            handleRealtimeSync(data)
        case "fullSync":
            handleFullSync(data)
        case "pong":
            handlePong(data)
        case "error":
            handleError(data)
        default:
            print("❌ Unknown message type: \(type)")
        }
    }
    
    // MARK: - Message Sending
    
    private func sendMessage(_ message: [String: Any]) {
        guard let webSocketTask = webSocketTask else {
            queueMessage(message)
            return
        }
        
        guard connectionState == .connected else {
            queueMessage(message)
            return
        }
        
        do {
            let data = try JSONSerialization.data(withJSONObject: message)
            let string = String(data: data, encoding: .utf8) ?? ""
            
            if let messageType = message["type"] as? String {
                print("📤 Sending \(messageType) message")
            }
            
            webSocketTask.send(.string(string)) { [weak self] error in
                if let error = error {
                    print("❌ Failed to send message: \(error)")
                    self?.queueMessage(message)
                } else {
                    if let messageType = message["type"] as? String {
                        print("✅ Successfully sent \(messageType) message")
                    }
                }
            }
        } catch {
            print("❌ Failed to encode message: \(error)")
            queueMessage(message)
        }
    }
    
    private func queueMessage(_ message: [String: Any]) {
        let queuedMessage = QueuedMessage(message: message)
        messageQueue.append(queuedMessage)
        print("📦 Message queued (queue size: \(messageQueue.count))")
    }
    
    private func processMessageQueue() {
        guard connectionState == .connected else { return }
        
        for (index, queuedMessage) in messageQueue.enumerated().reversed() {
            if queuedMessage.retryCount < queuedMessage.maxRetries {
                var updatedMessage = queuedMessage
                updatedMessage.retryCount += 1
                
                sendMessage(queuedMessage.message)
                messageQueue.remove(at: index)
            } else {
                print("❌ Dropping message after max retries")
                messageQueue.remove(at: index)
            }
        }
        
        if !messageQueue.isEmpty {
            print("✅ Processed message queue (\(messageQueue.count) items)")
        }
    }
    
    private func flushQueuedMessages() {
        print("📦 Flushing \(messageQueue.count) queued messages")
        processMessageQueue()
    }
    
    // MARK: - Heartbeat
    
    private func startHeartbeat() {
        stopHeartbeat()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            self?.sendHeartbeat()
        }
    }
    
    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }
    
    private func sendHeartbeat() {
        guard connectionState == .connected else { return }
        
        let heartbeat = ["type": "ping", "timestamp": Date().timeIntervalSince1970] as [String: Any]
        sendMessage(heartbeat)
        lastHeartbeat = Date()
    }
    
    private func handlePong(_ data: [String: Any]) {
        // Update connection health
        if let timestamp = data["timestamp"] as? TimeInterval {
            let latency = Date().timeIntervalSince1970 - timestamp
            print("💓 Heartbeat latency: \(Int(latency * 1000))ms")
        }
    }
    
    // MARK: - Error Handling
    
    private func handleConnectionError(_ error: Error) {
        print("❌ Connection error: \(error)")
        
        // Check if this is an iOS backgrounding error (common codes: 1006, 1001)
        let nsError = error as NSError
        let isBackgroundDisconnection = nsError.code == 1006 || nsError.code == 1001
        
        if isBackgroundDisconnection {
            print("🌙 Detected iOS background disconnection (code: \(nsError.code))")
            // Don't mark as failed - this is expected iOS behavior
            // The app will reconnect when returning to foreground
            updateConnectionState(.disconnected)
        } else if !isManualDisconnect {
            updateConnectionState(.failed(error.localizedDescription))
        }
    }
    
    // MARK: - Session Management
    
    func createSession(playerName: String) {
        guard !playerName.isEmpty else { return }
        
        let playerId = UUID().uuidString
        let player = Player(id: playerId, name: playerName, isHost: true)
        self.currentUser = player
        self.isHost = true
        
        connectToServer { [weak self] success in
            guard success else {
                self?.updateConnectionState(.failed("Failed to connect to server"))
                return
            }
            
            let message = [
                "type": "createSession",
                "playerName": playerName,
                "playerId": playerId
            ]
            
            self?.sendMessage(message)
        }
    }
    
    func joinSession(code: String, playerName: String) {
        guard !code.isEmpty && !playerName.isEmpty else { return }
        
        let playerId = UUID().uuidString
        let player = Player(id: playerId, name: playerName, isHost: false)
        self.currentUser = player
        self.isHost = false
        
        connectToServer { [weak self] success in
            guard success else {
                self?.updateConnectionState(.failed("Failed to connect to server"))
                return
            }
            
            let message = [
                "type": "joinSession", 
                "sessionCode": code.uppercased(),
                "playerName": playerName,
                "playerId": playerId
            ]
            
            self?.sendMessage(message)
        }
    }
    
    // Rejoin with existing player ID (for reconnections)
    func joinSession(code: String, playerId: String, playerName: String) {
        guard !code.isEmpty && !playerId.isEmpty && !playerName.isEmpty else { return }
        
        print("🔄 Rejoining session \(code) with existing player ID \(playerId)")
        
        let message = [
            "type": "joinSession", 
            "sessionCode": code.uppercased(),
            "playerName": playerName,
            "playerId": playerId
        ]
        
        sendMessage(message)
    }
    
    func endSession() {
        if let sessionCode = gameSession?.code {
            let message = [
                "type": "leaveSession",
                "sessionCode": sessionCode
            ]
            sendMessage(message)
        }
        
        disconnect(manual: true)
        clearSession()
    }
        
    private func clearSession() {
        DispatchQueue.main.async {
            self.gameSession = nil
            self.currentUser = nil
            self.isHost = false
        }
    }
    
    // MARK: - Game Actions
    
    func updatePlayerLocation(_ location: PlayerLocation) {
        guard let currentUser = currentUser,
              let sessionCode = gameSession?.code,
              connectionState == .connected else {
            print("❌ Cannot update location - missing requirements")
            print("  currentUser: \(currentUser?.name ?? "nil")")
            print("  sessionCode: \(sessionCode ?? "nil")")
            print("  connectionState: \(connectionState)")
            return
        }
        
        print("📍 Updating location for \(currentUser.name) (isHost: \(isHost))")
        print("  📊 Location: \(location.latitude), \(location.longitude)")
        print("  🧭 Heading: \(location.heading ?? 0)°")
        
        // Update local user
        updateLocalPlayerLocation(location)
        
        // Send comprehensive location data to server
        let message = [
            "type": "locationUpdate",
            "sessionCode": sessionCode,
            "playerId": currentUser.id,
            "location": [
                "latitude": location.latitude,
                "longitude": location.longitude,
                "heading": location.heading ?? 0,
                "altitude": location.altitude ?? 0,
                "accuracy": location.accuracy ?? 0,
                "speed": location.speed ?? 0,
                "timestamp": ISO8601DateFormatter().string(from: location.timestamp)
            ]
        ] as [String: Any]
        
        print("📤 Sending enhanced location update with heading to server")
        sendMessage(message)
    }
    
    private func updateLocalPlayerLocation(_ location: PlayerLocation) {
        self.currentUser?.location = location
        
        if var session = gameSession,
           let currentUser = currentUser {
            var updatedUser = currentUser
            updatedUser.location = location
            session.players[currentUser.id] = updatedUser
            self.gameSession = session
        }
    }
    
    func addPin(type: PinType, coordinate: PinCoordinate) {
        guard let currentUser = currentUser,
              let sessionCode = gameSession?.code,
              connectionState == .connected else { return }
        
        let pin = Pin(
            type: type.rawValue,
            name: type.displayName,
            coordinate: coordinate,
            playerId: currentUser.id,
            teamId: currentUser.teamId
        )
        
        // Add to local session
        addLocalPin(pin)
        
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
        ] as [String: Any]
        
        sendMessage(message)
    }
    
    private func addLocalPin(_ pin: Pin) {
        if var session = gameSession {
            if !session.pins.contains(where: { $0.id == pin.id }) {
                session.pins.append(pin)
                self.gameSession = session
            }
        }
    }
    
    func removePin(_ pinId: String) {
        guard connectionState == .connected else { return }
        
        // Remove from local session
        removeLocalPin(pinId)
        
        let message = [
            "type": "removePin",
            "pinId": pinId
        ]
        
        sendMessage(message)
    }
    
    private func removeLocalPin(_ pinId: String) {
        if var session = gameSession {
            session.pins.removeAll { $0.id == pinId }
            self.gameSession = session
        }
    }
    
    func sendGameMessage(_ text: String) {
        guard let currentUser = currentUser,
              connectionState == .connected else { return }
        
        let message = GameMessage(
            text: text,
            playerId: currentUser.id,
            playerName: currentUser.name,
            teamId: currentUser.teamId
        )
        
        // Add to local session
        addLocalMessage(message)
        
        let serverMessage = [
            "type": "sendMessage",
            "message": [
                "text": text,
                "teamId": currentUser.teamId as Any
            ]
        ] as [String: Any]
        
        sendMessage(serverMessage)
    }
    
    private func addLocalMessage(_ message: GameMessage) {
        if var session = gameSession {
            session.messages.append(message)
            self.gameSession = session
        }
    }
    
    func assignPlayerToTeam(_ playerId: String, teamId: String) {
        // Visual debugging for physical devices
        DispatchQueue.main.async {
            if !self.isHost {
                // Show alert for "not host" issue
                NotificationCenter.default.post(name: NSNotification.Name("ShowDebugAlert"), object: "❌ Team assignment failed: Not host")
                return
            }
            
            if self.connectionState != .connected {
                // Show alert for connection issue
                NotificationCenter.default.post(name: NSNotification.Name("ShowDebugAlert"), object: "❌ Not connected: \(self.connectionState)")
                return
            }
            
            // Show success alert
            NotificationCenter.default.post(name: NSNotification.Name("ShowDebugAlert"), object: "✅ Sending team assignment: \(playerId) → \(teamId)")
        }
        
        guard isHost else { return }
        guard connectionState == .connected else { return }
        
        let message = [
            "type": "assignTeam",
            "playerId": playerId,
            "teamId": teamId
        ]
        
        sendMessage(message)
    }
    
    // MARK: - Message Handlers
    
    private func handleSessionCreated(_ data: [String: Any]) {
        guard let sessionData = data["session"] as? [String: Any],
              let code = sessionData["code"] as? String,
              let currentUser = currentUser else { return }
        
        let session = createGameSession(from: sessionData)
        var updatedSession = session
        updatedSession.players[currentUser.id] = currentUser
        
        self.gameSession = updatedSession
        updateConnectionState(.connected)
        
        print("✅ Session created: \(code)")
    }
    
    private func handleSessionJoined(_ data: [String: Any]) {
        guard let sessionData = data["session"] as? [String: Any] else { return }
        
        let session = createGameSession(from: sessionData)
        self.gameSession = session
        updateConnectionState(.connected)
        
        print("✅ Joined session: \(session.code)")
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
            print("✅ Player joined: \(name)")
        }
    }
    
    private func handlePlayerLeft(_ data: [String: Any]) {
        guard let playerId = data["playerId"] as? String else { return }
        
        if var session = gameSession {
            let playerName = session.players[playerId]?.name ?? "Unknown"
            session.players.removeValue(forKey: playerId)
            self.gameSession = session
            print("👋 Player left: \(playerName)")
        }
    }
    
    private func handleLocationUpdate(_ data: [String: Any]) {
        guard let playerId = data["playerId"] as? String,
              let locationData = data["location"] as? [String: Any],
              let latitude = locationData["latitude"] as? Double,
              let longitude = locationData["longitude"] as? Double else { return }
        
        let heading = locationData["heading"] as? Double
        let location = PlayerLocation(latitude: latitude, longitude: longitude, heading: heading)
        
        if var session = gameSession,
           var player = session.players[playerId] {
            player.location = location
            session.players[playerId] = player
            self.gameSession = session
            
            print("📍 Location updated for \(player.name)")
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
        
        addLocalPin(pin)
        print("📍 Pin added: \(pin.name)")
    }
    
    private func handlePinRemoved(_ data: [String: Any]) {
        guard let pinId = data["pinId"] as? String else { return }
        
        removeLocalPin(pinId)
        print("📍 Pin removed: \(pinId)")
    }
    
    private func handleMessageReceived(_ data: [String: Any]) {
        guard let messageData = data["message"] as? [String: Any],
              let text = messageData["text"] as? String,
              let playerId = messageData["playerId"] as? String,
              let playerName = messageData["playerName"] as? String else { return }
        
        // Don't add our own messages
        if playerId == currentUser?.id { return }
        
        let teamId = messageData["teamId"] as? String
        let message = GameMessage(
            text: text,
            playerId: playerId,
            playerName: playerName,
            teamId: teamId
        )
        
        addLocalMessage(message)
        print("💬 Message received from \(playerName): \(text)")
        
        // Send push notification if in background
        if UIApplication.shared.applicationState == .background {
            notificationManager.sendTeamMessage(text, from: playerName, teamId: teamId)
        }
    }
    
    private func handleTeamAssigned(_ data: [String: Any]) {
        guard let playerId = data["playerId"] as? String,
              let teamId = data["teamId"] as? String else { return }
        
        if var session = gameSession {
            session.players[playerId]?.teamId = teamId
            
            // Update current user if it's them
            if playerId == currentUser?.id {
                currentUser?.teamId = teamId
            }
            
            self.gameSession = session
            print("🔄 Team assigned: \(playerId) -> \(teamId)")
        }
    }
    
    private func handleRealtimeSync(_ data: [String: Any]) {
        // Handle real-time sync data for positions and states
        if let playerPositions = data["playerPositions"] as? [String: [String: Any]] {
            updatePlayerPositions(playerPositions)
        }
        
        if let playerStates = data["playerStates"] as? [String: [String: Any]] {
            updatePlayerStates(playerStates)
        }
    }
    
    private func handleFullSync(_ data: [String: Any]) {
        // Handle full session sync
        if let sessionData = data["session"] as? [String: Any] {
            let session = createGameSession(from: sessionData)
            self.gameSession = session
            print("🔄 Full sync completed")
        }
    }
    
    private func updatePlayerPositions(_ positions: [String: [String: Any]]) {
        guard var session = gameSession else { return }
        
        for (playerId, positionData) in positions {
            if let latitude = positionData["latitude"] as? Double,
               let longitude = positionData["longitude"] as? Double,
               var player = session.players[playerId] {
                
                let heading = positionData["heading"] as? Double
                let altitude = positionData["altitude"] as? Double
                let accuracy = positionData["accuracy"] as? Double
                let speed = positionData["speed"] as? Double
                
                let location = PlayerLocation(
                    latitude: latitude,
                    longitude: longitude,
                    heading: heading,
                    altitude: altitude,
                    accuracy: accuracy,
                    speed: speed
                )
                
                player.location = location
                session.players[playerId] = player
            }
        }
        
        self.gameSession = session
    }
    
    private func updatePlayerStates(_ states: [String: [String: Any]]) {
        // Update player states (health, ammo, etc.) if needed in the future
        // This is for extensibility
    }
    
    private func sendAppStateChange(state: String) {
        let message = [
            "type": "appStateChange",
            "state": state
        ]
        sendMessage(message)
    }
    
    private func requestFullSync() {
        let message = [
            "type": "syncRequest"
        ]
        sendMessage(message)
    }
    
    private func restartHeartbeat() {
        stopHeartbeat()
        startHeartbeat()
    }
    
    private func handleError(_ data: [String: Any]) {
        let message = data["message"] as? String ?? "Unknown error"
        updateConnectionState(.failed(message))
        print("❌ Server error: \(message)")
    }
    
    // MARK: - Helper Methods
    
    private func createGameSession(from data: [String: Any]) -> GameSession {
        let id = data["id"] as? String ?? UUID().uuidString
        let code = data["code"] as? String ?? ""
        let name = data["name"] as? String ?? "Game Session"
        let hostId = data["hostPlayerId"] as? String ?? ""
        
        var session = GameSession(id: id, code: code, name: name, hostId: hostId)
        
        // Add players
        if let players = data["players"] as? [[String: Any]] {
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
                        player.location = PlayerLocation(latitude: latitude, longitude: longitude, heading: heading)
                    }
                    
                    session.players[id] = player
                }
            }
        }
        
        // Add pins
        if let pins = data["pins"] as? [[String: Any]] {
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
        
        // Add messages
        if let messages = data["messages"] as? [[String: Any]] {
            for messageData in messages {
                if let id = messageData["id"] as? String,
                   let text = messageData["text"] as? String,
                   let playerId = messageData["playerId"] as? String,
                   let playerName = messageData["playerName"] as? String {
                    
                    let teamId = messageData["teamId"] as? String
                    let timestampString = messageData["timestamp"] as? String
                    let timestamp = timestampString.flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
                    
                    let message = GameMessage(
                        id: id,
                        text: text,
                        playerId: playerId,
                        playerName: playerName,
                        teamId: teamId,
                        timestamp: timestamp
                    )
                    
                    session.messages.append(message)
                }
            }
        }
        
        return session
    }
    
    // MARK: - Computed Properties
    
    var isConnected: Bool {
        connectionState == .connected
    }
    
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
        print("✅ WebSocket connection opened")
        updateConnectionState(.connected)
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("❌ WebSocket connection closed (code: \(closeCode.rawValue))")
        
        if !isManualDisconnect {
            updateConnectionState(.failed("Connection closed by server"))
        }
    }
} 