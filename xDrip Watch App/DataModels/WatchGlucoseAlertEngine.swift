//
//  WatchGlucoseAlertEngine.swift
//  xDrip Watch App
//
//  Created as part of the Direct-to-Watch feature (docs/watch-direct-to-sensor.md).
//  Copyright © 2026 xDrip4iOS contributors. All rights reserved.
//
//  Watch-local urgent-low / low / high / urgent-high notifications for readings the Watch
//  collects directly from the sensor. Uses the limit values already synced from the iPhone, so
//  no additional configuration is needed. Only readings the Watch collects itself trigger these
//  alerts: while the iPhone is reachable it keeps owning the alerting pipeline.
//

import Foundation
import os
import UserNotifications

/// One notification per excursion episode: repeated firings are suppressed until the value
/// returns to the normal range, plus a per-category cooldown against boundary oscillation spam.
///
/// Callers must invoke this class on the main thread only: `WatchStateModel` already funnels all
/// readings through its main-thread `onReadings` dispatch. Mutability is confined to that lane;
/// `UNUserNotificationCenter` itself is thread-safe.
final class WatchGlucoseAlertEngine {

    private enum AlertKind: String, CaseIterable {
        case urgentLow
        case low
        case high
        case urgentHigh
    }

    /// Excursion state machine: an episode stays armed until a reading lands back in the normal
    /// range, preventing repeat alerts for one prolonged excursion.
    private var activeAlertKind: AlertKind?

    /// Time of the last delivered notification per category. A boundary-oscillating run must not
    /// spam the watch face with repeated firings every five minutes.
    private var lastFiredAt: [AlertKind: Date] = [:]

    /// Minimum spacing between two notifications of the same category.
    private static let minimumRepeatInterval: TimeInterval = 30 * 60

    private let log = Logger(subsystem: "xDrip", category: "WatchGlucoseAlertEngine")

    private let notificationCenter = UNUserNotificationCenter.current()

    // MARK: - evaluation

    /// Evaluates the newest directly collected reading against the synced limit values.
    func evaluate(
        readingMgDl: Double,
        isMgDl: Bool,
        urgentLowLimitInMgDl: Double,
        lowLimitInMgDl: Double,
        highLimitInMgDl: Double,
        urgentHighLimitInMgDl: Double
    ) {
        var alertKind: AlertKind?

        if readingMgDl <= urgentLowLimitInMgDl {
            alertKind = .urgentLow
        } else if readingMgDl <= lowLimitInMgDl {
            alertKind = .low
        } else if readingMgDl >= urgentHighLimitInMgDl {
            alertKind = .urgentHigh
        } else if readingMgDl >= highLimitInMgDl {
            alertKind = .high
        }

        guard let alertKind else {
            // back in the normal range: re-arm the episode machine
            activeAlertKind = nil
            return
        }

        // same excursion, no new notification
        guard alertKind != activeAlertKind else { return }
        // same category fired recently, suppress
        if let lastFiredAt = lastFiredAt[alertKind],
           lastFiredAt.addingTimeInterval(Self.minimumRepeatInterval) > Date() {
            activeAlertKind = alertKind
            return
        }

        activeAlertKind = alertKind
        lastFiredAt[alertKind] = Date()

        deliver(alertKind, readingMgDl: readingMgDl, isMgDl: isMgDl)
    }

    // MARK: - delivery

    private func deliver(_ alertKind: AlertKind, readingMgDl: Double, isMgDl: Bool) {
        let content = UNMutableNotificationContent()

        switch alertKind {
        case .urgentLow:
            content.title = Texts_WatchApp.alertUrgentLowTitle
            content.interruptionLevel = .critical
            content.sound = .defaultCritical
        case .low:
            content.title = Texts_WatchApp.alertLowTitle
            content.sound = .default
        case .high:
            content.title = Texts_WatchApp.alertHighTitle
            content.sound = .default
        case .urgentHigh:
            content.title = Texts_WatchApp.alertUrgentHighTitle
            content.interruptionLevel = .timeSensitive
            content.sound = .defaultCritical
        }

        content.body = "\(readingMgDl.mgDlToMmolAndToString(mgDl: isMgDl)) \(isMgDl ? Texts_WatchApp.alertUnitMgDl : Texts_WatchApp.alertUnitMmol)"
        content.threadIdentifier = "xdrip.watch.glucose"

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)

        Task { [weak self] in
            guard let self else { return }

            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])

                guard granted else {
                    log.info("local notifications denied by the user")
                    return
                }

                try await UNUserNotificationCenter.current().add(request)
                log.info("delivered \(String(describing: alertKind)) notification")
            } catch {
                log.error("unable to deliver glucose notification: \(error.localizedDescription, privacy: .public)")
            }
        }

        log.info("glucose alert requested: \(String(describing: alertKind))")
    }
}