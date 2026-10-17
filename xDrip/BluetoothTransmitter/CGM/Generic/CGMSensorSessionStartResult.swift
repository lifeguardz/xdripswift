//
//  CGMSensorSessionStartResult.swift
//  xDrip
//
//  Moved here from DexcomG6SensorLabel.swift as part of the Direct-to-Watch feature
//  (docs/watch-direct-to-sensor.md). These types are payload types of the shared
//  CGMTransmitterDelegate protocol and belong in the CGM layer, not in the iOS-only
//  sensor-label SwiftUI views.
//
//  This file is shared between the iOS app target and the watchOS Watch app target.
//

import Foundation

// MARK: - persisted sensor metadata

/// Persisted values are append-only. Existing values must not be reordered.
enum SensorSessionOrigin: Int16 {
    case unknown = 0
    case startRequested = 1
    case startedByApp = 2
    case existingSessionAdopted = 3
    case transmitterDetected = 4
    case startRejected = 5
}

/// Persisted values are append-only. Existing values must not be reordered.
enum SensorCalibrationMode: Int16 {
    case unknown = 0
    case noCode = 1
    case factoryCoded = 2
}

/// Typed session-start response used to reconcile the local Sensor with the transmitter.
struct CGMSensorSessionStartResult {
    let response: DexcomSessionStartResponse
    let requestedStartDate: Date
    let sessionStartDate: Date

    var isSuccessful: Bool {
        switch response {
        case .manualCalibrationSessionStarted,
             .manualCalibrationSessionInProgress,
             .autoCalibrationSessionInProgress:
            return true
        case .staleStartComand, .error, .transmitterEndOfLife:
            return false
        }
    }

    var calibrationMode: SensorCalibrationMode {
        switch response {
        case .manualCalibrationSessionStarted, .manualCalibrationSessionInProgress:
            return .noCode
        case .autoCalibrationSessionInProgress:
            return .factoryCoded
        case .staleStartComand, .error, .transmitterEndOfLife:
            return .unknown
        }
    }

    func sessionOrigin(tolerance: TimeInterval) -> SensorSessionOrigin {
        guard isSuccessful else { return .startRejected }
        return abs(sessionStartDate.timeIntervalSince(requestedStartDate)) <= tolerance
            ? .startedByApp
            : .existingSessionAdopted
    }
}