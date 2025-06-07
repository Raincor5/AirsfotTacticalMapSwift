//
//  ChatView.swift
//  Airsoft Tactical Map
//
//  Created by Jaroslavs Krots on 05/06/2025.
//

import SwiftUI

struct ChatView<GameManager: GameManagerProtocol>: View {
    @ObservedObject var gameManager: GameManager
    @Environment(\.presentationMode) var presentationMode
    @State private var messageText = ""
    
    var body: some View {
        NavigationView {
            ZStack {
                // Dark background
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Image(systemName: "text.bubble.fill")
                            .foregroundColor(.green)
                            .font(.title2)
                        
                        Text("TACTICAL COMMS")
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Button("CLOSE") {
                            presentationMode.wrappedValue.dismiss()
                        }
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.green)
                    }
                    .padding()
                    .background(Color.black.opacity(0.8))
                    .overlay(
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(.green.opacity(0.3)),
                        alignment: .bottom
                    )
                    
                    // Messages List
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if let messages = gameManager.gameSession?.messages {
                                ForEach(messages) { message in
                                    TacticalMessageRowView(
                                        message: message,
                                        isCurrentUser: message.playerId == gameManager.currentUser?.id
                                    )
                                }
                            } else {
                                VStack(spacing: 16) {
                                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                                        .font(.system(size: 40))
                                        .foregroundColor(.gray)
                                    
                                    Text("NO TRANSMISSIONS")
                                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                                        .foregroundColor(.gray)
                                    
                                    Text("No messages received yet")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(.gray.opacity(0.7))
                                }
                                .padding()
                            }
                        }
                        .padding()
                    }
                    .background(Color.black)
                    
                    // Message Input
                    VStack(spacing: 0) {
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(.green.opacity(0.3))
                        
                        HStack(spacing: 12) {
                            TextField("TRANSMIT MESSAGE...", text: $messageText)
                                .font(.system(size: 16, weight: .medium, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.black.opacity(0.3))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.green.opacity(0.3), lineWidth: 1)
                                        )
                                )
                            
                            Button(action: {
                                if !messageText.trimmingCharacters(in: .whitespaces).isEmpty {
                                    gameManager.sendGameMessage(messageText)
                                    messageText = ""
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.title2)
                                    Text("SEND")
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                }
                                .foregroundColor(messageText.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : .black)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(messageText.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray.opacity(0.3) : Color.green)
                                )
                            }
                            .disabled(messageText.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        .padding()
                        .background(Color.black.opacity(0.8))
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .preferredColorScheme(.dark)
    }
}

struct TacticalMessageRowView: View {
    let message: GameMessage
    let isCurrentUser: Bool
    
    var body: some View {
        HStack {
            if isCurrentUser {
                Spacer()
            }
            
            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 6) {
                if !isCurrentUser {
                    HStack(spacing: 4) {
                        Image(systemName: "person.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        
                        Text(message.playerName)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                    }
                }
                
                Text(message.text)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isCurrentUser ? Color.blue.opacity(0.8) : Color.gray.opacity(0.2))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isCurrentUser ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    )
                    .foregroundColor(isCurrentUser ? .white : .white)
                
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    
                    Text(formatTime(message.timestamp))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.gray)
                    
                    if isCurrentUser {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
            }
            
            if !isCurrentUser {
                Spacer()
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    ChatView<WebSocketGameManager>(gameManager: WebSocketGameManager())
} 