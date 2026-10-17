//
//  TextsWatchApp.swift
//  xDrip Watch App
//
//  Created by Paul Plant on 27/4/24.
//  Copyright © 2024 Johan Degraeve. All rights reserved.
//

import Foundation

/// all Nightscout related texts
class Texts_WatchApp {
    static private let filename = "WatchApp"
    
    static let requestingData: String = {
        return NSLocalizedString("requestingData", tableName: filename, bundle: Bundle.main, value: "Requesting data...", comment: "watch app - text for requesting data")
    }()
    
    static let lastReading: String = {
        return NSLocalizedString("lastReading", tableName: filename, bundle: Bundle.main, value: "Last reading", comment: "watch app - text for last reading")
    }()
    
    static let noSensorData: String = {
        return NSLocalizedString("noSensorData", tableName: filename, bundle: Bundle.main, value: "No sensor data", comment: "watch app - text for no sensor data")
    }()

    // MARK: - Direct Connection (Direct-to-Watch, docs/watch-direct-to-sensor.md)

    static let directConnection: String = {
        return NSLocalizedString("directConnection", tableName: filename, bundle: Bundle.main, value: "Direct Connection", comment: "watch app - title of the direct sensor connection page")
    }()

    static let directConnectionToggle: String = {
        return NSLocalizedString("directConnectionToggle", tableName: filename, bundle: Bundle.main, value: "Direct to Sensor", comment: "watch app - toggle that asks the iPhone to enable/disable the direct sensor connection")
    }()

    static let directConnectionStatus: String = {
        return NSLocalizedString("directConnectionStatus", tableName: filename, bundle: Bundle.main, value: "Status", comment: "watch app - label above the direct connection status")
    }()

    static let directConnectionOff: String = {
        return NSLocalizedString("directConnectionOff", tableName: filename, bundle: Bundle.main, value: "Off", comment: "watch app - direct connection phase: not active")
    }()

    static let directConnectionBluetoothOff: String = {
        return NSLocalizedString("directConnectionBluetoothOff", tableName: filename, bundle: Bundle.main, value: "Bluetooth Off", comment: "watch app - direct connection phase: bluetooth hardware is off")
    }()

    static let directConnectionConnecting: String = {
        return NSLocalizedString("directConnectionConnecting", tableName: filename, bundle: Bundle.main, value: "Connecting", comment: "watch app - direct connection phase: scanning, connecting or authenticating")
    }()

    static let directConnectionConnected: String = {
        return NSLocalizedString("directConnectionConnected", tableName: filename, bundle: Bundle.main, value: "Connected", comment: "watch app - direct connection phase: authenticated and receiving readings")
    }()

    static let directConnectionNotConfigured: String = {
        return NSLocalizedString("directConnectionNotConfigured", tableName: filename, bundle: Bundle.main, value: "Not configured. Open the sensor settings on the iPhone and turn on Apple Watch Direct Connection.", comment: "watch app - direct connection has no configuration from the iPhone yet")
    }()

    static let directConnectionIPhoneUnreachable: String = {
        return NSLocalizedString("directConnectionIPhoneUnreachable", tableName: filename, bundle: Bundle.main, value: "iPhone not reachable. The iPhone app is needed to change this.", comment: "watch app - the direct connection toggle needs a reachable iPhone")
    }()

    static let directConnectionSensor: String = {
        return NSLocalizedString("directConnectionSensor", tableName: filename, bundle: Bundle.main, value: "Sensor", comment: "watch app - label for the directly connected sensor name")
    }()

    static let directConnectionSensorStart: String = {
        return NSLocalizedString("directConnectionSensorStart", tableName: filename, bundle: Bundle.main, value: "Sensor Start", comment: "watch app - label for the directly connected sensor's session start")
    }()

    static let directConnectionLastReading: String = {
        return NSLocalizedString("directConnectionLastReading", tableName: filename, bundle: Bundle.main, value: "Last direct reading", comment: "watch app - label for the time of the last directly collected reading")
    }()

    static let directConnectionPairingNeeded: String = {
        return NSLocalizedString("directConnectionPairingNeeded", tableName: filename, bundle: Bundle.main, value: "Bluetooth pairing needed: keep this app open and confirm the pairing request within the next few minutes.", comment: "watch app - shown while the sensor requires the user to confirm the system Bluetooth pairing request")
    }()

    static let directConnectionLog: String = {
        return NSLocalizedString("directConnectionLog", tableName: filename, bundle: Bundle.main, value: "Connection Log", comment: "watch app - header of the connection diagnostics section on the direct connection page")
    }()

    static let directConnectionLogEmpty: String = {
        return NSLocalizedString("directConnectionLogEmpty", tableName: filename, bundle: Bundle.main, value: "No connection activity yet. Entries appear as soon as the connection runs.", comment: "watch app - shown when the connection log has no entries")
    }()

    // MARK: - Watch local glucose alerts for directly collected readings

    static let alertUrgentLowTitle: String = {
        return NSLocalizedString("alertUrgentLowTitle", tableName: filename, bundle: Bundle.main, value: "⚠️ Urgent Low", comment: "watch app - critical alert title for an urgent low glucose")
    }()

    static let alertLowTitle: String = {
        return NSLocalizedString("alertLowTitle", tableName: filename, bundle: Bundle.main, value: "🟡 Low Glucose", comment: "watch app - alert title for a low glucose")
    }()

    static let alertHighTitle: String = {
        return NSLocalizedString("alertHighTitle", tableName: filename, bundle: Bundle.main, value: "🟠 High Glucose", comment: "watch app - alert title for a high glucose")
    }()

    static let alertUrgentHighTitle: String = {
        return NSLocalizedString("alertUrgentHighTitle", tableName: filename, bundle: Bundle.main, value: "🔴 Urgent High", comment: "watch app - critical alert title for an urgent high glucose")
    }()

    static let alertUnitMgDl: String = {
        return NSLocalizedString("alertUnitMgDl", tableName: filename, bundle: Bundle.main, value: "mg/dL", comment: "watch app - mg/dL unit label in local alert bodies")
    }()

    static let alertUnitMmol: String = {
        return NSLocalizedString("alertUnitMmol", tableName: filename, bundle: Bundle.main, value: "mmol/L", comment: "watch app - mmol/L unit label in local alert bodies")
    }()

    static let directConnectionSafetyNote: String = {
        return NSLocalizedString("directConnectionSafetyNote", tableName: filename, bundle: Bundle.main, value: "Experimental software, not a medical device. Never rely on it as the only source of glucose information.", comment: "watch app - safety disclaimer below the direct connection settings, mirroring the project README warning")
    }()

}
