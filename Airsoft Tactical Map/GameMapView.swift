//
//  GameMapView.swift
//  Airsoft Tactical Map
//
//  Created by Jaroslavs Krots on 05/06/2025.
//

import SwiftUI
import MapKit

struct GameMapView<GameManager: GameManagerProtocol>: View {
    @ObservedObject var gameManager: GameManager
    @ObservedObject var locationManager: LocationManager
    
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    
    @State private var showingSessionInfo = false
    @State private var showingPinSelector = false
    @State private var showingQuickMessages = false
    @State private var showingChat = false
    @State private var showingTeamManager = false
    @State private var showingTacticalAlerts = false
    @State private var pendingPinCoordinate: CLLocationCoordinate2D?
    @State private var pulseScale: CGFloat = 1.0
    @State private var hasInitiallySetRegion = false
    @State private var shouldAutoCenter = true
    
    var body: some View {
        ZStack {
            // Map
            Map(coordinateRegion: $mapRegion, annotationItems: allMapItems) { item in
                MapAnnotation(coordinate: item.coordinate) {
                    switch item {
                    case .player(let player, _, let isCurrentUser):
                        PlayerMarkerView(
                            player: player,
                            isCurrentUser: isCurrentUser,
                            currentUserTeamId: gameManager.currentUser?.teamId,
                            teams: gameManager.gameSession?.teams ?? []
                        )
                    case .pin(let pin, _):
                        PinMarkerView(pin: pin) {
                            gameManager.removePin(pin.id)
                        }
                    }
                }
            }
            .onTapGesture {
                // Disable auto-centering when user taps the map
                shouldAutoCenter = false
            }
            .simultaneousGesture(
                DragGesture()
                    .onChanged { _ in
                        // Disable auto-centering when user pans the map
                        shouldAutoCenter = false
                    }
            )
            
            // Tactical crosshair for pin placement
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    ZStack {
                        // Outer ring
                        Circle()
                            .stroke(Color.green.opacity(0.8), lineWidth: 2)
                            .frame(width: 40, height: 40)
                        
                        // Inner crosshair
                        Image(systemName: "plus")
                            .font(.title2)
                            .foregroundColor(.green)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.7))
                                    .frame(width: 20, height: 20)
                            )
                        
                        // Animated pulse
                        Circle()
                            .stroke(Color.green.opacity(0.3), lineWidth: 1)
                            .frame(width: 60, height: 60)
                            .scaleEffect(pulseScale)
                            .animation(
                                Animation.easeInOut(duration: 1.5)
                                    .repeatForever(autoreverses: true),
                                value: pulseScale
                            )
                    }
                    Spacer()
                }
                Spacer()
            }
            .allowsHitTesting(false)
            .onAppear {
                pulseScale = 1.2
            }
            .onAppear {
                if !hasInitiallySetRegion {
                updateMapRegion()
                    hasInitiallySetRegion = true
                }
            }
            .onChange(of: locationManager.location) { _ in
                updatePlayerLocation()
                
                // Only auto-center on first location fix or if explicitly enabled
                if shouldAutoCenter && !hasInitiallySetRegion {
                    updateMapRegion()
                    hasInitiallySetRegion = true
                    shouldAutoCenter = false // Disable auto-centering after first time
                }
            }
            
            // UI Overlays
            VStack {
                // Top Bar
                HStack {
                    // Session Info Button
                    Button(action: { showingSessionInfo = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "shield.lefthalf.fill")
                                .font(.caption)
                            Text(gameManager.sessionCode ?? "N/A")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                            Divider()
                                .frame(height: 12)
                            Image(systemName: "person.2.fill")
                                .font(.caption)
                            Text("\(totalPlayerCount)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.8))
                        .foregroundColor(.green)
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.green.opacity(0.3), lineWidth: 1)
                        )
                    }
                    
                    Spacer()
                    
                    // Top-Right Button Stack (Chat & Quick Messages)
                    VStack(spacing: 8) {
                        // Chat Button
                        Button(action: { showingChat = true }) {
                            ZStack {
                                VStack(spacing: 2) {
                                    Image(systemName: "text.bubble.fill")
                                        .font(.title3)
                                    Text("CHAT")
                                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                                }
                                .foregroundColor(.black)
                                .frame(width: 50, height: 50)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.green, Color.green.opacity(0.8)]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color.green.opacity(0.3), lineWidth: 2)
                                )
                                .shadow(color: .green.opacity(0.3), radius: 3)
                                
                                // Unread message indicator
                                if hasUnreadMessages {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 12, height: 12)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white, lineWidth: 1)
                                        )
                                        .offset(x: 15, y: -15)
                                }
                            }
                        }
                        
                        // Quick Messages Button
                        Button(action: { showingQuickMessages = true }) {
                            VStack(spacing: 2) {
                                Image(systemName: "bolt.fill")
                                    .font(.title3)
                                Text("QUICK")
                                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                            }
                            .foregroundColor(.black)
                            .frame(width: 50, height: 50)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                            )
                            .shadow(color: .blue.opacity(0.3), radius: 3)
                        }
                    }
                    
                    // Connection Status
                    HStack(spacing: 4) {
                        if gameManager.isConnected {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundColor(.green)
                                .font(.title3)
                            Text("ONLINE")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                                .foregroundColor(.red)
                                .font(.title3)
                            Text("OFFLINE")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.red)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(12)
                }
                .padding()
                
                // Middle Right Side Controls (Pin & Alert)
                HStack {
                    Spacer()
                    
                    VStack(spacing: 12) {
                        // Pin Placement
                        Button(action: {
                            // Place pin at crosshair location (map center)
                            pendingPinCoordinate = mapRegion.center
                            showingPinSelector = true
                        }) {
                            VStack(spacing: 2) {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.title3)
                                Text("PIN")
                                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                            }
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.red, Color.red.opacity(0.8)]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.red.opacity(0.3), lineWidth: 2)
                            )
                            .shadow(color: .red.opacity(0.3), radius: 3)
                        }
                        
                        // Tactical Alerts
                        Button(action: { showingTacticalAlerts = true }) {
                            VStack(spacing: 2) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.title3)
                                Text("ALERT")
                                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                            }
                            .foregroundColor(.black)
                            .frame(width: 50, height: 50)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.yellow, Color.yellow.opacity(0.8)]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.yellow.opacity(0.3), lineWidth: 2)
                            )
                            .shadow(color: .yellow.opacity(0.3), radius: 3)
                        }
                    }
                    .padding(.trailing, 20)
                }
                
                Spacer()
                
                // Bottom Controls (Center & Teams)
                HStack {
                    Spacer()
                    
                    // Center on User
                    Button(action: centerOnUser) {
                        VStack(spacing: 2) {
                            Image(systemName: "scope")
                                .font(.title2)
                            Text("CENTER")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                        }
                        .foregroundColor(.white)
                        .frame(width: 55, height: 55)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.purple, Color.purple.opacity(0.8)]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.purple.opacity(0.3), lineWidth: 2)
                        )
                        .shadow(color: .purple.opacity(0.3), radius: 3)
                    }
                    
                    // Team Manager (Host only)
                    if gameManager.isHost {
                        Button(action: { showingTeamManager = true }) {
                            VStack(spacing: 2) {
                                Image(systemName: "person.3.sequence.fill")
                                    .font(.title2)
                                Text("TEAMS")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                            }
                            .foregroundColor(.black)
                            .frame(width: 55, height: 55)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.orange, Color.orange.opacity(0.8)]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.orange.opacity(0.3), lineWidth: 2)
                            )
                            .shadow(color: .orange.opacity(0.3), radius: 3)
                        }
                    }
                }
                .padding()
            }
            
            // Team Indicator
            if let currentUser = gameManager.currentUser,
               let teamId = currentUser.teamId,
               let team = gameManager.gameSession?.teams.first(where: { $0.id == teamId }) {
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Image(systemName: "shield.lefthalf.fill")
                                .font(.caption)
                                .foregroundColor(team.swiftUIColor)
                            
                            Text(team.name)
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(team.swiftUIColor.opacity(0.8), lineWidth: 2)
                        )
                        .shadow(color: team.swiftUIColor.opacity(0.3), radius: 3)
                        .padding(.trailing)
                    }
                    Spacer()
                }
                .padding(.top, 80)
            }
        }
        .sheet(isPresented: $showingSessionInfo) {
            SessionInfoView(gameManager: gameManager)
        }
        .sheet(isPresented: $showingPinSelector) {
            PinSelectorView { pinType in
                if let coordinate = pendingPinCoordinate {
                    gameManager.addPin(
                        type: pinType,
                        coordinate: PinCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
                    )
                }
                showingPinSelector = false
                pendingPinCoordinate = nil
            }
        }
        .sheet(isPresented: $showingQuickMessages) {
            QuickMessagesView { message in
                gameManager.sendGameMessage(message.displayText)
                showingQuickMessages = false
            }
        }
        .sheet(isPresented: $showingChat) {
            ChatView(gameManager: gameManager)
        }
        .sheet(isPresented: $showingTeamManager) {
            TeamManagerView(gameManager: gameManager)
        }
        .sheet(isPresented: $showingTacticalAlerts) {
            TacticalAlertsView(gameManager: gameManager, locationManager: locationManager)
        }
    }
    
    // MARK: - Computed Properties
    
    private var allMapItems: [MapAnnotationItem] {
        var items: [MapAnnotationItem] = []
        
        // Add current user
        if let currentUser = gameManager.currentUser,
           let location = locationManager.playerLocation {
            items.append(.player(
                player: currentUser,
                coordinate: location.coordinate,
                isCurrentUser: true
            ))
            print("🗺️ Added current user \(currentUser.name) to map with team: \(currentUser.teamId ?? "none")")
        }
        
        // Add other players (only teammates)
        let currentUserTeamId = gameManager.currentUser?.teamId
        for player in gameManager.otherPlayers {
            // Only show players on the same team (allies)
            if player.teamId == currentUserTeamId, 
               let teamId = currentUserTeamId, // Ensure current user has a team
               let location = player.location {
                items.append(.player(
                    player: player,
                    coordinate: location.coordinate,
                    isCurrentUser: false
                ))
                print("🗺️ Added teammate \(player.name) to map with team: \(player.teamId ?? "none")")
            } else if player.teamId != currentUserTeamId && player.location != nil {
                print("🚫 Hiding enemy \(player.name) from map (team: \(player.teamId ?? "none"))")
            } else if player.location == nil {
                print("⚠️ Player \(player.name) has no location, not showing on map")
            }
        }
        
        // Add pins
        if let pins = gameManager.gameSession?.pins {
            for pin in pins {
                items.append(.pin(
                    pin: pin,
                    coordinate: pin.coordinate.coreLocationCoordinate
                ))
            }
        }
        
        return items
    }
    
    private var totalPlayerCount: Int {
        1 + gameManager.otherPlayers.count
    }
    
    private var hasUnreadMessages: Bool {
        // This would track unread messages in a real implementation
        false
    }
    
    // MARK: - Actions
    
    private func updateMapRegion() {
        if let location = locationManager.location {
            mapRegion = MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }
    }
    
    private func updatePlayerLocation() {
        if let location = locationManager.playerLocation {
            gameManager.updatePlayerLocation(location)
        }
    }
    
    private func centerOnUser() {
        if let location = locationManager.location {
            withAnimation(.easeInOut(duration: 1.0)) {
                mapRegion = MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
            }
            // Re-enable auto-centering for a brief moment if user manually centers
            shouldAutoCenter = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                shouldAutoCenter = false
            }
        }
    }
    

    

}

// MARK: - Map Items

enum MapAnnotationItem: Identifiable {
    case player(player: Player, coordinate: CLLocationCoordinate2D, isCurrentUser: Bool)
    case pin(pin: Pin, coordinate: CLLocationCoordinate2D)
    
    var id: String {
        switch self {
        case .player(let player, _, _):
            return "player_\(player.id)"
        case .pin(let pin, _):
            return "pin_\(pin.id)"
        }
    }
    
    var coordinate: CLLocationCoordinate2D {
        switch self {
        case .player(_, let coordinate, _):
            return coordinate
        case .pin(_, let coordinate):
            return coordinate
        }
    }
}

#Preview {
    let gameManager = WebSocketGameManager()
    GameMapView(
        gameManager: gameManager,
        locationManager: LocationManager()
    )
} 