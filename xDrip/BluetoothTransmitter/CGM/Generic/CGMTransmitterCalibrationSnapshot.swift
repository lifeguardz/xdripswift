//
//  CGMTransmitterCalibrationSnapshot.swift
//  xDrip
//
//  Created as part of the Direct-to-Watch feature (docs/watch-direct-to-sensor.md).
//  Copyright © 2026 xDrip4iOS contributors. All rights reserved.
//
//  This file is shared between the iOS app target and the watchOS Watch app target.
//

import Foundation

#if os(iOS)
import CoreData
#endif

/// Detached, platform-neutral snapshot of one user calibration entering the Bluetooth lifecycle.
///
/// A calibration must not be carried into asynchronous Bluetooth callbacks as a managed object.
/// The snapshot copies only the values a transmitter needs to build its calibration command, plus
/// the stable identifier used to re-apply the transmitter result in the store that owns the
/// original calibration. Because the type carries no Core Data dependency, the CGM transmitters can
/// compile on platforms that have no access to the app's Core Data store, such as the watchOS
/// Direct-to-Watch client.
struct CGMTransmitterCalibrationSnapshot {

    /// Stable identifier used by the calibration owner to re-apply a transmitter result.
    let id: String

    /// User-entered glucose value expressed in mg/dL.
    let bg: Double

    /// Wall-clock entry time later converted into the relative transmitter clock.
    let timeStamp: Date

    /// Snapshot of whether an earlier path already sent this treatment to a transmitter.
    let sentToTransmitter: Bool

    init(id: String, bg: Double, timeStamp: Date, sentToTransmitter: Bool) {
        self.id = id
        self.bg = bg
        self.timeStamp = timeStamp
        self.sentToTransmitter = sentToTransmitter
    }

    #if os(iOS)
    /// Creates the snapshot from the Core Data calibration managed by the iOS app.
    ///
    /// The values are copied exactly once, at the boundary between the calibration store and the
    /// transmitter. Later Core Data changes do not affect an already queued Bluetooth command.
    init(calibration: Calibration) {
        self.init(
            id: calibration.id,
            bg: calibration.bg,
            timeStamp: calibration.timeStamp,
            sentToTransmitter: calibration.sentToTransmitter
        )
    }
    #endif

    /// Returns an immutable copy flagged as sent to the transmitter.
    ///
    /// Transmitters use this after a calibration command left the device, so a queued snapshot can
    /// never be re-sent while the transmitter has not answered yet.
    func markedAsSentToTransmitter() -> CGMTransmitterCalibrationSnapshot {
        CGMTransmitterCalibrationSnapshot(
            id: id,
            bg: bg,
            timeStamp: timeStamp,
            sentToTransmitter: true
        )
    }

}