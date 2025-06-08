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
    @ObservedObject var networkManager: NetworkManager

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
    @State private var lastUpdateTime = Date()
    
    // Timer for periodic UI updates
    let updateTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    var body: some View {
        GeometryReader { geometry in
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
                    shouldAutoCenter = false
                }
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { _ in
                            shouldAutoCenter = false
                        }
                )
                .overlay(
                    VStack {
                        HStack {
                            NetworkStatsView(networkManager: networkManager)
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding()
                    .allowsHitTesting(false),
                    alignment: .topLeading
)
                // Tactical crosshair for pin placement
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        ZStack {
                            Circle()
                                .stroke(Color.green.opacity(0.8), lineWidth: 2)
                                .frame(width: 40, height: 40)
                            
                            Image(systemName: "plus")
                                .font(.title2)
                                .foregroundColor(.green)
                                .background(
                                    Circle()
                                        .fill(Color.black.opacity(0.7))
                                        .frame(width: 20, height: 20)
                                )
                            
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
                
                // UI Overlays - Responsive to screen size
                VStack(spacing: 0) {
                    // Top Bar
                    HStack(alignment: .top) {
                        // Session Info Button
                        Button(action: { showingSessionInfo = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "shield.lefthalf.filled")
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
                        
                        // Connection Status
                        HStack(spacing: 4) {
                            if gameManager.isConnected {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                Text("ONLINE")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                                    .foregroundColor(.red)
                                    .font(.caption)
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
                    .padding(.horizontal)
                    .padding(.top, geometry.safeAreaInsets.top > 0 ? 0 : 8)
                    
                    // Team Indicator
                    if let currentUser = gameManager.currentUser,
                       let teamId = currentUser.teamId,
                       let team = gameManager.gameSession?.teams.first(where: { $0.id == teamId }) {
                        HStack {
                            Spacer()
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(team.swiftUIColor)
                                    .frame(width: 12, height: 12)
                                
                                Text(team.name.uppercased())
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.8))
                            .cornerRadius(20)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(team.swiftUIColor.opacity(0.8), lineWidth: 2)
                            )
                            .shadow(color: team.swiftUIColor.opacity(0.3), radius: 3)
                            .padding(.trailing)
                        }
                        .padding(.top, 8)
                    }
                    
                    Spacer()
                    
                    // Bottom Control Panel - Ergonomic layout
                    VStack(spacing: 12) {
                        // Primary action buttons row
                        HStack(spacing: 12) {
                            // Chat Button
                            TacticalButton(
                                icon: "text.bubble.fill",
                                label: "CHAT",
                                color: .green,
                                hasNotification: hasUnreadMessages,
                                size: geometry.size.width < 380 ? .small : .medium
                            ) {
                                showingChat = true
                            }
                            
                            // Pin Placement
                            TacticalButton(
                                icon: "mappin.and.ellipse",
                                label: "PIN",
                                color: .red,
                                size: geometry.size.width < 380 ? .small : .medium
                            ) {
                                pendingPinCoordinate = mapRegion.center
                                showingPinSelector = true
                            }
                            
                            // Center on User
                            TacticalButton(
                                icon: "location.fill",
                                label: "CENTER",
                                color: .purple,
                                size: geometry.size.width < 380 ? .small : .medium
                            ) {
                                centerOnUser()
                            }
                            
                            // Team Manager (Host only)
                            if gameManager.isHost {
                                TacticalButton(
                                    icon: "person.3.fill",
                                    label: "TEAMS",
                                    color: .orange,
                                    size: geometry.size.width < 380 ? .small : .medium
                                ) {
                                    showingTeamManager = true
                                }
                            }
                        }
                        
                        // Secondary action buttons row
                        HStack(spacing: 12) {
                            // Quick Messages
                            TacticalButton(
                                icon: "bolt.fill",
                                label: "QUICK",
                                color: .blue,
                                size: .small
                            ) {
                                showingQuickMessages = true
                            }
                            
                            // Tactical Alerts
                            TacticalButton(
                                icon: "exclamationmark.triangle.fill",
                                label: "ALERT",
                                color: .yellow,
                                size: .small
                            ) {
                                showingTacticalAlerts = true
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, geometry.safeAreaInsets.bottom > 0 ? 0 : 16)
                }
            }
            .onAppear {
                if !hasInitiallySetRegion {
                    updateMapRegion()
                    hasInitiallySetRegion = true
                }
            }
            .onChange(of: locationManager.location) { _ in
                updatePlayerLocation()
                
                if shouldAutoCenter && !hasInitiallySetRegion {
                    updateMapRegion()
                    hasInitiallySetRegion = true
                    shouldAutoCenter = false
                }
            }
            .onReceive(updateTimer) { _ in
                // Force UI update periodically to ensure map annotations refresh
                lastUpdateTime = Date()
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
    
    // In GameMapView.swift, update the computed properties:

    private var allMapItems: [MapAnnotationItem] {
        var items: [MapAnnotationItem] = []
        
        // Try to use interpolated state from network manager first
        if let interpolatedState = networkManager.interpolatedState {
            // Add players from interpolated state
            for playerState in interpolatedState.players {
                if let position = playerState.position {
                    let location = PlayerLocation(
                        latitude: position.latitude,
                        longitude: position.longitude,
                        heading: position.heading,
                        altitude: nil,
                        accuracy: nil,
                        speed: position.speed,
                        timestamp: position.lastUpdate
                    )
                    
                    let player = Player(
                        id: playerState.id,
                        name: playerState.name,
                        teamId: playerState.teamId,
                        location: location,
                        isHost: playerState.isHost
                    )
                    
                    items.append(.player(
                        player: player,
                        coordinate: location.coordinate,
                        isCurrentUser: playerState.id == gameManager.currentUser?.id
                    ))
                }
            }
            
            // Add pins from interpolated state
            for pin in interpolatedState.pins {
                items.append(.pin(
                    pin: pin,
                    coordinate: pin.coordinate.coreLocationCoordinate
                ))
            }
        } else {
            // Fallback to game session data when network manager state is not available
            guard let session = gameManager.gameSession else {
                return items
            }
            
            // Add players from game session
            for player in session.players.values {
                if let location = player.location {
                    items.append(.player(
                        player: player,
                        coordinate: location.coordinate,
                        isCurrentUser: player.id == gameManager.currentUser?.id
                    ))
                }
            }
            
            // Add pins from game session
            for pin in session.pins {
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
        false // Implement unread message tracking
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
            withAnimation(.easeInOut(duration: 0.5)) {
                mapRegion = MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
            }
            shouldAutoCenter = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                shouldAutoCenter = false
            }
        }
    }
}

// MARK: - Tactical Button Component

struct TacticalButton: View {
    let icon: String
    let label: String
    let color: Color
    var hasNotification: Bool = false
    var size: ButtonSize = .medium
    
    let action: () -> Void
    
    enum ButtonSize {
        case small, medium
        
        var dimension: CGFloat {
            switch self {
            case .small: return 45
            case .medium: return 55
            }
        }
        
        var iconSize: Font {
            switch self {
            case .small: return .title3
            case .medium: return .title2
            }
        }
        
        var labelSize: CGFloat {
            switch self {
            case .small: return 7
            case .medium: return 8
            }
        }
    }
    
    var body: some View {
        Button(action: action) {
            ZStack {
                VStack(spacing: 2) {
                    Image(systemName: icon)
                        .font(size.iconSize)
                    Text(label)
                        .font(.system(size: size.labelSize, weight: .bold, design: .monospaced))
                }
                .foregroundColor(color == .yellow ? .black : .white)
                .frame(width: size.dimension, height: size.dimension)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [color, color.opacity(0.8)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(color.opacity(0.3), lineWidth: 2)
                )
                .shadow(color: color.opacity(0.3), radius: 3)
                
                if hasNotification {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 1)
                        )
                        .offset(x: size.dimension * 0.3, y: -size.dimension * 0.3)
                }
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
            return "player_\(player.id)_\(Date().timeIntervalSince1970)"
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
        locationManager: LocationManager(),
        networkManager: gameManager.networkManager
    )
}

