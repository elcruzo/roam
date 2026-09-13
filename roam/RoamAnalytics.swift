//
//  RoamAnalytics.swift
//  roam
//
//  No-op analytics shim. roam ships with telemetry disabled — nothing is sent
//  anywhere. The method surface is kept so call sites stay unchanged; wire your
//  own analytics provider inside these bodies if you ever want them.
//

import Foundation

enum RoamAnalytics {

    // MARK: - Setup
    static func configure() {}

    // MARK: - App Lifecycle
    static func trackAppOpened() {}

    // MARK: - Onboarding
    static func trackOnboardingStarted() {}
    static func trackOnboardingReplayed() {}
    static func trackOnboardingVideoCompleted() {}
    static func trackOnboardingDemoTriggered() {}

    // MARK: - Permissions
    static func trackAllPermissionsGranted() {}
    static func trackPermissionGranted(permission: String) {}

    // MARK: - Voice Interaction
    static func trackPushToTalkStarted() {}
    static func trackPushToTalkReleased() {}
    static func trackUserMessageSent(transcript: String) {}
    static func trackAIResponseReceived(response: String) {}
    static func trackElementPointed(elementLabel: String?) {}

    // MARK: - Region Highlight
    static func trackRegionHighlightStarted() {}
    static func trackRegionHighlightCaptured(width: Int, height: Int) {}

    // MARK: - Errors
    static func trackResponseError(error: String) {}
    static func trackTTSError(error: String) {}
}
