//
//  LGCacheConfigs.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2019/3/14.
//  Copyright © 2019年 龚杰洪. All rights reserved.
//

import Foundation

// MARK: - LGExpiry 缓存过期定义
/// 缓存过期定义
///
/// - never: 永不过期
/// - ageLimit: 多少秒后过期
public enum LGExpiry {
    case never
    case ageLimit(TimeInterval)
}

// MARK: - LGSpaceCost 磁盘和内存空间占用量枚举
/// 磁盘和内存空间占用量枚举
///
/// - zero: 没有空间
/// - unlimited: 无限制
/// - byte: 占用多少byte
public enum LGSpaceCost {
    case zero
    case unlimited
    case byte(UInt64)
}

// MARK: - LGDiskConfig 磁盘缓存相关配置
/// 存储磁盘缓存相关配置, 并在初始时如果文件夹不存在，则创建对应的文件夹用于写入
public struct LGDiskConfig {
    /// 缓存名字，仅用于标识当前缓存是哪一个
    public let name: String
    
    /// 过期时间，默认最多存储30天，30天 * 24小时 * 60分 * 60秒
    public let expiry: LGExpiry
    
    /// 占用磁盘空间最大值，单位Byte，默认1GB, 1_024 * 1_024 * 1_024
    public let totalCostLimit: LGSpaceCost
    
    /// 数量上限，默认无限制
    public let countLimit: LGCountLimit
    
    /// 数据直接写入磁盘还是写入数据库分隔值，默认10_240(10KB)，默认10KB以上的内容会存到磁盘path路径下
    public let inlineThreshold: LGSpaceCost
    
    /// 需要多少空余磁盘，无限制，不过在磁盘没有剩余空间时队列中中后面的任务会被放弃
    public let freeDiskSpaceLimit: LGSpaceCost
    
    /// 多长时间检查一次自动修整，默认60秒
    public let autoTrimInterval: TimeInterval
    
    /// 文件存储的文件夹，默认 .../Caches/LGDiskCache/
    public let directory: URL
    
    /// 初始化
    ///
    /// - Parameters:
    ///   - name: 缓存名字，仅用于标识当前缓存是哪一个
    ///   - expiry: 过期时间，默认最多存储30天，30天 * 24小时 * 60分 * 60秒
    ///   - totalCostLimit: 占用磁盘空间最大值, 默认无限制
    ///   - countLimit: 数量上限，默认无限制
    ///   - inlineThreshold: 数据直接写入磁盘还是写入数据库分隔值，默认10_240(10KB)，默认10KB以上的内容会存到磁盘path路径下
    ///   - freeDiskSpaceLimit: 需要多少空余磁盘，无限制，不过在磁盘没有剩余空间时队列中中后面的任务会被放弃
    ///   - autoTrimInterval: 多长时间检查一次自动修整，默认60秒
    ///   - directory: /// 文件存储的文件夹，默认 .../Caches/LGDiskCache/
    public init(name: String,
                expiry: LGExpiry = .ageLimit(2_592_000),
                totalCostLimit: LGSpaceCost = .byte(1_024 * 1_024 * 1_024),
                countLimit: LGCountLimit = .unlimited,
                inlineThreshold: LGSpaceCost = .byte(10_240),
                freeDiskSpaceLimit: LGSpaceCost = .unlimited,
                autoTrimInterval: TimeInterval = 60.0,
                directory: URL? = nil)
    {
        self.name = name
        self.expiry = expiry
        self.totalCostLimit = totalCostLimit
        self.countLimit = countLimit
        self.inlineThreshold = inlineThreshold
        self.freeDiskSpaceLimit = freeDiskSpaceLimit
        self.autoTrimInterval = autoTrimInterval
        if let directory = directory {
            self.directory = directory
            createDirectoryIfNotExists(directory)
        } else {
            let path = FileManager.lg_cacheDirectoryPath + "/LGDiskCache"
            let pathURL = URL(fileURLWithPath: path)
            self.directory = pathURL
            createDirectoryIfNotExists(pathURL)
        }
    }
    
    /// 根据文件URL判断文件夹是否存在，如果不存在，则创建该文件夹
    ///
    /// - Parameter url: 文件夹路径
    internal func createDirectoryIfNotExists(_ url: URL) {
        do {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    // do nothing
                } else {
                    try FileManager.default.removeItem(at: directory)
                    try FileManager.default.createDirectory(at: directory,
                                                            withIntermediateDirectories: true,
                                                            attributes: nil)
                }
            } else {
                try FileManager.default.createDirectory(at: directory,
                                                        withIntermediateDirectories: true,
                                                        attributes: nil)
            }
        } catch {
            println(error)
        }
    }
}

public typealias LGCountLimit = UInt64

extension LGCountLimit {
    public static var unlimited: LGCountLimit {
        return LGCountLimit.max
    }
}

// MARK: - LGMemoryConfig 内存缓存相关配置
/// 存储内存缓存相关配置
public struct LGMemoryConfig {
    /// 缓存名字，仅用于标识当前缓存是哪一个
    public let name: String
    
    /// 过期时间, 默认12（小时） * 60（分） * 60（秒）
    public let expiry: LGExpiry
    
    /// 数量上限，默认无限制
    public let countLimit: LGCountLimit
    
    /// 内存占用上限，默认物理内存的5%作为最大内存缓存空间，超出的将被逐出, 单位Byte
    public let totalCostLimit: LGSpaceCost
    
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
    ///   - countLimit: 数量上限，默认无限制
    ///   - totalCostLimit: 内存占用上限，默认物理内存的不超过5%作为最大内存缓存空间，超出的将被逐出, 单位Byte
    ///   - autoTrimInterval: 自动整理时间间隔，默认5秒
    ///   - shouldRemoveAllObjectsOnMemoryWarning: 是否在接收到内存警告时清空缓存，默认true
    ///   - shouldRemoveAllObjectsWhenEnteringBackground: 是否在程序进入后台是清空缓存，默认true
    ///   - isReleaseOnMainThread: 是否在主线程释放内存，默认false
    ///   - isReleaseAsynchronously: 是否异步释放内存，默认true
    public init(name: String,
                expiry: LGExpiry = .ageLimit(43_200),
                countLimit: LGCountLimit = .unlimited,
                totalCostLimit: LGSpaceCost = .byte(ProcessInfo().physicalMemory / 100 * 5),
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
