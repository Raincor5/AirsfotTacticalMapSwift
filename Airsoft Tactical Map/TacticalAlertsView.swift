//
//  TacticalAlertsView.swift
//  Airsoft Tactical Map
//
//  Created by Jaroslavs Krots on 05/06/2025.
//

import SwiftUI
import CoreLocation

struct TacticalAlertsView<GameManager: GameManagerProtocol>: View {
    @ObservedObject var gameManager: GameManager
    @ObservedObject var locationManager: LocationManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedAlertType: TacticalAlertType = .enemySpotted
    @State private var customMessage: String = ""
    @State private var urgencyLevel: Urgency = .medium
    @State private var includeCoordinates: Bool = true
    
    private let notificationManager = PushNotificationManager.shared
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    
                    Text("Tactical Alert")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Send urgent updates to your team")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top)
                
                ScrollView {
                    VStack(spacing: 24) {
                        
                        // Alert Type Selection
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Alert Type")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                                ForEach(TacticalAlertType.allCases, id: \.self) { alertType in
                                    AlertTypeCard(
                                        alertType: alertType,
                                        isSelected: selectedAlertType == alertType
                                    ) {
                                        selectedAlertType = alertType
                                        // Auto-fill custom message based on alert type
                                        customMessage = getDefaultMessage(for: alertType)
                                    }
                                }
                            }
                        }
                        
                        // Custom Message
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Message Details")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            TextField("Additional details...", text: $customMessage)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(5)
                        }
                        
                        // Urgency Level
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Urgency Level")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            HStack(spacing: 12) {
                                ForEach(Urgency.allCases, id: \.self) { urgency in
                                    UrgencyButton(
                                        urgency: urgency,
                                        isSelected: urgencyLevel == urgency
                                    ) {
                                        urgencyLevel = urgency
                                    }
                                }
                            }
                        }
                        
                        // Coordinates Toggle
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Include My Coordinates", isOn: $includeCoordinates)
                                .font(.headline)
                            
                            if includeCoordinates, let location = locationManager.location {
                                Text("📍 \(location.coordinate.latitude, specifier: "%.4f"), \(location.coordinate.longitude, specifier: "%.4f")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 8)
                            }
                        }
                        
                        // Send Button
                        Button(action: sendTacticalAlert) {
                            HStack {
                                Image(systemName: "paperplane.fill")
                                Text("Send Alert")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(urgencyLevel.color.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(customMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(leading: 
                Button("Cancel") {
                    dismiss()
                }
            )
        }
        .onAppear {
            customMessage = getDefaultMessage(for: selectedAlertType)
        }
    }
    
    // MARK: - Actions
    
    private func sendTacticalAlert() {
        let coordinates: (latitude: Double, longitude: Double)? = includeCoordinates ? 
            locationManager.location.map { ($0.coordinate.latitude, $0.coordinate.longitude) } : nil
        
        let alert = TacticalAlert(
            title: selectedAlertType.displayName,
            body: customMessage,
            type: selectedAlertType,
            urgency: urgencyLevel,
            coordinates: coordinates,
            teamId: gameManager.currentUser?.teamId
        )
        
        // Send as local notification to team (for MultipeerConnectivity)
        notificationManager.sendTacticalAlert(alert)
        
        // Safety check: Only send game message if we have a current user and are connected
        if gameManager.currentUser != nil && gameManager.isConnected {
            let alertMessage = "🚨 \(selectedAlertType.displayName.uppercased()): \(customMessage)"
            gameManager.sendGameMessage(alertMessage)
            print("🚨 Tactical alert sent: \(selectedAlertType.displayName)")
        } else {
            print("⚠️ Cannot send tactical alert - no current user or not connected")
            print("   Current user: \(gameManager.currentUser?.name ?? "nil")")
            print("   Connected: \(gameManager.isConnected)")
        }
        
        dismiss()
    }
    
    private func getDefaultMessage(for alertType: TacticalAlertType) -> String {
        switch alertType {
        case .enemySpotted:
            return "Enemy forces spotted in area"
        case .objectiveCaptured:
            return "Objective secured - awaiting further orders"
        case .rallyPoint:
            return "Rally point established at coordinates"
        case .casualty:
            return "Team member down - need medical assistance"
        case .ammunition:
            return "Running low on ammunition"
        case .retreat:
            return "Tactical retreat in progress"
        case .advance:
            return "Moving to advance position"
        case .regroup:
            return "All units regroup at designated position"
        }
    }
}

// MARK: - Alert Type Card

struct AlertTypeCard: View {
    let alertType: TacticalAlertType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: alertType.iconName)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : .primary)
                
                Text(alertType.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white : .primary)
                    .multilineTextAlignment(.center)
            }
            .frame(height: 80)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue : Color.secondary.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Urgency Button

struct UrgencyButton: View {
    let urgency: Urgency
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(urgency.displayName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : urgency.color)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? urgency.color : urgency.color.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(urgency.color, lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Extensions

extension TacticalAlertType {
    var displayName: String {
        switch self {
        case .enemySpotted: return "Enemy Spotted"
        case .objectiveCaptured: return "Objective Captured"
        case .rallyPoint: return "Rally Point"
        case .casualty: return "Casualty"
        case .ammunition: return "Ammunition"
        case .retreat: return "Retreat"
        case .advance: return "Advance"
        case .regroup: return "Regroup"
        }
    }
    
    var iconName: String {
        switch self {
        case .enemySpotted: return "eye.fill"
        case .objectiveCaptured: return "flag.fill"
        case .rallyPoint: return "location.fill"
        case .casualty: return "cross.fill"
        case .ammunition: return "circle.dotted"
        case .retreat: return "arrow.backward"
        case .advance: return "arrow.forward"
        case .regroup: return "arrow.triangle.merge"
        }
    }
}

extension Urgency {
    var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"  
        case .high: return "High"
        case .critical: return "Critical"
        }
    }
    
    var color: Color {
        switch self {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .orange
        case .critical: return .red
        }
    }
}

#Preview {
    TacticalAlertsView(
        gameManager: WebSocketGameManager(),
        locationManager: LocationManager()
    )
} 