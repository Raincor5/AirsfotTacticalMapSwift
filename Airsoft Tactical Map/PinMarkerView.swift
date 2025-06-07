//
//  PinMarkerView.swift
//  Airsoft Tactical Map
//
//  Created by Jaroslavs Krots on 05/06/2025.
//

import SwiftUI

struct PinMarkerView: View {
    let pin: Pin
    let onRemove: () -> Void
    
    private var pinType: PinType {
        PinType(rawValue: pin.type) ?? .waypoint
    }
    
    var body: some View {
        Button(action: onRemove) {
            ZStack {
                // Pin background
                Circle()
                    .fill(pinType.color)
                    .frame(width: 30, height: 30)
                    .shadow(radius: 2)
                
                // Pin icon
                Image(systemName: pinType.systemImage)
                    .foregroundColor(.white)
                    .font(.system(size: 14, weight: .bold))
                
                // Pin name label
                Text(pin.name)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.9))
                    .cornerRadius(4)
                    .offset(y: 22)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    VStack(spacing: 20) {
        PinMarkerView(
            pin: Pin(
                type: "enemy",
                name: "Enemy",
                coordinate: PinCoordinate(latitude: 0, longitude: 0),
                playerId: "test"
            )
        ) { }
        
        PinMarkerView(
            pin: Pin(
                type: "objective",
                name: "Objective",
                coordinate: PinCoordinate(latitude: 0, longitude: 0),
                playerId: "test"
            )
        ) { }
        
        PinMarkerView(
            pin: Pin(
                type: "friendly",
                name: "Friendly",
                coordinate: PinCoordinate(latitude: 0, longitude: 0),
                playerId: "test"
            )
        ) { }
    }
    .padding()
} 