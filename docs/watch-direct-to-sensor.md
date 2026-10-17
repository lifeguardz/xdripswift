# Feature Plan: Direct-to-Watch sensor connection (Dexcom G7 / ONE+ / Stelo)

- **Status:** planned, not started
- **Scope:** personal fork (`lifeguardz/xdripswift`), based on upstream `JohanDegraeve/xdripswift` v7.1.1 (build 4233)
- **First target sensor family:** Dexcom G7 / ONE+ / Stelo (native Bluetooth, primary mode)
- **Related upstream issues:** `JohanDegraeve/xdripswift#685` (G7 without Dexcom app), upstream FAQ currently states the Watch app *cannot* connect directly to a CGM — this feature changes that for this fork

---

## 1. Goal

Let the Apple Watch app connect **directly to the CGM sensor over Bluetooth**, independent of the iPhone — the same model as Dexcom's official "Direct to Watch" feature. With this enabled, the Watch shows real-time glucose when the iPhone is out of range, at home, swimming, or off. When the iPhone is around, both devices hold their own sensor connections and data is merged without duplication.

---

## 2. Current state (verified in this codebase)

The Watch app today is a **companion-only display**:

| Aspect | Evidence |
|---|---|
| Watch target compiles ~40 UI/state files only — no Bluetooth code | `project.pbxproj`, Sources phase of target `xDrip Watch App` |
| All data arrives via `WCSession` from the iPhone | `xDrip Watch App/DataModels/WatchStateModel.swift` (`requestWatchUpdate: status / bgReadings / agp`) |
| Phone-side sender | `xDrip/Managers/Watch/WatchManager.swift` (`WatchUpdateType` payloads, `sendMessage` / `transferUserInfo`) |
| Watch is embedded, not independent | `WKCompanionAppBundleIdentifier = $(MAIN_APP_BUNDLE_IDENTIFIER)`, `WKRunsIndependentlyOfCompanionApp = NO` |
| Complications update from app-group UserDefaults written by the Watch app | `ComplicationSharedUserDefaultsModel` + `WidgetCenter.reloadAllTimelines()` in `WatchStateModel.updateComplicationData()` |
| Upstream confirms this by design | FAQ: "Can Apple Watch connect directly to my CGM without the iPhone? No." |

Consequence today: with the iPhone away or the app suspended, the Watch shows stale data and falls back to `---` after ~20 minutes.

---

## 3. Why this is feasible

### 3.1 watchOS supports it

- CoreBluetooth **central role** (scan / connect / services / notifications) works on watchOS.
- `bluetooth-central` in `UIBackgroundModes` enables BLE during **Background App Refresh** since watchOS 8 (WWDC21 session *Connect Bluetooth devices to Apple Watch*).
- WWDC22 session *Get timely alerts from Bluetooth devices on watchOS* added **background peripheral discovery** and **characteristic monitoring** — the system wakes the app when a subscribed characteristic notifies. This is the exact pattern the official Dexcom Watch app relies on.
- watchOS 10 is already the deployment target of the Watch app in this project.

### 3.2 The sensor supports it — Dexcom G7 has three Bluetooth channels

Confirmed from Dexcom's own FAQ ("If I use Direct to Watch, can I still connect to my AID system?"):

> **Dexcom G7 has three Bluetooth channels:**
> 1. **Smartphone** – allows glucose data to be sent to the Clarity and Follow apps
> 2. **Smartwatch**
> 3. **Dexcom Receiver OR connected AID system**
>
> G7 can display glucose on multiple devices … simultaneously and independent of each other.

Implications:

- The Watch app can be a **fully authenticated primary client on the smartwatch channel** without stealing or disturbing the iPhone's smartphone-channel connection.
- No exclusive handover between iPhone and Watch is required (unlike earlier assumptions for G6-class hardware).
- Both devices may collect the same readings; merged by timestamp on the iPhone.

### 3.3 This repo already contains the entire hard part — for iOS

All of it lives in the iOS app target only, but it is pure Swift/CoreBluetooth/C/ObjC and architecturally portable:

- `xDrip/BluetoothTransmitter/Generic/BluetoothTransmitter.swift` — `CBCentralManager` wrapper (connect, discovery, notifications, queue serialization)
- `xDrip/BluetoothTransmitter/CGM/Generic/CGMTransmitter.swift` — CGM transmitter base + `CGMTransmitterType`
- `xDrip/BluetoothTransmitter/CGM/Dexcom/G7/CGMG7Transmitter.swift` + delegate — **Primary mode** (xDrip performs full J-PAKE authentication with the 4-digit pairing code, ECC signing, glucose/backfill commands) and **Coexistence mode** (passive attach to another app's connection, observing authenticated status and 0x31 glucose + 0x25 clock coexistence packets)
- `xDrip/BluetoothTransmitter/CGM/Dexcom/Generic/` — the complete Dexcom protocol message stack (see §6.1 for the list), including the G7 crypto: `DexcomG7ECC.c`, `DexcomG7AuthBridge.m`, `DexcomG7ProofSigner.swift`, `DexcomG7AuthSession.swift`
- Recent proof of maturity: v7.1.1 fixed G7 coexistence reconnection between readings (especially in background).

### 3.4 The official app proves the end-to-end behavior

Dexcom G7 Direct-to-Watch shipped June 2024 (US/UK/IE) as "the first CGM that connects directly to Apple Watch"; community reports (e.g. jseaber.com, 2024) describe days of reliable watch-side collection with the phone away. Third-party watch apps face the same watchOS constraints we do.

---

## 4. Non-goals (v1)

- ❌ G6 / ONE / Anubis watch support (G6 manufacturing ends July 2026; possible later phase)
- ❌ Libre 2 / MiaoMiao / Bubble / Medtrum watch support (later, same pattern)
- ❌ Watch-only App Store distribution (the Watch app stays embedded in the iOS app; it just becomes *able* to run without the phone)
- ❌ Calibration entry from the Watch (calibrations stay iPhone-driven in v1; the Watch consumes the native sensor algorithm output and synced calibration context)
- ❌ Nightscout / Dexcom Share upload from the Watch (relayed readings still flow to the iPhone, which remains the upload/alerts/HealthKit brain)
- ❌ HealthKit, AID integration, or alerting parity on the watch beyond basic high/low local notifications

---

## 5. Architecture decisions

1. **G7 family first.** Modern protocol, official direct-to-watch precedent, dedicated smartwatch channel, no discontinued-hardware risk.
2. **Watch connects as primary client on the smartwatch channel.** Uses the existing `CGMG7Transmitter` primary-mode code path (needs transmitter ID + 4-digit pairing code). No handover, no stealing the phone's channel.
3. **Coexistence/passive mode is the fallback**, reusing the existing observation logic when another client owns the connection in range — but the leave-phone-at-home use case requires primary mode, so primary is the default when the user enables Direct-to-Watch.
4. **Slim watch-side manager, not a port of `BluetoothPeripheralManager`.** The iOS manager is tightly coupled to Core Data, UI, and UIKit. The Watch gets a new lightweight `WatchSensorManager` that drives one transmitter.
5. **No Core Data on the watch.** Readings live in a ring buffer in the shared app-group UserDefaults (pattern already established by `ComplicationSharedUserDefaultsModel`). History, statistics, uploads, HealthKit and alerting remain iPhone responsibilities.
6. **Timestamp-based merge.** When the watch relays its readings to the iPhone (`transferUserInfo`), the phone ingests them through the normal reading-ingestion path with existing timestamp dedupe — overlapping readings collected by both devices collapse to one.
7. **Configuration flows phone → watch.** The iPhone already knows transmitter type, transmitter ID, pairing code, sensor session start date, limits and units. Enabling Direct-to-Watch pushes this once via WCSession; the watch settings screen also allows manual entry/edit.
8. **Companion mode stays the default.** Direct-to-Watch is an explicit toggle. When off (or sensor connection unavailable), behavior is exactly today's companion app.
9. **Battery honesty.** Direct mode is opt-in; watch battery impact is real and documented. Swimming/submersion drops readings (same as the official app).

---

## 6. Implementation phases

### Phase 0 — Independent watch app configuration

- `project.pbxproj`: set `INFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp = YES` for the `xDrip Watch App` target (Debug + Release).
- Add `bluetooth-central` background mode to the Watch app's Info configuration (`UIBackgroundModes`).
- **Acceptance:** Watch app builds and runs with the iPhone app not installed; existing companion flows still work when it is installed.

### Phase 1 — Compile the G7 core for watchOS *(make-or-break)*

Add to the `xDrip Watch App` target's Sources build phase:

- `BluetoothTransmitter/Generic/BluetoothTransmitter.swift` + `BluetoothTransmitterDelegate.swift`
- `BluetoothTransmitter/CGM/Generic/CGMTransmitter.swift` + `CGMTransmitterDelegate.swift`
- `BluetoothTransmitter/CGM/Dexcom/G7/CGMG7Transmitter.swift` + `CGMG7TransmitterDelegate.swift`
- The Dexcom protocol folder `BluetoothTransmitter/CGM/Dexcom/Generic/` (Swift + C/ObjC), including at least:
  - G7 primary stack: `DexcomG7AuthSession.swift`, `DexcomG7AuthBridge.h/.m`, `DexcomG7ProofSigner.swift`, `DexcomG7ECC.c/.h`, `DexcomG7GlucoseDataRxMessage.swift`, `DexcomG7BackfillMessage.swift`, `DexcomG7CalibrationMessages.swift`, `DexcomG7DiagnosticMessages.swift`, `DexcomG7ExtendedVersionMessage.swift`
  - Shared message machinery: `TransmitterMessage.swift`, `DexcomTransmitterOpCode.swift`, `NSData+CRC.swift`, `DexcomTransmitterTimeRxMessage.swift` / `DexcomTransmitterTimeTxMessage.swift`, `DexcomBackfillStream.swift`, `DexcomBackfillTxMessage.swift`, `DexcomSessionStart*` / `DexcomSessionStop*`, `DexcomCalibrationTxMessage` / `DexcomCalibrationRxMessage`, `KeepAliveTxMessage.swift`, `PairRequestTxMessage.swift`, `ResetMessage.swift`, `SensorDataRxMessage.swift` / `SensorDataTxMessage.swift`, `String+Dexcom.swift`, `AESCrypt.h/.m`
  - The exact minimal set is resolved by the compiler; simplest start is adding the whole `Dexcom/Generic` folder and trimming.
- Supporting shared types the watch target already partially includes (`FollowerDataSourceType`, constants, etc.) — extend as needed.
- `#if os(iOS)` guards for iOS-only APIs encountered during compile (e.g. `UIApplication` background tasks in `BluetoothTransmitter`-adjacent code, UIKit imports).
- **Acceptance:** Watch target compiles for watchOS with the full G7 protocol stack; existing iOS target builds unchanged; unit tests still pass.

### Phase 2 — Watch-side sensor manager + data flow

- New `WatchSensorManager` (in the watch target):
  - constructs `CGMG7Transmitter` with the shared config,
  - implements the minimal delegate surface (connected/disconnected, glucose, backfill, sensor age/battery),
  - maintains the readings ring buffer (last ~24–36 h) in app-group UserDefaults,
  - feeds `WatchStateModel` so all existing views render unchanged,
  - pushes newly collected readings to the iPhone via `session.transferUserInfo` (same channel the complication data already uses, but watch→phone direction).
- Phone side (`WatchManager.swift` + reading ingestion):
  - handle the new `watchCollectedReadings` payload type,
  - insert into the existing ingestion path used by transmitters (timestamp dedupe handles the both-connected overlap),
  - keep owning Nightscout/Share upload, HealthKit, alerting.
- Config sync phone → watch: extend `currentStatus()` payload with transmitter type/ID, pairing code, sensor session start date (needed by the watch to authenticate and timestamp coexistence-style packets).
- **Acceptance:** Watch, with Direct enabled, authenticates to a real G7 and displays live readings with the iPhone in airplane mode; iPhone later receives the readings collected while it was away, deduped.

### Phase 3 — Watch settings UI + mode switching

- New watch settings screen (SwiftUI, styled per existing watch views):
  - sensor type (G7/ONE+/Stelo),
  - transmitter ID entry,
  - pairing code entry,
  - "Direct to Watch" toggle,
  - connection status / last reading display.
- `WatchStateModel` switches data source: direct readings when enabled and connected; companion (`WCSession`) data otherwise; `MainViewDataSourceView` shows the watch's own connection state (noise indicator, sensor age already exist in the model).
- **Acceptance:** full enable/disable flow works from the watch alone; toggling off restores pure companion behavior.

### Phase 4 — Background execution, alerts, complications

- Verify/declare characteristic monitoring so watchOS wakes the app per glucose notification; add `WKRefreshBackgroundTask` handling for housekeeping (reconnect attempts, buffer flush).
- Reload existing complications directly from watch-collected readings (`updateComplicationData()` already writes the shared model — it just gets fed locally now).
- Watch-local high/low notifications using the already-synced limit values (`urgentLow/low/high/urgentHigh`).
- **Acceptance:** Readings continue (and complications refresh) while the watch app is not in the foreground over a multi-hour real-world test; alert fires on the watch without the iPhone.

### Phase 5 — Hardening + later phases

- Battery drain measurement and reconnect-tuning on real hardware (Series 4+ / watchOS 10 minimum, as README states).
- Document conflicts: official Dexcom watch app competes for the smartwatch channel.
- Later (separate efforts, same pattern): G6/ONE transmitter port, Libre transmitters, watch-entered calibrations, optional watch-side upload when phone unreachable for long periods.

---

## 7. Risks & mitigations

| Risk | Assessment | Mitigation |
|---|---|---|
| watchOS background execution is refresh-driven, not continuously guaranteed | Real; official Dexcom app lives with the same constraint and works well per user reports | Characteristic monitoring + background app refresh; foreground-connected UX is first-class; honest docs |
| Watch battery drain | Real; BLE central + background wake costs energy | Opt-in toggle; show battery indicator; keep-alive only while enabled |
| Two concurrent primary clients (phone + watch) confuse the transmitter | Low for G7 — three channels exist by design; both clients run the same code here | Primary mode on separate channels; timestamp dedupe on merge; fall back to coexistence observation if needed |
| J-PAKE / ECC port to watchOS has hidden iOS assumptions | Low — code is Foundation/CoreBluetooth + C | Phase 1 compile proves it early; ObjC bridging header for the watch target |
| `BluetoothTransmitter` core uses iOS-only APIs subtly | Medium — file is large (1000+ lines) | `#if os(iOS)` guards; watch-specific subclass if the split is cleaner |
| Official Dexcom watch app already installed | Both compete for the smartwatch channel | Document; detect and surface "smartwatch channel busy" state |
| Upstream drift makes the fork hard to rebase | Accepted (personal fork first) | Keep changes additive and phase-isolated to ease future upstream PRs |
| Swimming/submersion drops readings | Hardware reality, identical to official app | Document it |

---

## 8. Testing strategy

- **Protocol unit tests:** the Dexcom message classes are pure data — the existing iOS test suite (`xDrip Tests`) keeps covering them once files are shared; add watchOS target tests for the ring buffer and merge logic.
- **Bench harness:** fake G7 peripheral (or recorded characteristic traces) to drive the watch app without hardware.
- **Hardware acceptance per phase:** real G7 sensor + watch + phone; airplane-mode phone test; long-range test; overnight background test; both-connected overlap test (verify no duplicates on iPhone).
- **Safety note (from README):** xDrip4iOS is experimental, not a medical device; never rely on it as the only glucose source. Direct-to-Watch inherits this warning — keep it prominent in any UI/docs we add.

---

## 9. References

- Dexcom FAQ — *If I use Direct to Watch, can I still connect to my AID system?* (three Bluetooth channels) — dexcom.com
- Dexcom press release — *Dexcom G7 Now Connects Directly to Apple Watch in the U.S.* (June 5, 2024)
- WWDC21 — *Connect Bluetooth devices to Apple Watch* (bluetooth-central background mode)
- WWDC22 — *Get timely alerts from Bluetooth devices on watchOS* (characteristic monitoring)
- Apple docs — *Interacting with Bluetooth peripherals during background app refresh*
- xDrip4iOS FAQ — current "No" answer this feature supersedes for this fork
- Upstream issue `JohanDegraeve/xdripswift#685` — G7 without Dexcom app context
- jseaber.com (2024) — real-world report of G7 Direct-to-Watch behavior
- In-repo: `xDrip/BluetoothTransmitter/CGM/Dexcom/G7/CGMG7Transmitter.swift` header comment (primary vs coexistence mode design notes)

---

## 10. Open questions

1. Should the watch request sensor **backfill on reconnect** (existing `DexcomBackfillStream`) in v1, or only live readings? (Recommended: backfill — code already exists.)
2. Where should the **pairing code** be stored on the watch — keychain (matches iOS behavior) vs app-group UserDefaults? (Recommended: keychain.)
3. Should the watch relay readings **immediately** when reachable, or batched (e.g. every 5 min like `transferUserInfo` throttling on the phone side)? (Recommended: batched + on-session-activation flush.)
4. Do we surface a complication "source" indicator (direct vs relayed) so the user can see the data path at a glance?