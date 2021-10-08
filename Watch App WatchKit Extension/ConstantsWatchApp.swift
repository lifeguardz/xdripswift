//
//  ConstantsWatchApp.swift
//  Watch App WatchKit Extension
//
//  Created by Paul Plant on 8/10/21.
//  Copyright © 2021 Johan Degraeve. All rights reserved.
//

import Foundation
import UIKit

enum ConstantsWatchApp {
    
    static let minutesAgoWarningMinutes = 11
    static let minutesAgoUrgentMinutes = 21
    
    ///
    static let minsAgoLabelColor = UIColor.lightGray
    static let minsAgoLabelColorWarning = UIColor.orange
    static let minsAgoLabelColorUrgent = UIColor.red
    static let minsAgoLabelColorDeactivated = UIColor.gray
    
    static let deltaLabelColor = UIColor.white
    
    static let labelColorDeactivated = UIColor.gray
    
    /// glucose colors - for values in range
    static let glucoseInRangeColor = UIColor.green
    
    /// glucose colors - for values higher than urgentHighMarkValue or lower than urgent LowMarkValue
    static let glucoseUrgentRangeColor = UIColor.red

    /// glucose colors - for values between highMarkValue and urgentHighMarkValue or between urgentLowMarkValue and lowMarkValue
    static let glucoseNotUrgentRangeColor = UIColor.yellow
    
    
    
}
