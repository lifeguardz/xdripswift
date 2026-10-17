//
//  WatchState.swift
//  xdrip
//
//  Created by Paul Plant on 21/2/24.
//  Copyright © 2024 Johan Degraeve. All rights reserved.
//

import Foundation

protocol WatchPayload: Codable {
    var asDictionary: [String: Any]? { get }
}

extension WatchPayload {
    var asDictionary: [String: Any]? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data, options: .allowFragments)).flatMap { $0 as? [String: Any] }
    }
}

/// current status data used to manage watch views
struct WatchStatus: WatchPayload {
    var generatedAt: Double = Date().timeIntervalSince1970
    var isMgDl: Bool = true
    var urgentLowLimitInMgDl: Double = 60
    var lowLimitInMgDl: Double = 80
    var highLimitInMgDl: Double = 170
    var urgentHighLimitInMgDl: Double = 250
    var activeSensorDescription: String?
    var sensorAgeInMinutes: Double = 0
    var sensorMaxAgeInMinutes: Double = 0
    var preferSensorCountdown: Bool = false
    var sensorNoiseStateRawValue: Int?
    var isMaster: Bool = true
    var followerDataSourceTypeRawValue: Int = 0
    var followerBackgroundKeepAliveTypeRawValue: Int = 0
    var followerConnectionStatusRawValue: String?
    var timeStampOfLastFollowerConnection: Double?
    var secondsUntilFollowerDisconnectWarning: Int?
    var timeStampOfLastHeartBeat: Double?
    var secondsUntilHeartBeatDisconnectWarning: Int?
    var keepAliveIsDisabled: Bool = false

    var aidStatus: AIDStatus?
    var therapyMetrics: TherapyMetricsSnapshot? = nil

    /// Direct-to-Watch sensor configuration (docs/watch-direct-to-sensor.md). Sent only while the
    /// active peripheral is a G7-family sensor with a valid applicator code and the user enabled
    /// the direct connection. The Watch connects as primary client on the sensor's dedicated
    /// smartwatch channel - never on the channel this app uses itself. Absent means the iPhone no
    /// longer offers a direct connection and the Watch must stop any running one.
    var directSensorConfig: WatchDirectSensorConfig? = nil
}

/// Everything the Watch needs to authenticate as a primary client on the chosen G7 channel.
///
/// The four-digit applicator code is the sensor's pairing secret. It travels only over the paired,
/// encrypted WatchConnectivity transport and is never persisted on the iPhone beyond the active
/// sensor's own Core Data record it was read from.
struct WatchDirectSensorConfig: WatchPayload {
    /// Opt-in master switch; companion-only behaviour stays the default.
    var enabled: Bool

    /// Advertised sensor name / transmitter ID, e.g. "DXCM1ABC23".
    var transmitterId: String

    /// Four-digit applicator code, required for primary ownership of the smartwatch channel.
    var pairingCode: String

    /// Watch v1 always authenticates as primary client; coexistence is a phone-only concept.
    var useOtherApp: Bool = false

    /// `DexcomG7BluetoothSlot` raw value for the Watch's own connection. The evidence-based
    /// default is the mobile-app slot (proven by the Wear OS reference implementation); the
    /// smartwatch slot stays selectable for experiments (docs/watch-direct-to-sensor.md).
    var bluetoothSlotRawValue: Int = Int(DexcomG7BluetoothSlot.mobileApp.rawValue)

    /// Supported total session length in seconds, when known.
    var sensorSessionLengthAsDouble: Double? = nil

    /// Picks the sensor identity the Watch should scan for.
    ///
    /// The Watch matches the advertised `DX...` name, and matching MUST be exact so the Watch
    /// never attempts authentication against a neighbour's sensor. The saved record's
    /// transmitterId can still be the automatic-discovery placeholder (`DX0000`), which maps to a
    /// "DX" wildcard on the transmitter; when the Core Data record already knows the real
    /// Bluetooth name, prefer it. Returns an empty string when no precise identity is known yet -
    /// the Watch configuration then stays inert until the iPhone has connected to the sensor once.
    static func resolvedWatchDirectTransmitterName(transmitterId: String?, bluetoothName: String?) -> String {
        if let storedId = transmitterId?.uppercased(),
           storedId != ConstantsBluetoothPairing.dummyDexcomG7TypeTransmitterId.uppercased(),
           storedId != "DX",
           storedId.hasPrefix("DX"),
           storedId.count > 2 {
            return transmitterId ?? ""
        }

        if let bluetoothName,
           bluetoothName.uppercased().hasPrefix("DX"),
           bluetoothName.count > 2 {
            return bluetoothName
        }

        return ""
    }
}

/// current BG chart data used to manage watch views
struct WatchBgReadings: WatchPayload {
    var generatedAt: Double = Date().timeIntervalSince1970
    var hoursIncluded: Double = 12
    var bgReadingValues: [Double] = []
    var bgReadingDatesAsDouble: [Double] = []
    var slopeOrdinal: Int = 1
    var deltaValueInUserUnit: Double = 0
}

/// Compact AGP background data for the Watch main chart.
///
/// AGP is generated on iOS because the phone has Core Data access. The Watch only receives
/// minute-of-day percentile points, then maps them locally onto the current chart window.
/// Keeping the payload independent of chart width avoids stale endpoint redraws when the user
/// changes the visible hours.
struct WatchAGP: WatchPayload {
    var generatedAt: Double = Date().timeIntervalSince1970
    var requestID: Double = 0
    var visibleStartDateAsDouble: Double = 0
    var visibleEndDateAsDouble: Double = 0
    var dayCount: Int = 0
    var minuteOfDayValues: [Int] = []
    var p5Values: [Double] = []
    var p25Values: [Double] = []
    var medianValues: [Double] = []
    var p75Values: [Double] = []
    var p95Values: [Double] = []
}
