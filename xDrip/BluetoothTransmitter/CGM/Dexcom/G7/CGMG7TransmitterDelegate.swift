import Foundation

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
}

extension CGMG7TransmitterDelegate {
    func received(pairingRequired: Bool, cGMG7Transmitter _: CGMG7Transmitter) {}
}
