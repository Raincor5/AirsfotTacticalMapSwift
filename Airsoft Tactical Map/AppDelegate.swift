//
//  AppDelegate.swift
//  Airsoft Tactical Map
//
//  Created by Jaroslavs Krots on 05/06/2025.
//

import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // Setup push notification categories
        PushNotificationManager.shared.setupNotificationCategories()
        
        // Check current permission status
        PushNotificationManager.shared.checkPermissionStatus()
        
        // Handle app launch from notification
        if let notificationUserInfo = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            handleLaunchFromNotification(notificationUserInfo)
        }
        
        return true
    }
    
    // MARK: - Push Notification Registration
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("📱 Successfully registered for push notifications")
        PushNotificationManager.shared.setDeviceToken(deviceToken)
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ Failed to register for push notifications: \(error.localizedDescription)")
    }
    
    // MARK: - Remote Notification Handling
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        
        print("📥 Received remote notification: \(userInfo)")
        
        // Handle different types of push notifications
        handleRemoteNotification(userInfo, isBackground: application.applicationState == .background)
        
        completionHandler(.newData)
    }
    
    // MARK: - Notification Handling
    
    private func handleRemoteNotification(_ userInfo: [AnyHashable: Any], isBackground: Bool) {
        guard let notificationType = userInfo["type"] as? String else { return }
        
        switch notificationType {
        case "tactical_alert":
            handleTacticalAlertNotification(userInfo, isBackground: isBackground)
        case "team_message":
            handleTeamMessageNotification(userInfo, isBackground: isBackground)
        case "session_invitation":
            handleSessionInvitationNotification(userInfo, isBackground: isBackground)
        case "player_update":
            handlePlayerUpdateNotification(userInfo, isBackground: isBackground)
        default:
            print("Unknown notification type: \(notificationType)")
        }
    }
    
    private func handleTacticalAlertNotification(_ userInfo: [AnyHashable: Any], isBackground: Bool) {
        print("🚨 Handling tactical alert notification")
        
        if isBackground {
            // Send local notification to get user's attention
            if let alertType = userInfo["alert_type"] as? String,
               let message = userInfo["message"] as? String {
                
                let alert = TacticalAlert(
                    title: "Tactical Alert",
                    body: message,
                    type: TacticalAlertType(rawValue: alertType) ?? .enemySpotted,
                    urgency: .high,
                    coordinates: nil,
                    teamId: userInfo["team_id"] as? String
                )
                
                PushNotificationManager.shared.sendTacticalAlert(alert)
            }
        } else {
            // App is in foreground, handle directly
            NotificationCenter.default.post(name: .tacticalAlertReceived, object: userInfo)
        }
    }
    
    private func handleTeamMessageNotification(_ userInfo: [AnyHashable: Any], isBackground: Bool) {
        print("💬 Handling team message notification")
        
        if isBackground {
            // Send local notification
            if let message = userInfo["message"] as? String,
               let senderName = userInfo["sender_name"] as? String,
               let teamId = userInfo["team_id"] as? String {
                
                PushNotificationManager.shared.sendTeamMessage(message, from: senderName, teamId: teamId)
            }
        } else {
            // Update chat in real-time
            NotificationCenter.default.post(name: .teamMessageReceived, object: userInfo)
        }
    }
    
    private func handleSessionInvitationNotification(_ userInfo: [AnyHashable: Any], isBackground: Bool) {
        print("📧 Handling session invitation notification")
        
        if let sessionCode = userInfo["session_code"] as? String,
           let hostName = userInfo["host_name"] as? String {
            
            if isBackground {
                PushNotificationManager.shared.sendSessionInvitation(sessionCode: sessionCode, hostName: hostName)
            } else {
                NotificationCenter.default.post(name: .sessionInvitationReceived, object: userInfo)
            }
        }
    }
    
    private func handlePlayerUpdateNotification(_ userInfo: [AnyHashable: Any], isBackground: Bool) {
        print("👥 Handling player update notification")
        
        // Update player location or status in background
        NotificationCenter.default.post(name: .playerUpdateReceived, object: userInfo)
    }
    
    private func handleLaunchFromNotification(_ userInfo: [AnyHashable: Any]) {
        print("🚀 App launched from notification")
        
        // Store the notification data to be processed once the app is fully loaded
        NotificationCenter.default.post(name: .launchedFromNotification, object: userInfo)
    }
}

// MARK: - Additional Notification Names

extension Notification.Name {
    static let tacticalAlertReceived = Notification.Name("tacticalAlertReceived")
    static let teamMessageReceived = Notification.Name("teamMessageReceived")
    static let sessionInvitationReceived = Notification.Name("sessionInvitationReceived")
    static let playerUpdateReceived = Notification.Name("playerUpdateReceived")
    static let launchedFromNotification = Notification.Name("launchedFromNotification")
} 