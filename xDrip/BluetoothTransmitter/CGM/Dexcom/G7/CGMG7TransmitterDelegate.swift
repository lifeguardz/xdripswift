import Foundation

/// Diagnostic milestones that let a UI (the Watch's direct-connection page) show how far the
/// G7 connection funnel progressed, without console access to the OS log. Fire-and-forget:
/// implementations may drop events freely. Texts are English-only on purpose so they stay
/// greppable and identical across devices.
///
/// The funnels normal progress is:
/// discoveredSensor → connected → characteristicsDiscovered → authenticationStarted →
/// authenticationStatus → ownershipConfirmed → (data flows).
/// Deviations at each stage have their own case, including the sensor's encryption/bond
/// requirement which is reported through the separate `received(pairingRequired:)` callback.
enum DexcomG7ConnectionEvent: Equatable {
    /// Core Bluetooth delivered a G7-family advertisement while scanning. The name may be any
    /// nearby sensor: this proves the scan sees advertisements at all.
    case discoveredSensor(name: String)
    /// GATT connection established with a sensor.
    case connected
    /// Service and characteristic discovery completed.
    case characteristicsDiscovered
    /// The authentication state machine sent its opening packet. `fullOwnership` is true when a
    /// full J-PAKE bootstrap runs and false for the persisted-key short authentication.
    case authenticationStarted(fullOwnership: Bool)
    /// The sensor's `0x05` status. `authenticated` reflects key acceptance and `paired` whether
    /// the selected slot considers this client its confirmed owner.
    case authenticationStatus(authenticated: Bool, paired: Bool)
    /// Ownership or short-authentication completed; `Write_Control` will be armed.
    case ownershipConfirmed
    /// The stored shared key was rejected. This transmitter stops reconnecting intentionally,
    /// because the slot may now belong to another client.
    case authenticationRejectedPersistedKey
    /// A notification subscription failed. The full error text is included unchanged so
    /// encryption-related rejections remain visible.
    case notificationFailed(characteristic: String, error: String)
    /// Core Bluetooth disconnected, with the error text when the disconnect was not clean.
    case disconnected(error: String?)

    var displayText: String {
        switch self {
        case .discoveredSensor(let name):
            return "Saw sensor advertisement: \(name)"
        case .connected:
            return "Connected, discovering services"
        case .characteristicsDiscovered:
            return "Characteristics discovered"
        case .authenticationStarted(let fullOwnership):
            return fullOwnership ? "Starting full ownership (J-PAKE)" : "Starting short authentication"
        case .authenticationStatus(let authenticated, let paired):
            return "Auth status: authenticated=\(authenticated ? 1 : 0) paired=\(paired ? 1 : 0)"
        case .ownershipConfirmed:
            return "Authentication complete, requesting data"
        case .authenticationRejectedPersistedKey:
            return "Stored key rejected. Stopping retries"
        case .notificationFailed(let characteristic, let error):
            return "Notification failed (\(characteristic)): \(error)"
        case .disconnected(let error):
            return "Disconnected" + (error.map { ": \($0)" } ?? "")
        }
    }
}

/// Delivers G7-specific sensor information that does not belong to the common glucose delegate.
/// Implementations persist these values in the active `DexcomG7` Core Data entity and refresh the
/// status, lifetime, and sensor-session presentation that depends on them.
protocol CGMG7TransmitterDelegate: AnyObject {

    /// Delivers the sensor start date reconstructed from the current glucose and reported age.
    /// A nil value represents a stopped sensor session.
    func received(sensorStartDate: Date?, cGMG7Transmitter: CGMG7Transmitter)

    /// Delivers the human-readable algorithm state reported with the current sensor response.
    func received(sensorStatus: String?, cGMG7Transmitter: CGMG7Transmitter)

    /// Delivers the supported total session length reported by `0x52`, including the 12-hour grace
    /// period. The value is either 10.5 or 15.5 days expressed in seconds.
    func received(sensorSessionLength: TimeInterval, cGMG7Transmitter: CGMG7Transmitter)

    /// Delivers one complete full-version response. All fields belong to the same packet and are
    /// persisted together so a partial result can never suppress a later version request.
    func received(version: DexcomG7VersionMessage, cGMG7Transmitter: CGMG7Transmitter)

    /// Delivers one complete battery response and the exact time used for future request cadence.
    func received(
        battery: DexcomG7BatteryStatusMessage,
        readAt: Date,
        isFirstReading: Bool,
        cGMG7Transmitter: CGMG7Transmitter
    )

    /// Reports the sensor's Bluetooth-pairing requirement.
    ///
    /// A G7-family sensor allows the authentication characteristics over a plaintext link, but it
    /// requires an encrypted link - a Bluetooth bond - before it accepts anything through
    /// `Write_Control` or `Backfill`. Core Bluetooth cannot create a bond on request; the system
    /// pairing request appears when the app performs encrypted-requiring access while it is active
    /// in the foreground. `true` therefore means the connection needs the user to keep the app
    /// open and confirm an upcoming system pairing request. `false` confirms that an encrypted
    /// characteristic is usable again (the bond was established, or already existed).
    ///
    /// The default is a no-op because only the Watch app's direct-connection UI tracks this state.
    func received(pairingRequired: Bool, cGMG7Transmitter: CGMG7Transmitter)

    /// Delivers one connection-milestone event for diagnostics (see `DexcomG7ConnectionEvent`).
    func received(connectionEvent: DexcomG7ConnectionEvent, cGMG7Transmitter: CGMG7Transmitter)
}

extension CGMG7TransmitterDelegate {
    func received(pairingRequired: Bool, cGMG7Transmitter _: CGMG7Transmitter) {}

    /// Only the Watch's connection log consumes milestone events; other implementations keep
    /// their existing behaviour.
    func received(connectionEvent _: DexcomG7ConnectionEvent, cGMG7Transmitter _: CGMG7Transmitter) {}
}
