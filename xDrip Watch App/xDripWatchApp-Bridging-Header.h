//
//  xDripWatchApp-Bridging-Header.h
//  xDrip Watch App
//
//  Created as part of the Direct-to-Watch feature (docs/watch-direct-to-sensor.md).
//  Copyright © 2026 xDrip4iOS contributors. All rights reserved.
//
//  Objective-C boundary for the shared Dexcom G7 Bluetooth stack. The Watch app target compiles
//  the same vendored crypto sources as the iOS app, so it needs the same bridging surface. Only
//  the headers used by the shared CGM core belong here; iOS-only UI classes stay out.
//

#import "AESCrypt.h"
#import "DexcomG7AuthBridge.h"