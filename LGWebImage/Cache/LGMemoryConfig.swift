//
//  LGMemoryConfig.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2019/3/6.
//  Copyright © 2019年 龚杰洪. All rights reserved.
//

import Foundation


/// 存储内存缓存相关配置
public struct LGMemoryConfig {
    /// 缓存名字，仅用于标识当前缓存是哪一个
    public let name: String
    
    /// 过期时间, 默认12（小时） * 60（分） * 60（秒）
    public let expiry: LGExpiry
    
    /// 数量上限，默认UInt64.max
    public let countLimit: UInt64
    
    /// 内存占用上限，默认物理内存的5%作为最大内存缓存空间，超出的将被逐出, 单位Byte
    public let totalCostLimit: UInt64
    
    /// 自动整理时间间隔，默认5秒
    public let autoTrimInterval: TimeInterval
    
    /// 是否在接收到内存警告时清空缓存，默认true
    public let shouldRemoveAllObjectsOnMemoryWarning: Bool
    
    /// 是否在程序进入后台是清空缓存，默认true
    public let shouldRemoveAllObjectsWhenEnteringBackground: Bool
    
    /// 是否在主线程释放内存，默认false
    public let isReleaseOnMainThread: Bool
    
    /// 是否异步释放内存，默认true
    public let isReleaseAsynchronously: Bool
    
    /// 工厂方法初始化
    ///
    /// - Parameters:
    ///   - name: 缓存名字，仅用于标识当前缓存是哪一个
    ///   - expiry: 过期时间, 默认12（小时） * 60（分） * 60（秒）
    ///   - countLimit: 数量上限，默认UInt64.max
    ///   - totalCostLimit: 内存占用上限，默认物理内存的不超过5%作为最大内存缓存空间，超出的将被逐出, 单位Byte
    ///   - autoTrimInterval: 自动整理时间间隔，默认5秒
    ///   - shouldRemoveAllObjectsOnMemoryWarning: 是否在接收到内存警告时清空缓存，默认true
    ///   - shouldRemoveAllObjectsWhenEnteringBackground: 是否在程序进入后台是清空缓存，默认true
    ///   - isReleaseOnMainThread: 是否在主线程释放内存，默认false
    ///   - isReleaseAsynchronously: 是否异步释放内存，默认true
    public init(name: String,
                expiry: LGExpiry = .ageLimit(43_200),
                countLimit: UInt64 = UInt64.max,
                totalCostLimit: UInt64 = ProcessInfo().physicalMemory / 100 * 5,
                autoTrimInterval: TimeInterval = 5.0,
                shouldRemoveAllObjectsOnMemoryWarning: Bool = true,
                shouldRemoveAllObjectsWhenEnteringBackground: Bool = true,
                isReleaseOnMainThread: Bool = false,
                isReleaseAsynchronously: Bool = true)
    {
        self.name = name
        self.expiry = expiry
        self.countLimit = countLimit
        self.autoTrimInterval = autoTrimInterval
        self.shouldRemoveAllObjectsOnMemoryWarning = shouldRemoveAllObjectsOnMemoryWarning
        self.shouldRemoveAllObjectsWhenEnteringBackground = shouldRemoveAllObjectsWhenEnteringBackground
        self.isReleaseOnMainThread = isReleaseOnMainThread
        self.isReleaseAsynchronously = isReleaseAsynchronously
        self.totalCostLimit = totalCostLimit
    }
}
