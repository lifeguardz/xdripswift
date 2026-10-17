import Foundation
import CoreBluetooth

/// to be implemented for anyone who needs to receive information from a specific type of cgm transmitter
protocol CGMTransmitterDelegate:AnyObject {
     
    /// only for transmitters that can detect new sensor
    /// - parameters:
    ///     - detected sensor start time, optional, default nil
    func newSensorDetected(sensorStartDate: Date?)
    
    /// only for transmitters that can detect an expired sensor - only used for Firefly (at the time of writing this), but could probably also be used for Libre
    func sensorStopDetected()
    
    /// only for transmitters that can detect missing sensor
    func sensorNotDetected()
    
    /// to pass back transmitter data from cgmtransmitter
    /// - parameters:
    ///     - glucoseData : array of RawGlucoseData, can be empty array, first entry is the youngest
    ///     - transmitterBatteryInfo : needed for battery level alarm
    ///     - sensorAge : only if transmitter can give that info, eg MiaoMiao, otherwise nil
    func cgmTransmitterInfoReceived(glucoseData:inout [GlucoseData], transmitterBatteryInfo:TransmitterBatteryInfo?, sensorAge: TimeInterval?)
    
    /// to pass some text error message, delegate can decide to show to user, log, ...
    func errorOccurred(xDripError: XdripError)

    /// Reports a decoded sensor/transmitter health state without promoting generic BLE errors.
    func sensorHealthEventOccurred(_ event: CGMSensorHealthEvent)

    /// Reports the decoded result of a sensor-start request.
    /// Dexcom G6/ONE provides this callback. The default implementation does nothing.
    func sensorSessionStartResultReceived(_ result: CGMSensorSessionStartResult)

    /// confirms that a validated glucose packet belongs to the matching local sensor session
    /// Dexcom G6/ONE provides this callback. The default implementation does nothing.
    func sensorSessionConfirmed(startDate: Date)

    #if os(iOS)
    /// Reports G6/ONE calibration stages after reconciling the transmitter's session date.
    /// G6/ONE-only requirement: the G5 transmitter stack is not compiled into the watchOS target
    /// (Direct-to-Watch v1 supports G7/ONE+/Stelo only, see docs/watch-direct-to-sensor.md).
    func dexcomG6CalibrationStateReceived(_ state: DexcomAlgorithmState, sensorStartDate: Date, from transmitter: CGMG5Transmitter)
    #endif

    /// Asks the delegate to persist the transmitter-side outcome flags for one calibration that was
    /// submitted through `calibrate` or supplied when the transmitter was created.
    ///
    /// The delegate owns the calibration store and re-applies the result there, identified by the
    /// snapshot's `id`. Transmitters stay fully decoupled from Core Data. A `nil` flag means the
    /// transmitter has no new information for it and the stored value must be left unchanged.
    func transmitterCalibrationOutcomeReceived(id: String, sentToTransmitter: Bool?, acceptedByTransmitter: Bool?)
    
}

extension CGMTransmitterDelegate {
    func sensorHealthEventOccurred(_ event: CGMSensorHealthEvent) {}
    func sensorSessionStartResultReceived(_ result: CGMSensorSessionStartResult) {}
    func sensorSessionConfirmed(startDate: Date) {}
    #if os(iOS)
    func dexcomG6CalibrationStateReceived(_ state: DexcomAlgorithmState, sensorStartDate: Date, from transmitter: CGMG5Transmitter) {}
    #endif

    /// Default no-op: platforms without a calibration store (watchOS Direct-to-Watch) never submit
    /// calibrations, so they never receive outcomes either.
    func transmitterCalibrationOutcomeReceived(id: String, sentToTransmitter: Bool?, acceptedByTransmitter: Bool?) {}
}
