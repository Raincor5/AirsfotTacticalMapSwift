//
//  PushNotificationManager.swift
//  Airsoft Tactical Map
//
//  Created by Jaroslavs Krots on 05/06/2025.
//

import Foundation
import UserNotifications
import UIKit

class PushNotificationManager: NSObject, ObservableObject {
    static let shared = PushNotificationManager()
    
    @Published var isAuthorized = false
    @Published var deviceToken: String?
    
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    
    // MARK: - Permission Management
    
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound, .criticalAlert]) { granted, error in
            DispatchQueue.main.async {
                self.isAuthorized = granted
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                    print("✅ Push notification permission granted")
                } else {
                    print("❌ Push notification permission denied")
                }
            }
        }
    }
    
    func checkPermissionStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }
    
    // MARK: - Device Token Management
    
    func setDeviceToken(_ deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        self.deviceToken = tokenString
        print("📱 Device token: \(tokenString)")
        
        // Send token to your server for storing
        sendTokenToServer(tokenString)
    }
    
    private func sendTokenToServer(_ token: String) {
        // TODO: Send to your WebSocket server to store for push notifications
        print("📤 Sending device token to server: \(token)")
    }
    
    // MARK: - Local Notifications (for MultipeerConnectivity)
    
    func sendTacticalAlert(_ message: TacticalAlert) {
        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = message.body
        content.sound = .default
        content.categoryIdentifier = message.category.rawValue
        
        // Add tactical-specific data
        content.userInfo = [
            "type": "tactical_alert",
            "alert_type": message.type.rawValue,
            "coordinates": message.coordinates as Any,
            "team_id": message.teamId as Any,
            "urgency": message.urgency.rawValue
        ]
        
        // Immediate delivery for tactical alerts
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to schedule tactical alert: \(error)")
            } else {
                print("🚨 Tactical alert sent: \(message.title)")
            }
        }
    }
    
    func sendTeamMessage(_ message: String, from playerName: String, teamId: String?) {
        let content = UNMutableNotificationContent()
        content.title = "Team Radio"
        content.body = "\(playerName): \(message)"
        content.sound = .default
        content.categoryIdentifier = TacticalNotificationCategory.teamMessage.rawValue
        
        content.userInfo = [
            "type": "team_message",
            "sender": playerName,
            "team_id": teamId as Any,
            "message": message
        ]
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to send team message notification: \(error)")
            } else {
                print("📻 Team message notification sent")
            }
        }
    }
    
    // MARK: - Session Notifications
    
    func sendSessionInvitation(sessionCode: String, hostName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Tactical Session Invitation"
        content.body = "\(hostName) invited you to join session \(sessionCode)"
        content.sound = .default
        content.categoryIdentifier = TacticalNotificationCategory.sessionInvite.rawValue
        
        content.userInfo = [
            "type": "session_invitation",
            "session_code": sessionCode,
            "host_name": hostName
        ]
        
        let request = UNNotificationRequest(
            identifier: "session_invite_\(sessionCode)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to send session invitation: \(error)")
            } else {
                print("📧 Session invitation sent")
            }
        }
    }
    
    // MARK: - Setup Notification Categories
    
    func setupNotificationCategories() {
        let tacticalAlertCategory = UNNotificationCategory(
            identifier: TacticalNotificationCategory.tacticalAlert.rawValue,
            actions: [
                UNNotificationAction(
                    identifier: "acknowledge",
                    title: "Copy That",
                    options: []
                ),
                UNNotificationAction(
                    identifier: "respond",
                    title: "Respond",
                    options: [.foreground]
                )
            ],
            intentIdentifiers: [],
            options: []
        )
        
        let teamMessageCategory = UNNotificationCategory(
            identifier: TacticalNotificationCategory.teamMessage.rawValue,
            actions: [
                UNNotificationAction(
                    identifier: "reply",
                    title: "Reply",
                    options: [.foreground]
                ),
                UNNotificationAction(
                    identifier: "mark_read",
                    title: "Mark Read",
                    options: []
                )
            ],
            intentIdentifiers: [],
            options: []
        )
        
        let sessionInviteCategory = UNNotificationCategory(
            identifier: TacticalNotificationCategory.sessionInvite.rawValue,
            actions: [
                UNNotificationAction(
                    identifier: "join_session",
                    title: "Join",
                    options: [.foreground]
                ),
                UNNotificationAction(
                    identifier: "decline_session",
                    title: "Decline",
                    options: []
                )
            ],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([
            tacticalAlertCategory,
            teamMessageCategory,
            sessionInviteCategory
        ])
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushNotificationManager: UNUserNotificationCenterDelegate {
    // Handle notifications when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground for tactical alerts
        if notification.request.content.categoryIdentifier == TacticalNotificationCategory.tacticalAlert.rawValue {
            completionHandler([.banner, .sound, .badge])
        } else {
            completionHandler([.banner, .sound])
        }
    }
    
    // Handle notification interactions
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let actionIdentifier = response.actionIdentifier
        
        switch actionIdentifier {
        case "acknowledge":
            handleTacticalAlertAcknowledge(userInfo)
        case "respond":
            handleTacticalAlertRespond(userInfo)
        case "reply":
            handleTeamMessageReply(userInfo)
        case "join_session":
            handleSessionJoin(userInfo)
        case "decline_session":
            handleSessionDecline(userInfo)
        default:
            // Default tap action
            handleNotificationTap(userInfo)
        }
        
        completionHandler()
    }
    
    // MARK: - Notification Action Handlers
    
    private func handleTacticalAlertAcknowledge(_ userInfo: [AnyHashable: Any]) {
        print("🎖️ Tactical alert acknowledged")
        // Send acknowledgment to team
    }
    
    private func handleTacticalAlertRespond(_ userInfo: [AnyHashable: Any]) {
        print("📻 Opening app to respond to tactical alert")
        // Open app to message screen
        NotificationCenter.default.post(name: .openTacticalResponse, object: userInfo)
    }
    
    private func handleTeamMessageReply(_ userInfo: [AnyHashable: Any]) {
        print("💬 Opening app to reply to team message")
        // Open app to chat
        NotificationCenter.default.post(name: .openTeamChat, object: userInfo)
    }
    
    private func handleSessionJoin(_ userInfo: [AnyHashable: Any]) {
        if let sessionCode = userInfo["session_code"] as? String {
            print("🎯 Joining session: \(sessionCode)")
            NotificationCenter.default.post(name: .joinSession, object: sessionCode)
        }
    }
    
    private func handleSessionDecline(_ userInfo: [AnyHashable: Any]) {
        print("❌ Session invitation declined")
    }
    
    private func handleNotificationTap(_ userInfo: [AnyHashable: Any]) {
        // Handle default notification tap
        print("📱 Notification tapped, opening app")
        NotificationCenter.default.post(name: .openFromNotification, object: userInfo)
    }
}

// MARK: - Data Models

struct TacticalAlert {
    let title: String
    let body: String
    let type: TacticalAlertType
    let urgency: Urgency
    let coordinates: (latitude: Double, longitude: Double)?
    let teamId: String?
    let category: TacticalNotificationCategory = .tacticalAlert
    
    var isUrgent: Bool {
        urgency == .critical || urgency == .high
    }
}

enum TacticalAlertType: String, CaseIterable {
    case enemySpotted = "enemy_spotted"
    case objectiveCaptured = "objective_captured"
    case rallyPoint = "rally_point"
    case casualty = "casualty"
    case ammunition = "ammunition"
    case retreat = "retreat"
    case advance = "advance"
    case regroup = "regroup"
}

enum Urgency: String, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"
}

enum TacticalNotificationCategory: String, CaseIterable {
    case tacticalAlert = "TACTICAL_ALERT"
    case teamMessage = "TEAM_MESSAGE"
    case sessionInvite = "SESSION_INVITE"
}

// MARK: - Notification Names

extension Notification.Name {
    static let openTacticalResponse = Notification.Name("openTacticalResponse")
    static let openTeamChat = Notification.Name("openTeamChat")
    static let joinSession = Notification.Name("joinSession")
    static let openFromNotification = Notification.Name("openFromNotification")
} 