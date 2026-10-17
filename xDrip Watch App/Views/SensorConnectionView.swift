//
//  SensorConnectionView.swift
//  xDrip Watch App
//
//  Created as part of the Direct-to-Watch feature (docs/watch-direct-to-sensor.md).
//  Copyright © 2026 xDrip4iOS contributors. All rights reserved.
//
//  Status and opt-in control for the Watch app's direct Bluetooth connection to the
//  Dexcom G7-family sensor. The iPhone owns the configuration (sensor credentials and the
//  opt-in switch): the toggle here asks the iPhone to change it, and the fresh configuration
//  arrives with the next status update. Companion-only behaviour stays the default.
//

import SwiftUI

struct SensorConnectionView: View {
    @EnvironmentObject var watchState: WatchStateModel

    var body: some View {
        List {
            statusSection
            toggleSection
            sensorSection
        }
        .listStyle(.carousel)
        .navigationTitle(Texts_WatchApp.directConnection)
    }

    // MARK: - sections

    private var statusSection: some View {
        Section {
            HStack(spacing: 6) {
                Circle()
                    .fill(phaseColor)
                    .frame(width: 10, height: 10)

                Text(phaseText)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)

                Spacer()
            }
            .padding(.vertical, 2)

            if watchState.directConnectionPhase == .connecting && watchState.directSensorPairingRequired {
                Text(Texts_WatchApp.directConnectionPairingNeeded)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
                    .minimumScaleFactor(0.8)
            }
        } header: {
            Text(Texts_WatchApp.directConnectionStatus)
        }
    }

    private var toggleSection: some View {
        Section {
            Toggle(isOn: directConnectionBinding) {
                Text(Texts_WatchApp.directConnectionToggle)
                    .font(.system(size: 13))
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
            }

            if !watchState.session.isReachable {
                Text(Texts_WatchApp.directConnectionIPhoneUnreachable)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Text(Texts_WatchApp.directConnectionSafetyNote)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(4)
        }
    }

    @ViewBuilder private var sensorSection: some View {
        if let sensorName = watchState.directSensorName {
            Section {
                row(label: Texts_WatchApp.directConnectionSensor, value: sensorName)

                if let directSensorStartDate = watchState.directSensorStartDate {
                    row(label: Texts_WatchApp.directConnectionSensorStart, value: directSensorStartDate.formatted(date: .abbreviated, time: .omitted))
                }

                if let latestDirectReadingTimeStamp = watchState.latestDirectReadingTimeStamp {
                    row(label: Texts_WatchApp.directConnectionLastReading, value: latestDirectReadingTimeStamp.formatted(date: .omitted, time: .shortened))
                }
            }
        } else {
            Section {
                Text(Texts_WatchApp.directConnectionNotConfigured)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
            }
        }
    }

    // MARK: - private helpers

    /// The toggle reflects the configuration the iPhone last confirmed, never a local-only value:
    /// a change is sent to the iPhone and the toggle snaps back until the fresh status arrives.
    private var directConnectionBinding: Binding<Bool> {
        Binding(
            get: { watchState.directSensorConfigEnabled },
            set: { requestedEnabled in
                _ = watchState.requestDirectToSensorChange(enabled: requestedEnabled)
            }
        )
    }

    private var phaseText: String {
        switch watchState.directConnectionPhase {
        case .inactive:
            return Texts_WatchApp.directConnectionOff
        case .bluetoothOff:
            return Texts_WatchApp.directConnectionBluetoothOff
        case .connecting:
            return Texts_WatchApp.directConnectionConnecting
        case .connected:
            return Texts_WatchApp.directConnectionConnected
        }
    }

    private var phaseColor: Color {
        switch watchState.directConnectionPhase {
        case .inactive:
            return .gray
        case .bluetoothOff:
            return .gray
        case .connecting:
            return .orange
        case .connected:
            return .green
        }
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }
}

#Preview {
    SensorConnectionView()
}