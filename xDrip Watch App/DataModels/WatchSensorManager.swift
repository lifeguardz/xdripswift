//
//  WatchSensorManager.swift
//  xDrip Watch App
//
//  Created as part of the Direct-to-Watch feature (docs/watch-direct-to-sensor.md).
//  Copyright © 2026 xDrip4iOS contributors. All rights reserved.
//
//  Owns the Watch app's direct Bluetooth connection to a Dexcom G7 / ONE+ / Stelo sensor.
//  The Watch connects as a primary authenticated client on the sensor's dedicated smartwatch
//  channel - it never touches the channel the iPhone app uses. Readings are forwarded through
//  `onReadings`; WatchStateModel merges them into the chart, refreshes the complication and
//  relays them to the iPhone.
//

import CoreBluetooth
import Foundation
import os

/// Direct-sensor configuration pushed by the iOS app inside every status update.
///
/// The iOS app is the source of truth: it knows the active G7-family sensor, its four-digit
/// applicator code and its session length. The Watch persists the latest configuration so a
/// relaunch of the Watch app can resume the connection without waiting for the iPhone.
struct WatchDirectSensorConfiguration: Codable, Equatable {

    /// Opt-in master switch. Direct connection only runs when the iPhone has it enabled
    /// (companion-only behaviour stays the default, see docs/watch-direct-to-sensor.md).
    var enabled: Bool

    /// Advertised sensor name / transmitter ID, e.g. "DXCM1ABC23". Used for discovery.
    var transmitterId: String

    /// Four-digit applicator code. Required for primary ownership of the smartwatch channel.
    var pairingCode: String

    /// Watch v1 always authenticates as primary client; coexistence is a phone-only concept.
    var useOtherApp: Bool = false

    /// `DexcomG7BluetoothSlot` raw value, always the smartwatch slot for this app.
    var bluetoothSlotRawValue: Int = Int(DexcomG7BluetoothSlot.smartWatch.rawValue)

    /// Supported total session length in seconds (10.5 or 15.5 days), when the iPhone knows it.
    var sensorSessionLengthAsDouble: Double?

    var bluetoothSlot: DexcomG7BluetoothSlot? {
        DexcomG7BluetoothSlot(rawValue: UInt8(bluetoothSlotRawValue))
    }

    var sensorSessionLength: TimeInterval? {
        sensorSessionLengthAsDouble.map { TimeInterval($0) }
    }

    /// Primary ownership cannot be established without the four-digit applicator code.
    var hasValidPairingCode: Bool {
        pairingCode.count == 4 && pairingCode.allSatisfy(\.isNumber)
    }

    var isStartable: Bool {
        enabled && !transmitterId.isEmpty && hasValidPairingCode
    }

    // MARK: - persistence

    private static let defaultsKey = "watchDirectSensorConfiguration"

    /// The configuration that changes the transmitter lifecycle. Everything else (session length,
    /// slot) is passed to the transmitter on start but must not restart a running connection.
    private var lifecycleSignature: String {
        "\(enabled)-\(transmitterId)-\(pairingCode)-\(useOtherApp)"
    }

    static func loadPersisted() -> WatchDirectSensorConfiguration? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(WatchDirectSensorConfiguration.self, from: data)
    }

    func persist() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    static func hasSameLifecycle(_ lhs: WatchDirectSensorConfiguration?, _ rhs: WatchDirectSensorConfiguration?) -> Bool {
        lhs?.lifecycleSignature == rhs?.lifecycleSignature
    }
}

/// Connection phases surfaced to the Watch UI.
enum WatchSensorConnectionPhase: Equatable {
    /// No configuration, or direct connection not enabled.
    case inactive
    /// Bluetooth hardware is off; connection resumes once it is switched on again.
    case bluetoothOff
    /// Scanning / connecting / authenticating; no readings received yet in this cycle.
    case connecting
    /// Authenticated and exchanging glucose data with the sensor.
    case connected
}

/// Manages the Watch app's own CGMG7Transmitter instance.
///
/// This is deliberately a slim manager: the heavy lifting (scan, J-PAKE authentication, backfill,
/// reconnection) already lives in the shared CGMG7Transmitter. This class owns its lifecycle,
/// translates the delegate surface into published UI state, and forwards glucose readings.
final class WatchSensorManager: NSObject, ObservableObject {

    @Published private(set) var connectionPhase: WatchSensorConnectionPhase = .inactive

    /// Sensor start date reconstructed from the current glucose and reported age, when the sensor
    /// reports one. Nil represents a stopped sensor session. Lets the Watch show a local sensor age
    /// even while the iPhone is unreachable.
    @Published private(set) var directSensorStartDate: Date?

    /// Human-readable sensor status reported with the current glucose response, when available.
    @Published private(set) var sensorStatusText: String?

    /// Readings collected from the sensor. Delivered on an arbitrary queue: implementors must hop
    /// to the main queue themselves. Newest reading first (the CGM delegate contract).
    var onReadings: ((_ readings: [(valueMgDl: Double, timeStamp: Date, slopeOrdinal: Int?)], _ sensorAge: TimeInterval?) -> Void)?

    private var transmitter: CGMG7Transmitter?

    private var configuration: WatchDirectSensorConfiguration?

    private let log = Logger(subsystem: "xDrip", category: "WatchSensorManager")

    // MARK: - lifecycle

    /// Applies a configuration received from the iPhone. Restarts the transmitter only when the
    /// lifecycle-relevant fields changed, so routine status pushes never interrupt a connection.
    func applyConfiguration(_ newConfiguration: WatchDirectSensorConfiguration) {
        let oldConfiguration = configuration

        configuration = newConfiguration
        newConfiguration.persist()

        guard !WatchDirectSensorConfiguration.hasSameLifecycle(oldConfiguration, newConfiguration) else { return }

        if newConfiguration.isStartable {
            startTransmitter()
        } else {
            stopTransmitter()
        }
    }

    /// Resumes a previously persisted configuration at app launch, before the iPhone has answered.
    func restorePersistedConfiguration() {
        guard configuration == nil, let persisted = WatchDirectSensorConfiguration.loadPersisted() else { return }

        configuration = persisted

        if persisted.isStartable {
            startTransmitter()
        }
    }

    /// Cheap connectivity nudge used when the Watch app becomes active: reconnects when Core
    /// Bluetooth gave up while the app was suspended. No-op while the connection is healthy.
    func ensureConnected() {
        guard let transmitter, configuration?.isStartable == true, connectionPhase != .connected else { return }

        transmitter.connect()
    }

    /// Stops the direct connection and clears the configuration received from the iPhone.
    func stop() {
        configuration = nil
        stopTransmitter()
    }

    private func startTransmitter() {
        guard let configuration else { return }

        stopTransmitter()

        let newTransmitter = CGMG7Transmitter(
            address: nil,
            name: configuration.transmitterId,
            transmitterID: configuration.transmitterId,
            useOtherApp: configuration.useOtherApp,
            pairingCode: configuration.pairingCode,
            bluetoothSlot: configuration.bluetoothSlot ?? .smartWatch,
            sensorSessionLength: configuration.sensorSessionLength,
            firmwareVersion: nil,
            firmwareBuildVersion: nil,
            firmwareVersionCode: nil,
            batteryLastReadDate: nil,
            calibrationToSendToTransmitter: nil,
            bluetoothTransmitterDelegate: self,
            cGMG7TransmitterDelegate: self,
            cGMTransmitterDelegate: self
        )

        transmitter = newTransmitter

        connectionPhase = .connecting
        log.info("direct sensor connection starting for \(configuration.transmitterId, privacy: .public)")

        newTransmitter.connect()
    }

    private func stopTransmitter() {
        transmitter?.disconnectAndForget()
        transmitter = nil

        connectionPhase = .inactive
        directSensorStartDate = nil
        sensorStatusText = nil
    }

    // MARK: - private helpers

    private func publishOnMain(_ update: @escaping () -> Void) {
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async { [weak self] in
                guard self != nil else { return }
                update()
            }
        }
    }
}

// MARK: - BluetoothTransmitterDelegate

extension WatchSensorManager: BluetoothTransmitterDelegate {
    func didConnectTo(bluetoothTransmitter: BluetoothTransmitter) {
        publishOnMain {
            self.connectionPhase = .connecting
        }
        log.info("direct sensor connected, authenticating")
    }

    func didDisconnectFrom(bluetoothTransmitter: BluetoothTransmitter) {
        publishOnMain {
            // CGMG7Transmitter owns the reconnection policy; show the in-progress phase.
            if self.connectionPhase != .inactive && self.connectionPhase != .bluetoothOff {
                self.connectionPhase = .connecting
            }
        }
        log.info("direct sensor disconnected, reconnecting")
    }

    func deviceDidUpdateBluetoothState(state: CBManagerState, bluetoothTransmitter: BluetoothTransmitter) {
        publishOnMain {
            self.connectionPhase = state == .poweredOff ? .bluetoothOff : (self.configuration?.isStartable == true ? .connecting : .inactive)
        }
        log.info("bluetooth state changed: \(String(describing: state), privacy: .public)")
    }

    func transmitterNeedsPairing(bluetoothTransmitter: BluetoothTransmitter) {
        // G7 authentication is J-PAKE at the application layer; classic pairing requests are not
        // expected on the watch channel. Logged for diagnostics only.
        log.error("unexpected classic pairing request from sensor")
    }

    func successfullyPaired() {}

    func pairingFailed() {
        log.error("pairing failed")
    }

    func error(message: String) {
        log.error("transmitter error: \(message, privacy: .public)")
    }

    func heartBeat() {}
}

// MARK: - CGMTransmitterDelegate

extension WatchSensorManager: CGMTransmitterDelegate {
    func newSensorDetected(sensorStartDate: Date?) {}

    func sensorStopDetected() {
        publishOnMain {
            self.directSensorStartDate = nil
        }
        log.info("direct sensor session stopped")
    }

    func sensorNotDetected() {}

    func cgmTransmitterInfoReceived(glucoseData: inout [GlucoseData], transmitterBatteryInfo: TransmitterBatteryInfo?, sensorAge: TimeInterval?) {
        guard glucoseData.count > 0 else { return }

        let readings = glucoseData.map { reading in
            (valueMgDl: reading.glucoseLevelRaw, timeStamp: reading.timeStamp, slopeOrdinal: reading.slopeOrdinal)
        }

        // copy for the log first: Logger interpolations are escaping autoclosures that cannot
        // capture the inout parameter directly
        let readingCount = glucoseData.count
        let newestReadingTimeStamp = glucoseData[0].timeStamp.description

        publishOnMain {
            self.connectionPhase = .connected
        }

        log.info("received \(readingCount) reading(s), newest at \(newestReadingTimeStamp, privacy: .public)")

        onReadings?(readings, sensorAge)
    }

    func errorOccurred(xDripError: XdripError) {
        log.error("cgm transmitter error: \(xDripError.errorDescription ?? "unknown error", privacy: .public)")
    }
}

// MARK: - CGMG7TransmitterDelegate

extension WatchSensorManager: CGMG7TransmitterDelegate {
    func received(sensorStartDate: Date?, cGMG7Transmitter: CGMG7Transmitter) {
        publishOnMain {
            self.directSensorStartDate = sensorStartDate
        }
    }

    func received(sensorStatus: String?, cGMG7Transmitter: CGMG7Transmitter) {
        publishOnMain {
            self.sensorStatusText = sensorStatus
        }
    }

    func received(sensorSessionLength: TimeInterval, cGMG7Transmitter: CGMG7Transmitter) {
        log.info("sensor session length reported: \(sensorSessionLength.description, privacy: .public) seconds")
    }

    func received(version: DexcomG7VersionMessage, cGMG7Transmitter: CGMG7Transmitter) {
        log.info("sensor firmware version: \(version.firmwareVersion, privacy: .public) (build \(version.buildVersion))")
    }

    func received(battery: DexcomG7BatteryStatusMessage, readAt: Date, isFirstReading: Bool, cGMG7Transmitter: CGMG7Transmitter) {
        log.info("sensor battery: voltageB \(battery.voltageB) (10 mV), runtime \(battery.runtime)")
    }
}