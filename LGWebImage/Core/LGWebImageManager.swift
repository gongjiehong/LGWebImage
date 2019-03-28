//
//  LGWebImageManager.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2017/10/16.
//  Copyright © 2017年 龚杰洪. All rights reserved.
//

import Foundation
import LGHTTPRequest
import ImageIO
import MapKit


internal var lg_setImageQueue: DispatchQueue {
    return DispatchQueue.userInteractive
}

/// 标识请求回调的Token类型定义，用于取消回调，但不取消下载
public typealias LGWebImageCallbackToken = String

/// 同意下载图片的Manager
public class LGWebImageManager {
    private lazy var workQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        queue.isSuspended = false
        queue.name = "com.LGWebImageManager.workQueue"
        return queue
    }()
    
    /// 图片缓存工具
    public var cache: LGImageCache
    
    /// 下载URLSession管理器
    fileprivate var sessionManager: LGURLSessionManager
    
    /// 大图的最大字节数，这里设置为1MB，超过1MB不处理渐进显示，在显示的时候根据屏幕大小生成缩略图进行展示
    fileprivate let maxFileSize: UInt64 = 1_024 * 1_024

    
    /// 根据一些选项设置和信任的host进行初始化
    ///
    /// - Parameters:
    ///   - options: 固定设置
    ///   - trustHosts: 信任的host，设置后不会验证SSL有效性
    public init(options: LGWebImageOptions = LGWebImageOptions.default, trustHosts: [String] = []) {
        cache = LGImageCache.default
        
        let sessionConfig = URLSessionConfiguration.default
        if options.contains(LGWebImageOptions.refreshImageCache) {
            sessionConfig.requestCachePolicy = URLRequest.CachePolicy.reloadIgnoringCacheData
        }
        
        var policies: [String : LGServerTrustPolicy] = [String : LGServerTrustPolicy]()
        
        for key in trustHosts {
            policies[key] = LGServerTrustPolicy.disableEvaluation
        }
        
        let sslTrust = LGServerTrustPolicyManager(policies: policies)
        
        sessionManager = LGURLSessionManager(configuration: sessionConfig,
                                              delegate: LGURLSessionDelegate(),
                                              serverTrustPolicyManager: sslTrust)
        
        
        if options.contains(LGWebImageOptions.autoTurnOnFillet) {
            UIImageView.swizzleImplementations()
            UIButton.swizzleImplementations()
            CALayer.swizzleImplementations()
            MKAnnotationView.swizzleImplementations()
        }
    }
    
    /// 默认单例
    public static let `default`: LGWebImageManager = {
        return LGWebImageManager()
    }()
    
    
    public typealias DownloadResult = (callbackToken: LGWebImageCallbackToken, operation: LGWebImageOperation)
    
    /// 下载图片方法，支持断点续传，大图优化
    ///
    /// - Parameters:
    ///   - url: 文件远端地址
    ///   - options: 一些选项
    ///   - progress: 进度回调
    ///   - completion: 完成回调
    /// - Returns: LGWebImageCallbackToken 用于中途取消进度回调和完成回调
    @discardableResult
    public func downloadImageWith(url: LGURLConvertible,
                                  options: LGWebImageOptions = LGWebImageOptions.default,
                                  progress: LGWebImageProgressBlock? = nil,
                                  completion: LGWebImageCompletionBlock? = nil) -> DownloadResult
    {
        let operation = LGWebImageOperation(withURL: url,
                                                options: options,
                                                imageCache: self.cache,
                                                progress: progress,
                                                completion: completion)
        let token = UUID().uuidString + "\(CACurrentMediaTime())"
        operation.name = token
        workQueue.addOperation(operation)
        return (token, operation)
    }
    
    /// 通过token取消回调，但不会取消下载
    ///
    /// - Parameter callbackToken: 某次请求对应的token
    public func cancelWith(callbackToken: LGWebImageCallbackToken) {
        for operation in self.workQueue.operations where operation.name == callbackToken {
            operation.cancel()
        }
    }
    
    /// 清理所有缓存，包含内存缓存，磁盘缓存，断点续传临时文件等
    ///
    /// - Parameter block: 清理完成后的回调
    public func clearAllCache(withBolck block: (() -> Void)?) {
        var clearCacheMark: Int = 0 {
            didSet {
                if clearCacheMark == 1 {
                    block?()
                }
            }
        }
        
        LGImageCache.default.clearAllCache {
            clearCacheMark += 1
        }
    }
}


fileprivate extension UIDevice {
    static var physicalMemory: UInt64 {
        return ProcessInfo().physicalMemory
    }
}
