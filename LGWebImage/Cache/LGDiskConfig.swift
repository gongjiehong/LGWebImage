//
//  LGDiskConfig.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2019/3/6.
//  Copyright © 2019年 龚杰洪. All rights reserved.
//

import Foundation

/// 存储磁盘缓存相关配置, 并在初始时如果文件夹不存在，则创建对应的文件夹用于写入
public struct LGDiskConfig {
    /// 缓存名字，仅用于标识当前缓存是哪一个
    public let name: String
    
    /// 过期时间，默认最多存储30天，30天 * 24小时 * 60分 * 60秒
    public let expiry: LGExpiry
    
    /// 占用最大的磁盘空间，单位KB，默认1GB, 1_024 * 1_024 * 1_024
    public let maxSize: UInt64
    
    /// 数据直接写入磁盘还是写入数据库分隔值，默认10_240(10KB)，默认10KB以上的内容会存到磁盘path路径下
    public let inlineThreshold: UInt64
    
    /// 需要多少空余磁盘，无限制，不过在磁盘没有剩余空间时队列中中后面的任务会被放弃
    public let freeDiskSpaceLimit: UInt64
    
    /// 多长时间检查一次自动修整，默认60秒
    public let autoTrimInterval: TimeInterval
    
    /// 文件存储的文件夹，默认 .../Caches/LGDiskCache/
    public let directory: URL
    
    /// 初始化
    ///
    /// - Parameters:
    ///   - name: 缓存名字，仅用于标识当前缓存是哪一个
    ///   - expiry: 过期时间，默认最多存储30天，30天 * 24小时 * 60分 * 60秒
    ///   - maxSize: 最大占用到少磁盘空间
    ///   - inlineThreshold: 数据直接写入磁盘还是写入数据库分隔值，默认10_240(10KB)，默认10KB以上的内容会存到磁盘path路径下
    ///   - freeDiskSpaceLimit: 需要多少空余磁盘，无限制，不过在磁盘没有剩余空间时队列中中后面的任务会被放弃
    ///   - autoTrimInterval: 多长时间检查一次自动修整，默认60秒
    public init(name: String,
                expiry: LGExpiry = .ageLimit(2_592_000),
                maxSize: UInt64 = 1_024 * 1_024 * 1_024,
                inlineThreshold: UInt64 = 10_240,
                freeDiskSpaceLimit: UInt64 = UInt64.max,
                autoTrimInterval: TimeInterval = 60.0,
                directory: URL? = nil)
    {
        self.name = name
        self.expiry = expiry
        self.maxSize = maxSize
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

