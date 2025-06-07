//
//  ServerConfigurationView.swift
//  Airsoft Tactical Map
//
//  Created by Jaroslavs Krots on 05/06/2025.
//

import SwiftUI
import CoreImage.CIFilterBuiltins
import AVFoundation

struct ServerConfigurationView: View {
    @ObservedObject var webSocketManager: WebSocketGameManager
    @Environment(\.presentationMode) var presentationMode
    
    @State private var serverIP: String = ""
    @State private var serverPort: String = "3001"
    @State private var showingQRGenerator = false
    @State private var showingQRScanner = false
    @State private var connectionTestResult: String = ""
    @State private var isTestingConnection = false
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    Color.black.ignoresSafeArea()
                    
                    ScrollView {
                        VStack(spacing: geometry.size.height < 700 ? 16 : 24) {
                            // Header - more compact on smaller screens
                            VStack(spacing: geometry.size.height < 700 ? 4 : 8) {
                                Image(systemName: "server.rack")
                                    .font(.system(size: geometry.size.height < 700 ? 30 : 40))
                                    .foregroundColor(.blue)
                                
                                Text("SERVER CONFIG")
                                    .font(.system(size: geometry.size.height < 700 ? 16 : 20, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                
                                if geometry.size.height >= 700 {
                                    VStack(spacing: 4) {
                                        Text("Configure WebSocket server for tactical coordination")
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundColor(.gray)
                                            .multilineTextAlignment(.center)
                                        
                                        Text("Local IP: 192.168.x.x | ngrok: your-url.ngrok-free.app")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.blue.opacity(0.8))
                                            .multilineTextAlignment(.center)
                                    }
                                }
                            }
                            .padding(.top, geometry.size.height < 700 ? 8 : 16)
                    
                            // Current Status
                            VStack(spacing: geometry.size.height < 700 ? 4 : 8) {
                                Text("STATUS")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.gray)
                                
                                Text(webSocketManager.serverStatus)
                                    .font(.system(size: geometry.size.height < 700 ? 12 : 14, weight: .medium, design: .monospaced))
                                    .foregroundColor(.green)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, geometry.size.height < 700 ? 6 : 8)
                                    .background(Color.black.opacity(0.3))
                                    .cornerRadius(8)
                            }
                            
                            // Manual Configuration
                            VStack(spacing: geometry.size.height < 700 ? 12 : 16) {
                        Text("MANUAL CONFIGURATION")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                        
                        VStack(spacing: 12) {
                            // IP Address Input
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Server IP Address")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundColor(.gray)
                                
                                TextField("192.168.1.100 or abc123.ngrok-free.app", text: $serverIP)
                                    .textFieldStyle(TacticalTextFieldStyle())
                                    .keyboardType(.URL)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                            }
                            
                            // Port Input
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Port")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundColor(.gray)
                                
                                TextField("3001", text: $serverPort)
                                    .textFieldStyle(TacticalTextFieldStyle())
                                    .keyboardType(.numberPad)
                                    .onChange(of: serverIP) { newValue in
                                        // Auto-adjust port for ngrok domains
                                        if newValue.contains(".ngrok") {
                                            serverPort = "80"
                                        } else if serverPort == "80" && !newValue.contains(".ngrok") {
                                            serverPort = "3001"
                                        }
                                    }
                            }
                        }
                        
                                // Configuration Buttons
                                HStack(spacing: geometry.size.height < 700 ? 8 : 12) {
                                    Button(action: testConnection) {
                                        HStack(spacing: geometry.size.height < 700 ? 4 : 8) {
                                            if isTestingConnection {
                                                ProgressView()
                                                    .scaleEffect(0.8)
                                            } else {
                                                Image(systemName: "network")
                                                    .font(.system(size: geometry.size.height < 700 ? 12 : 14))
                                            }
                                            Text("TEST")
                                                .font(.system(size: geometry.size.height < 700 ? 11 : 12, weight: .bold, design: .monospaced))
                                        }
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, geometry.size.height < 700 ? 10 : 12)
                                        .background(Color.blue.opacity(0.8))
                                        .cornerRadius(8)
                                    }
                                    .disabled(serverIP.isEmpty || isTestingConnection)
                                    
                                    Button(action: configureServer) {
                                        HStack(spacing: geometry.size.height < 700 ? 4 : 8) {
                                            Image(systemName: "checkmark.circle")
                                                .font(.system(size: geometry.size.height < 700 ? 12 : 14))
                                            Text("SAVE")
                                                .font(.system(size: geometry.size.height < 700 ? 11 : 12, weight: .bold, design: .monospaced))
                                        }
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, geometry.size.height < 700 ? 10 : 12)
                                        .background(Color.green.opacity(0.8))
                                        .cornerRadius(8)
                                    }
                                    .disabled(serverIP.isEmpty)
                                }
                        
                        // Test Result
                        if !connectionTestResult.isEmpty {
                            Text(connectionTestResult)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(connectionTestResult.contains("successful") ? .green : .red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.3))
                                .cornerRadius(6)
                        }
                            }
                            .padding(.horizontal, 20)
                            
                            // QR Code Section
                            VStack(spacing: geometry.size.height < 700 ? 12 : 16) {
                                Text("QR CODE OPTIONS")
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                
                                HStack(spacing: geometry.size.height < 700 ? 12 : 16) {
                                    // Generate QR Code
                                    Button(action: { showingQRGenerator = true }) {
                                        VStack(spacing: geometry.size.height < 700 ? 4 : 8) {
                                            Image(systemName: "qrcode")
                                                .font(.system(size: geometry.size.height < 700 ? 18 : 22))
                                            Text("GENERATE QR")
                                                .font(.system(size: geometry.size.height < 700 ? 9 : 10, weight: .bold, design: .monospaced))
                                        }
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: geometry.size.height < 700 ? 60 : 80)
                                        .background(Color.purple.opacity(0.8))
                                        .cornerRadius(12)
                                    }
                                    .disabled(serverIP.isEmpty)
                                    
                                    // Scan QR Code
                                    Button(action: { showingQRScanner = true }) {
                                        VStack(spacing: geometry.size.height < 700 ? 4 : 8) {
                                            Image(systemName: "qrcode.viewfinder")
                                                .font(.system(size: geometry.size.height < 700 ? 18 : 22))
                                            Text("SCAN QR")
                                                .font(.system(size: geometry.size.height < 700 ? 9 : 10, weight: .bold, design: .monospaced))
                                        }
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: geometry.size.height < 700 ? 60 : 80)
                                        .background(Color.orange.opacity(0.8))
                                        .cornerRadius(12)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("Save") {
                    configureServer()
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingQRGenerator) {
            QRCodeGeneratorView(serverIP: serverIP, serverPort: serverPort)
        }
        .sheet(isPresented: $showingQRScanner) {
            QRCodeScannerView { scannedData in
                handleScannedQR(scannedData)
            }
        }
        .onAppear {
            // Load current server configuration
            serverIP = webSocketManager.serverHost
            serverPort = String(webSocketManager.serverPort)
        }
    }
    
    private func configureServer() {
        guard let port = Int(serverPort) else { return }
        webSocketManager.configureServer(host: serverIP, port: port)
    }
    
    private func testConnection() {
        guard let port = Int(serverPort) else { return }
        
        isTestingConnection = true
        connectionTestResult = ""
        
        // Temporarily configure server for testing
        let originalHost = webSocketManager.serverHost
        let originalPort = webSocketManager.serverPort
        
        webSocketManager.configureServer(host: serverIP, port: port)
        
        webSocketManager.testConnection { success, message in
            DispatchQueue.main.async {
                self.isTestingConnection = false
                self.connectionTestResult = message
                
                if !success {
                    // Restore original configuration if test failed
                    self.webSocketManager.configureServer(host: originalHost, port: originalPort)
                }
            }
        }
    }
    
    private func handleScannedQR(_ data: String) {
        // Expected format: "tactical-server:192.168.1.100:3001"
        let components = data.components(separatedBy: ":")
        
        if components.count >= 3 && components[0] == "tactical-server" {
            serverIP = components[1]
            if let port = Int(components[2]) {
                serverPort = String(port)
            }
            
            // Auto-configure after scanning
            configureServer()
            connectionTestResult = "Configuration loaded from QR code"
        } else {
            connectionTestResult = "Invalid QR code format"
        }
    }
}

// MARK: - QR Code Generator View

struct QRCodeGeneratorView: View {
    let serverIP: String
    let serverPort: String
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Share Server Configuration")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Scan this QR code to configure other devices")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                if let qrImage = generateQRCode() {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                        .background(Color.white)
                        .cornerRadius(12)
                }
                
                VStack(spacing: 8) {
                    Text("Server Details:")
                        .font(.headline)
                    Text("IP: \(serverIP)")
                        .font(.system(.body, design: .monospaced))
                    Text("Port: \(serverPort)")
                        .font(.system(.body, design: .monospaced))
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
                
                Spacer()
            }
            .padding()
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
    
    private func generateQRCode() -> UIImage? {
        let data = "tactical-server:\(serverIP):\(serverPort)".data(using: .utf8)
        
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data ?? Data()
        filter.correctionLevel = "M"
        
        if let outputImage = filter.outputImage {
            let context = CIContext()
            let transform = CGAffineTransform(scaleX: 10, y: 10)
            let scaledImage = outputImage.transformed(by: transform)
            
            if let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) {
                return UIImage(cgImage: cgImage)
            }
        }
        
        return nil
    }
}

// MARK: - QR Code Scanner View

struct QRCodeScannerView: UIViewControllerRepresentable {
    let completion: (String) -> Void
    
    func makeUIViewController(context: Context) -> QRScannerViewController {
        let scanner = QRScannerViewController()
        scanner.completion = completion
        return scanner
    }
    
    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var completion: ((String) -> Void)?
    private var captureSession: AVCaptureSession!
    private var previewLayer: AVCaptureVideoPreviewLayer!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
    }
    
    private func setupCamera() {
        captureSession = AVCaptureSession()
        
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }
        let videoInput: AVCaptureDeviceInput
        
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            return
        }
        
        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        } else {
            return
        }
        
        let metadataOutput = AVCaptureMetadataOutput()
        
        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)
            
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            return
        }
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        
        captureSession.startRunning()
    }
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        captureSession.stopRunning()
        
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }
            
            completion?(stringValue)
            dismiss(animated: true)
        }
    }
}

#Preview {
    ServerConfigurationView(webSocketManager: WebSocketGameManager())
} 