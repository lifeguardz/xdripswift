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

    /// `DexcomG7BluetoothSlot` raw value for the Watch's own connection. Default is the mobile-app
    /// slot (the evidence-based proven configuration); the iPhone sends the user's selection.
    var bluetoothSlotRawValue: Int = Int(DexcomG7BluetoothSlot.mobileApp.rawValue)

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
    /// slot) is passed to the transmitter on start but must not restart a running connection - with
    /// one deliberate exception: the slot IS part of the signature because it can be changed by the
    /// user (Watch Connection Channel) and a changed slot requires a restarted transmitter.
    private var lifecycleSignature: String {
        "\(enabled)-\(transmitterId)-\(pairingCode)-\(useOtherApp)-\(bluetoothSlotRawValue)"
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

/// One line of the on-watch connection log: a timestamp plus an already-formatted diagnostic
/// text (English only, so it stays identical across devices and easy to report).
struct WatchDirectConnectionLogEntry: Identifiable {
    let id = UUID()
    let timeStamp: Date
    let text: String
}

/// Manages the Watch app's own CGMG7Transmitter instance.
///
/// This is deliberately a slim manager: the heavy lifting (scan, J-PAKE authentication, backfill,
/// reconnection) already lives in the shared CGMG7Transmitter. This class owns its lifecycle,
/// translates the delegate surface into published UI state, and forwards glucose readings.
final class WatchSensorManager: NSObject, ObservableObject {

    @Published private(set) var connectionPhase: WatchSensorConnectionPhase = .inactive

    /// Advertised name of the sensor the current configuration connects to, nil while not configured.
    @Published private(set) var configuredTransmitterId: String?

    /// Time stamp of the newest reading the direct connection delivered, nil before the first one.
    @Published private(set) var latestReadingTimeStamp: Date?

    /// Sensor start date reconstructed from the current glucose and reported age, when the sensor
    /// reports one. Nil represents a stopped sensor session. Lets the Watch show a local sensor age
    /// even while the iPhone is unreachable.
    @Published private(set) var directSensorStartDate: Date?

    /// Human-readable sensor status reported with the current glucose response, when available.
    @Published private(set) var sensorStatusText: String?

    /// The sensor demands a Bluetooth pairing request that it cannot complete right now: the bond
    /// does not exist yet and the system pairing dialog can only appear while the Watch app is
    /// active in the foreground (Direct-to-Watch pairing, see docs/watch-direct-to-sensor.md).
    @Published private(set) var pairingRequired = false

    /// Rolling connection diagnostics (newest first) shown on the Direct Connection page. The
    /// entries answer "how far did the connection get" without console access. Capped so the
    /// buffer cannot grow while a sensor is unreachable for hours.
    @Published private(set) var connectionLogEntries: [WatchDirectConnectionLogEntry] = []

    private static let maximumConnectionLogEntries = 24

    /// Readings collected from the sensor. Delivered on an arbitrary queue: implementors must hop
    /// to the main queue themselves. Newest reading first (the CGM delegate contract).
    var onReadings: ((_ readings: [(valueMgDl: Double, timeStamp: Date, slopeOrdinal: Int?)], _ sensorAge: TimeInterval?) -> Void)?

    private var transmitter: CGMG7Transmitter?

    private var configuration: WatchDirectSensorConfiguration?

    private let log = Logger(subsystem: "xDrip", category: "WatchSensorManager")

    // MARK: - lifecycle

    /// Applies a configuration received from the iPhone. Restarts the transmitter only when the
    /// lifecycle-relevant fields changed, so routine status pushes never interrupt a connection.
    /// A (re)enable after the feature was off clears the Watch's stored ownership key first: in
    /// the handover model the iPhone re-owned the channel while the Watch was disabled, so the
    /// next connection must perform a fresh full ownership with the pairing code.
    func applyConfiguration(_ newConfiguration: WatchDirectSensorConfiguration) {
        let oldConfiguration = configuration

        configuration = newConfiguration
        newConfiguration.persist()

        configuredTransmitterId = newConfiguration.isStartable ? newConfiguration.transmitterId : nil

        guard !WatchDirectSensorConfiguration.hasSameLifecycle(oldConfiguration, newConfiguration) else { return }

        if newConfiguration.isStartable {
            let previouslyDisabledOrAbsent = oldConfiguration?.isStartable != true
            startTransmitter(clearPersistedAuthentication: previouslyDisabledOrAbsent)
            appendConnectionLogEntry(
                "Configuration applied: \(newConfiguration.transmitterId), channel \(String(format: "%02X", newConfiguration.bluetoothSlotRawValue))"
            )
        } else {
            stopTransmitter()
        }
    }

    /// Resumes a previously persisted configuration at app launch, before the iPhone has answered.
    /// The Watch keeps ownership across suspensions, so its stored key is not cleared here.
    func restorePersistedConfiguration() {
        guard configuration == nil, let persisted = WatchDirectSensorConfiguration.loadPersisted() else { return }

        configuration = persisted

        if persisted.isStartable {
            startTransmitter(clearPersistedAuthentication: false)
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

    private func startTransmitter(clearPersistedAuthentication: Bool) {
        guard let configuration else { return }

        stopTransmitter()

        // Reuse the Core Bluetooth identifier of a previous successful connection to the SAME
        // sensor: the transmitter restores the peripheral directly, so the sensor's short
        // five-minute wake windows are caught without a scan. The BluetoothTransmitter base class
        // persists the identifier/name pair after every successful connection; the name comparison
        // is the ownership guard so a newly configured sensor always starts with a clean scan.
        let storedAddress = Self.persistedPeripheralAddress(for: configuration.transmitterId)
        if storedAddress == nil {
            log.info("no persisted peripheral identifier for \(configuration.transmitterId, privacy: .public), starting with scan discovery")
        }

        let newTransmitter = CGMG7Transmitter(
            address: storedAddress,
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

        // see applyConfiguration: a (re)enabled Watch clears its own stored ownership key before
        // the first connection so the channel can be re-owned with a fresh J-PAKE exchange
        if clearPersistedAuthentication {
            newTransmitter.requestClearPersistedAuthentication()
        }

        connectionPhase = .connecting
        log.info("direct sensor connection starting for \(configuration.transmitterId, privacy: .public)")

        newTransmitter.connect()
    }

    private func stopTransmitter() {
        transmitter?.disconnectAndForget()
        transmitter = nil

        connectionPhase = .inactive
        configuredTransmitterId = nil
        latestReadingTimeStamp = nil
        directSensorStartDate = nil
        sensorStatusText = nil
        pairingRequired = false
    }

    /// Returns the CoreBluetooth identifier the BluetoothTransmitter base class persisted after a
    /// previous successful connection to the same sensor, or nil. The stored name doubles as the
    /// ownership guard: it is the sensor's advertised `DX...` name and must be identical to the
    /// configured transmitter ID, so a replacement sensor never reuses the old identifier.
    private static func persistedPeripheralAddress(for transmitterId: String) -> String? {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: BluetoothTransmitter.DefaultsKey.lastKnownDeviceName) == transmitterId,
              let address = defaults.string(forKey: BluetoothTransmitter.DefaultsKey.lastKnownDeviceAddress),
              !address.isEmpty,
              UUID(uuidString: address) != nil else { return nil }
        return address
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

    /// Records one diagnostic line in the connection log (newest first). Called from any queue:
    /// the buffer update is funneled through `publishOnMain`. Consecutive identical texts are
    /// collapsed so repeated sensor wake cycles do not bury the interesting changes.
    private func appendConnectionLogEntry(_ text: String) {
        publishOnMain {
            if let newest = self.connectionLogEntries.first, newest.text == text {
                return
            }

            self.connectionLogEntries.insert(
                WatchDirectConnectionLogEntry(timeStamp: Date(), text: text),
                at: 0
            )
            if self.connectionLogEntries.count > Self.maximumConnectionLogEntries {
                self.connectionLogEntries.removeLast(self.connectionLogEntries.count - Self.maximumConnectionLogEntries)
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

        if state == .poweredOff {
            appendConnectionLogEntry("Bluetooth is switched off")
        } else if state == .poweredOn {
            appendConnectionLogEntry("Bluetooth is switched on again")
        }
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
        appendConnectionLogEntry("Error: \(message)")
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
        let newestReadingValue = glucoseData[0].glucoseLevelRaw

        publishOnMain {
            self.connectionPhase = .connected
            self.latestReadingTimeStamp = readings[0].timeStamp
            // glucose arrives through the encrypted link: any earlier pairing requirement is over
            self.pairingRequired = false
        }

        log.info("received \(readingCount) reading(s), newest at \(newestReadingTimeStamp, privacy: .public)")

        appendConnectionLogEntry("Reading received: \(String(format: "%.0f", newestReadingValue)) mg/dL")

        onReadings?(readings, sensorAge)
    }

    func errorOccurred(xDripError: XdripError) {
        log.error("cgm transmitter error: \(xDripError.errorDescription ?? "unknown error", privacy: .public)")
    }
}

// MARK: - CGMG7TransmitterDelegate

extension WatchSensorManager: CGMG7TransmitterDelegate {
    /// The sensor rejected encrypted access because no Bluetooth bond exists yet. The system
    /// pairing request can only appear while this app is active in the foreground, so the UI shows
    /// a keep-open instruction while the connection keeps retrying at every sensor wake.
    func received(pairingRequired: Bool, cGMG7Transmitter _: CGMG7Transmitter) {
        publishOnMain {
            self.pairingRequired = pairingRequired
        }

        if pairingRequired {
            appendConnectionLogEntry("Sensor asks for Bluetooth pairing. Keep this app open and confirm the pairing request")
        } else {
            appendConnectionLogEntry("Bluetooth pairing is no longer required")
        }
    }

    /// Connection milestones from the shared transmitter: the funnel shown on the page.
    func received(connectionEvent: DexcomG7ConnectionEvent, cGMG7Transmitter _: CGMG7Transmitter) {
        appendConnectionLogEntry(connectionEvent.displayText)
    }

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