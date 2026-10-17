//
//  UserDefaults+SharedCore.swift
//  xDrip
//
//  Created as part of the Direct-to-Watch feature (docs/watch-direct-to-sensor.md).
//  Copyright © 2026 xDrip4iOS contributors. All rights reserved.
//
//  This file is shared between the iOS app target and the watchOS Watch app target.
//

import Foundation

/// UserDefaults accessors needed by the shared Bluetooth/CGM core and the tracing layer.
///
/// These keys are also declared in `Extensions/UserDefaults.swift`'s `Key` enum for the iOS app.
/// The raw values must stay identical on every platform because they persist real user state:
/// the Watch app must read and write the same keys the iOS app uses. Keep both lists in sync.
private enum SharedCoreKey: String {
    case activeSensorTransmitterId = "activeSensorTransmitterId"
    case activeSensorMaxSensorAgeInDays = "activeSensorMaxSensorAgeInDays"
    case OSLogEnabled = "OSLogEnabled"
    case NSLogEnabled = "NSLogEnabled"
    case previousRawGlucoseValues = "previousRawGlucoseValues"
    case addDebugLevelLogsInTraceFileAndNSLog = "addDebugLevelLogsInTraceFileAndNSLog"
}

extension UserDefaults {

    /// active transmitter ID. Optional as should be set to nil if there is no transmitter connected. Used for the UI to configure sensor type in case no sensor serial number is availabel (for example Dexcom).
    @objc dynamic var activeSensorTransmitterId: String? {
        get {
            return string(forKey: SharedCoreKey.activeSensorTransmitterId.rawValue)
        }
        set {
            set(newValue, forKey: SharedCoreKey.activeSensorTransmitterId.rawValue)
        }
    }

    /// active sensor max sensor days. Optional as should be set to nil if no successful login has happened and/or if no active sensor is returned
    var activeSensorMaxSensorAgeInDays: Double? {
        get {
            return double(forKey: SharedCoreKey.activeSensorMaxSensorAgeInDays.rawValue)
        }
        set {
            set(newValue, forKey: SharedCoreKey.activeSensorMaxSensorAgeInDays.rawValue)
        }
    }

    /// OSLogEnabled - default false
    var OSLogEnabled: Bool {
        get {
            return bool(forKey: SharedCoreKey.OSLogEnabled.rawValue)
        }
        set {
            set(newValue, forKey: SharedCoreKey.OSLogEnabled.rawValue)
        }
    }

    /// NSLogEnabled - default false
    var NSLogEnabled: Bool {
        get {
            return bool(forKey: SharedCoreKey.NSLogEnabled.rawValue)
        }
        set {
            set(newValue, forKey: SharedCoreKey.NSLogEnabled.rawValue)
        }
    }

    /// used for storing data read with Libre 2 direct
    var previousRawGlucoseValues: [Int]? {
        get {
            if let data = object(forKey: SharedCoreKey.previousRawGlucoseValues.rawValue) as? [Int] {
                return data as [Int]
            } else {
                return nil
            }

        }
        set {
            set(newValue, forKey: SharedCoreKey.previousRawGlucoseValues.rawValue)
        }
    }

    /// addDebugLevelLogsInTraceFileAndNSLog - default false
    var addDebugLevelLogsInTraceFileAndNSLog: Bool {
        get {
            return bool(forKey: SharedCoreKey.addDebugLevelLogsInTraceFileAndNSLog.rawValue)
        }
        set {
            set(newValue, forKey: SharedCoreKey.addDebugLevelLogsInTraceFileAndNSLog.rawValue)
        }
    }

}