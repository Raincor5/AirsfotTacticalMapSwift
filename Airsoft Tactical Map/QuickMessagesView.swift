//
//  QuickMessagesView.swift
//  Airsoft Tactical Map
//
//  Created by Jaroslavs Krots on 05/06/2025.
//

import SwiftUI

struct QuickMessagesView: View {
    let onMessageSelected: (QuickMessage) -> Void
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Text("Quick Messages")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding()
                
                Text("Send a quick tactical message to your team")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.bottom)
                
                List(QuickMessage.allCases, id: \.self) { message in
                    Button(action: {
                        onMessageSelected(message)
                    }) {
                        HStack {
                            // Message icon
                            Image(systemName: iconForMessage(message))
                                .foregroundColor(colorForMessage(message))
                                .font(.title2)
                                .frame(width: 30)
                            
                            // Message text
                            Text(message.displayText)
                                .font(.body)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            // Arrow
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .listStyle(PlainListStyle())
            }
            .navigationBarItems(
                trailing: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
    
    private func iconForMessage(_ message: QuickMessage) -> String {
        switch message {
        case .moving:
            return "figure.walk"
        case .inPosition:
            return "checkmark.circle.fill"
        case .needBackup:
            return "exclamationmark.triangle.fill"
        case .enemySpotted:
            return "eye.fill"
        case .allClear:
            return "checkmark.shield.fill"
        case .objective:
            return "target"
        }
    }
    
    private func colorForMessage(_ message: QuickMessage) -> Color {
        switch message {
        case .moving:
            return .blue
        case .inPosition:
            return .green
        case .needBackup:
            return .red
        case .enemySpotted:
            return .orange
        case .allClear:
            return .green
        case .objective:
            return .purple
        }
    }
}

#Preview {
    QuickMessagesView { message in
        print("Selected message: \(message.displayText)")
    }
} 