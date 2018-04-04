//
//  DebugLog.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2017/9/7.
//  Copyright © 2017年 龚杰洪. All rights reserved.
//

import Foundation

// MARK: - just for this framework

func println(_ object: Any...) {
    #if DEBUG
        var date = Date()
        date.addTimeInterval(TimeInterval(TimeZone.current.secondsFromGMT()))
        Swift.print(date, ":\n")
        Swift.print(object, terminator: "\n\n")
    #endif
}
