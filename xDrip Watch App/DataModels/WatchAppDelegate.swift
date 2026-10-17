//
//  WatchAppDelegate.swift
//  xDrip Watch App
//
//  Created as part of the Direct-to-Watch feature (docs/watch-direct-to-sensor.md).
//  Copyright © 2026 xDrip4iOS contributors. All rights reserved.
//
//  Keeps the direct sensor connection alive while the Watch app is suspended. Core Bluetooth
//  wakes the app for characteristic updates (bluetooth-central background mode); this delegate
//  additionally schedules periodic application refresh tasks so reconnect attempts, chart
//  merging and complication refreshes continue over multi-hour periods without the app in the
//  foreground - the same refresh-driven model the official Dexcom watch app lives with.
//

import Foundation
import WatchKit

final class WatchAppDelegate: NSObject, WKApplicationDelegate {

    /// Lets app-lifecycle-only APIs (like background refresh scheduling) be reached from
    /// WatchStateModel without making the model depend on WatchKit.
    private(set) weak static var instance: WatchAppDelegate?

    /// The app's watch state. Set once by WatchStateModel during init.
    weak var watchState: WatchStateModel?

    /// Cadence for reconnect/housekeeping wakes while the direct connection is enabled.
    private static let backgroundRefreshInterval: TimeInterval = 10 * 60

    override init() {
        super.init()
        Self.instance = self
    }

    // MARK: - lifecycle

    func applicationWillResignActive() {
        scheduleBackgroundRefresh()
    }

    // MARK: - background tasks

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case let refreshTask as WKApplicationRefreshBackgroundTask:
                // Reconnect attempt plus complication/chart housekeeping while suspended.
                watchState?.handleBackgroundWake()
                scheduleBackgroundRefresh()
                refreshTask.setTaskCompletedWithSnapshot(false)
            default:
                // WatchConnectivity deliveries and snapshot work are handled by their own systems.
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }

    // MARK: - background refresh scheduling

    /// Requests one further wake. watchOS treats this as best-effort and may coalesce or delay it,
    /// which is fine: characteristic notifications themselves keep the connection data flowing, and
    /// this wake exists for reconnect attempts that need nothing else.
    func scheduleBackgroundRefresh() {
        guard watchState?.directConnectionPhase != .inactive, watchState?.directConnectionPhase != .bluetoothOff else { return }

        let desiredWakeDate = Date().addingTimeInterval(Self.backgroundRefreshInterval)

        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: desiredWakeDate,
            userInfo: nil
        ) { [weak self] error in
            if let error {
                self?.watchState?.logBackgroundRefreshFailure(error)
            }
        }
    }
}