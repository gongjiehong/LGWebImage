//
//  UIDevice+Extensions.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2020/6/1.
//  Copyright © 2020 龚杰洪. All rights reserved.
//

import Foundation

public extension UIDevice {
    /// 物理内存大小
    static let physicalMemory: UInt64 = {
        return ProcessInfo().physicalMemory
    }()
}
