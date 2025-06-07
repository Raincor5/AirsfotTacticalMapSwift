//
//  SetupView.swift
//  Airsoft Tactical Map
//
//  Created by Jaroslavs Krots on 05/06/2025.
//

import SwiftUI

struct SetupView<GameManager: GameManagerProtocol>: View {
    @ObservedObject var gameManager: GameManager
    @State private var playerName = ""
    @State private var sessionCode = ""
    @State private var showingCreateOptions = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Dark gradient background
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black,
                        Color.gray.opacity(0.3),
                        Color.black
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                // Tactical grid pattern overlay
                TacticalGridView()
                    .opacity(0.1)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: geometry.size.height < 700 ? 20 : 30) {
                        Spacer(minLength: geometry.size.height < 700 ? 30 : 50)
                        
                        // Title Section - responsive sizing
                        VStack(spacing: geometry.size.height < 700 ? 6 : 10) {
                            Image(systemName: "scope")
                                .font(.system(size: geometry.size.height < 700 ? 45 : 60))
                                .foregroundColor(.green)
                                .shadow(color: .green.opacity(0.5), radius: 10)
                            
                            Text("AIRSOFT")
                                .font(.system(size: geometry.size.height < 700 ? 26 : 32, weight: .black, design: .monospaced))
                                .foregroundColor(.white)
                                .shadow(color: .black, radius: 2)
                            
                            Text("TACTICAL MAP")
                                .font(.system(size: geometry.size.height < 700 ? 18 : 24, weight: .bold, design: .monospaced))
                                .foregroundColor(.green)
                                .shadow(color: .green.opacity(0.3), radius: 5)
                            
                            // Simulator debug mode indicator
                            #if targetEnvironment(simulator)
                            Text("SIMULATOR DEBUG MODE")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.2))
                                .cornerRadius(4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.orange.opacity(0.5), lineWidth: 1)
                                )
                            #endif
                        }
                        .padding(.bottom, geometry.size.height < 700 ? 12 : 20)
                        
                        // Player Name Input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("CALLSIGN")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)
                            
                            TextField("Enter your callsign", text: $playerName)
                                .textFieldStyle(TacticalTextFieldStyle())
                                .autocapitalization(.words)
                                .disableAutocorrection(true)
                        }
                        .padding(.horizontal, 20)
                        
                        // Action Buttons
                        VStack(spacing: geometry.size.height < 700 ? 10 : 15) {
                            // Create Session Button
                            Button(action: {
                                showingCreateOptions = true
                            }) {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .font(geometry.size.height < 700 ? .title3 : .title2)
                                    Text("CREATE OPERATION")
                                        .font(.system(size: geometry.size.height < 700 ? 14 : 16, weight: .bold, design: .monospaced))
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: geometry.size.height < 700 ? 48 : 56)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.green, Color.green.opacity(0.8)]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .foregroundColor(.black)
                                .cornerRadius(12)
                                .shadow(color: .green.opacity(0.3), radius: 5)
                            }
                            .disabled(playerName.isEmpty)
                            .opacity(playerName.isEmpty ? 0.5 : 1.0)
                            
                            // Join Session Section
                            VStack(spacing: geometry.size.height < 700 ? 8 : 12) {
                                Text("JOIN EXISTING OPERATION")
                                    .font(.system(size: geometry.size.height < 700 ? 11 : 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.gray)
                                
                                TextField("OPERATION CODE", text: $sessionCode)
                                    .textFieldStyle(TacticalTextFieldStyle())
                                    .autocapitalization(.allCharacters)
                                    .disableAutocorrection(true)
                                
                                Button(action: {
                                    gameManager.joinSession(code: sessionCode, playerName: playerName)
                                }) {
                                    HStack {
                                        Image(systemName: "person.badge.plus")
                                            .font(geometry.size.height < 700 ? .title3 : .title2)
                                        Text("JOIN OPERATION")
                                            .font(.system(size: geometry.size.height < 700 ? 14 : 16, weight: .bold, design: .monospaced))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: geometry.size.height < 700 ? 48 : 56)
                                    .background(
                                        LinearGradient(
                                            gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                                    .shadow(color: .blue.opacity(0.3), radius: 5)
                                }
                                .disabled(playerName.isEmpty || sessionCode.isEmpty)
                                .opacity(playerName.isEmpty || sessionCode.isEmpty ? 0.5 : 1.0)
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Connection Status
                        if gameManager.gameSession == nil && !sessionCode.isEmpty && !playerName.isEmpty {
                            VStack(spacing: 10) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .green))
                                    .scaleEffect(1.2)
                                
                                Text("SEARCHING FOR OPERATION...")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.green)
                                
                                Text("Looking for session: \(sessionCode)")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(.gray)
                            }
                            .padding()
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(12)
                            .padding(.horizontal, 20)
                        }
                        
                        // Error Display
                        if let error = gameManager.connectionError {
                            VStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                    .font(.title2)
                                
                                Text("CONNECTION ERROR")
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundColor(.red)
                                
                                Text(error)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                            }
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.red.opacity(0.3), lineWidth: 1)
                            )
                            .padding(.horizontal, 20)
                        }
                        
                        Spacer(minLength: 50)
                    }
                }
            }
        }
        .confirmationDialog("Create Operation", isPresented: $showingCreateOptions, titleVisibility: .visible) {
            Button("Host Operation") {
                gameManager.createSession(playerName: playerName)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Start a new tactical operation and share the code with your team.")
        }
    }
}

struct TacticalTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: 16, weight: .medium, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.green.opacity(0.3), lineWidth: 1)
                    )
            )
    }
}

struct TacticalGridView: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 20
            let cols = Int(size.width / spacing) + 1
            let rows = Int(size.height / spacing) + 1
            
            for col in 0..<cols {
                for row in 0..<rows {
                    let x = CGFloat(col) * spacing
                    let y = CGFloat(row) * spacing
                    let point = CGPoint(x: x, y: y)
                    
                    context.fill(
                        Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)),
                        with: .color(.green.opacity(0.3))
                    )
                }
            }
        }
    }
}

#Preview {
    SetupView<MultipeerGameManager>(gameManager: MultipeerGameManager())
} 