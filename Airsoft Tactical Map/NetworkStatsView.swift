// NetworkStatsView.swift
import SwiftUI

struct NetworkStatsView: View {
    @ObservedObject var networkManager: NetworkManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Server Tick: \(networkManager.serverTick)")
                .font(.system(size: 10, design: .monospaced))
            Text("Last Ack: \(networkManager.lastAcknowledgedInput)")
                .font(.system(size: 10, design: .monospaced))
            Text("Pending: \(networkManager.pendingInputs.count)")
                .font(.system(size: 10, design: .monospaced))
        }
        .padding(8)
        .background(Color.black.opacity(0.7))
        .foregroundColor(.green)
        .cornerRadius(8)
    }
}