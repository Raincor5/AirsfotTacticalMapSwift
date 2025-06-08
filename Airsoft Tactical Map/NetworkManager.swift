// NetworkManager.swift
import Foundation
import Combine

class NetworkManager: ObservableObject {
    @Published var currentSnapshot: GameSnapshot?
    @Published var interpolatedState: GameSnapshot?
    @Published var serverTick: Int = 0
    @Published var lastAcknowledgedInput: Int = 0
    
    private var inputSequence: Int = 0
    @Published var pendingInputs: [ServerInput] = []
    private var snapshotBuffer: [GameSnapshot] = []
    private var interpolationTime: TimeInterval = 0
    
    private let interpolationDelay: TimeInterval = 0.1 // 100ms
    private var updateTimer: Timer?
    
    // WebSocket communication callback - set by GameManager
    var sendToServer: (([String: Any]) -> Void)?
    
    // Callback for when message is successfully sent
    var onMessageSent: ((Int) -> Void)?
    
    // Current user ID for input acknowledgment
    var currentUserId: String?
    
    func startInterpolation() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { _ in
            self.interpolate()
        }
    }
    
    func sendInput(type: String, data: InputData) -> Int {
        inputSequence += 1
        let input = ServerInput(
            sequence: inputSequence,
            type: type,
            data: data,
            timestamp: Date()
        )
        
        pendingInputs.append(input)
        
        // Convert to server message format based on input type
        let serverMessage = convertToServerMessage(type: type, data: data, sequence: inputSequence)
        
        // Send to server via callback
        sendToServer?(serverMessage)
        
        // Note: In proper authoritative server setup, we wait for server acknowledgment
        // The server will send back acknowledgments and state updates
        
        return inputSequence
    }
    
    private func convertToServerMessage(type: String, data: InputData, sequence: Int) -> [String: Any] {
        switch type {
        case "move":
            // Convert to locationUpdate message
            var locationData: [String: Any] = [:]
            if let latitude = data.latitude {
                locationData["latitude"] = latitude
            }
            if let longitude = data.longitude {
                locationData["longitude"] = longitude
            }
            if let heading = data.heading {
                locationData["heading"] = heading
            }
            if let speed = data.speed {
                locationData["speed"] = speed
            }
            if let timestamp = data.timestamp {
                locationData["timestamp"] = ISO8601DateFormatter().string(from: timestamp)
            }
            
            return [
                "type": "locationUpdate",
                "location": locationData
            ]
            
        case "addPin":
            // Convert to addPin message
            guard let position = data.position, let pinType = data.type else {
                return ["type": "error", "message": "Invalid pin data"]
            }
            
            let pin: [String: Any] = [
                "id": UUID().uuidString,
                "type": pinType,
                "name": pinType.capitalized,
                "coordinate": [
                    "latitude": position.latitude,
                    "longitude": position.longitude
                ]
            ]
            
            return [
                "type": "addPin",
                "pin": pin
            ]
            
        case "removePin":
            // Convert to removePin message
            guard let pinId = data.pinId else {
                return ["type": "error", "message": "Invalid pin ID"]
            }
            
            return [
                "type": "removePin",
                "pinId": pinId
            ]
            
        default:
            // Fallback to input wrapper for unknown types
            let inputDict: [String: Any] = [
                "sequence": sequence,
                "type": type,
                "data": convertInputDataToDictionary(data),
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ]
            
            return ["type": "input", "data": inputDict]
        }
    }
    
    private func convertInputDataToDictionary(_ inputData: InputData) -> [String: Any] {
        var dict: [String: Any] = [:]
        
        if let latitude = inputData.latitude {
            dict["latitude"] = latitude
        }
        if let longitude = inputData.longitude {
            dict["longitude"] = longitude
        }
        if let heading = inputData.heading {
            dict["heading"] = heading
        }
        if let speed = inputData.speed {
            dict["speed"] = speed
        }
        if let timestamp = inputData.timestamp {
            dict["timestamp"] = ISO8601DateFormatter().string(from: timestamp)
        }
        if let type = inputData.type {
            dict["type"] = type
        }
        if let position = inputData.position {
            dict["position"] = [
                "latitude": position.latitude,
                "longitude": position.longitude
            ]
        }
        if let pinId = inputData.pinId {
            dict["pinId"] = pinId
        }
        
        return dict
    }
    
    func handleSnapshot(_ snapshot: GameSnapshot) {
        currentSnapshot = snapshot
        serverTick = snapshot.tick
        
        // Add to buffer for interpolation
        snapshotBuffer.append(snapshot)
        
        // Keep only recent snapshots
        let cutoffTime = Date().timeIntervalSince1970 - 2.0
        snapshotBuffer.removeAll { 
            $0.timestamp.timeIntervalSince1970 < cutoffTime 
        }
        
        // Remove acknowledged inputs
        if let lastProcessed = getLastProcessedInput(for: currentUserId) {
            pendingInputs.removeAll { $0.sequence <= lastProcessed }
        }
    }
    
    func handleDelta(_ delta: GameDelta) {
        guard var snapshot = currentSnapshot else { return }
        
        // Apply delta changes
        for (playerId, playerState) in delta.changes.players {
            if let index = snapshot.players.firstIndex(where: { $0.id == playerId }) {
                var mutableSnapshot = snapshot
                mutableSnapshot.players[index] = playerState
                snapshot = mutableSnapshot
            }
        }
        
        // Apply pin changes
        for pin in delta.changes.pins.added {
            if !snapshot.pins.contains(where: { $0.id == pin.id }) {
                var mutableSnapshot = snapshot
                mutableSnapshot.pins.append(pin)
                snapshot = mutableSnapshot
            }
        }
        
        for pinId in delta.changes.pins.removed {
            var mutableSnapshot = snapshot
            mutableSnapshot.pins.removeAll { $0.id == pinId }
            snapshot = mutableSnapshot
        }
        
        currentSnapshot = snapshot
        serverTick = delta.toTick
    }
    
    private func getLastProcessedInput(for userId: String?) -> Int? {
        // This would typically come from server acknowledgments
        // For now, return the last acknowledged input sequence
        return lastAcknowledgedInput > 0 ? lastAcknowledgedInput : nil
    }
    
    private func interpolate() {
        // Client-side interpolation between snapshots
        let renderTime = Date().timeIntervalSince1970 - interpolationDelay
        
        // Find two snapshots to interpolate between
        guard snapshotBuffer.count >= 2 else { 
            interpolatedState = currentSnapshot
            return 
        }
        
        var older: GameSnapshot?
        var newer: GameSnapshot?
        
        for i in 0..<(snapshotBuffer.count - 1) {
            if snapshotBuffer[i].timestamp.timeIntervalSince1970 <= renderTime &&
               snapshotBuffer[i + 1].timestamp.timeIntervalSince1970 >= renderTime {
                older = snapshotBuffer[i]
                newer = snapshotBuffer[i + 1]
                break
            }
        }
        
        guard let from = older, let to = newer else {
            interpolatedState = currentSnapshot
            return
        }
        
        // Interpolate between snapshots
        let alpha = (renderTime - from.timestamp.timeIntervalSince1970) / 
                   (to.timestamp.timeIntervalSince1970 - from.timestamp.timeIntervalSince1970)
        
        interpolatedState = interpolateSnapshots(from: from, to: to, alpha: alpha)
    }
    
    private func interpolateSnapshots(from: GameSnapshot, to: GameSnapshot, alpha: Double) -> GameSnapshot {
        // Implement interpolation logic
        var interpolated = to
        
        // Interpolate player positions
        let interpolatedPlayers = to.players.map { toPlayer in
            guard let fromPlayer = from.players.first(where: { $0.id == toPlayer.id }),
                  let fromPos = fromPlayer.position,
                  let toPos = toPlayer.position else {
                return toPlayer
            }
            
            var player = toPlayer
            player.position = PlayerPosition(
                latitude: fromPos.latitude + (toPos.latitude - fromPos.latitude) * alpha,
                longitude: fromPos.longitude + (toPos.longitude - fromPos.longitude) * alpha,
                heading: interpolateAngle(from: fromPos.heading, to: toPos.heading, alpha: alpha),
                speed: fromPos.speed + (toPos.speed - fromPos.speed) * alpha,
                lastUpdate: toPos.lastUpdate,
                clientTimestamp: toPos.clientTimestamp
            )
            
            return player
        }
        
        // Create a new GameSnapshot with interpolated data
        interpolated = GameSnapshot(
            tick: interpolated.tick,
            timestamp: interpolated.timestamp,
            players: interpolatedPlayers,
            pins: interpolated.pins,
            objectives: interpolated.objectives,
            gamePhase: interpolated.gamePhase,
            scores: interpolated.scores
        )
        
        return interpolated
    }
    
    private func interpolateAngle(from: Double, to: Double, alpha: Double) -> Double {
        var diff = to - from
        if diff > 180 { diff -= 360 }
        if diff < -180 { diff += 360 }
        return from + diff * alpha
    }
}