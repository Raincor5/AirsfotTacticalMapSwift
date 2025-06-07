//
//  PinSelectorView.swift
//  Airsoft Tactical Map
//
//  Created by Jaroslavs Krots on 05/06/2025.
//

import SwiftUI

struct PinSelectorView: View {
    let onPinSelected: (PinType) -> Void
    @Environment(\.presentationMode) var presentationMode
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Add Tactical Pin")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.top)
                
                Text("Select a pin type to place on the map")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(PinType.allCases, id: \.self) { pinType in
                        Button(action: {
                            onPinSelected(pinType)
                        }) {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(pinType.color)
                                        .frame(width: 60, height: 60)
                                        .shadow(radius: 2)
                                    
                                    Image(systemName: pinType.systemImage)
                                        .foregroundColor(.white)
                                        .font(.title2)
                                }
                                
                                Text(pinType.displayName)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationBarItems(
                trailing: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
}

#Preview {
    PinSelectorView { pinType in
        print("Selected pin type: \(pinType)")
    }
} 