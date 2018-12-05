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


/// 将Dictionary封装为线程安全的Dictionary
public struct LGThreadSafeDictionary<Key, Value>: Sequence where Key : Hashable {
    
    /// 原始Dictionary容器
    private var container: Dictionary<Key, Value> = Dictionary<Key, Value>()
    
    /// 线程锁
    private var lock: NSLock = NSLock()
    
    /// 元素类型定义
    public typealias Element = (key: Key, value: Value)
    
    public init() {
    }
    
    public subscript(key: Key) -> Value? {
        get {
            lock.lock()
            defer {
                lock.unlock()
            }
            return self.container[key]
        } set {
            lock.lock()
            defer {
                lock.unlock()
            }
            self.container[key] = newValue
        }
    }
    
    public var count: Int {
        lock.lock()
        defer {
            lock.unlock()
        }
        return self.container.count
    }
    
    public var isEmpty: Bool {
        return self.count == 0
    }
    
    @discardableResult
    public mutating func removeValue(forKey key: Key) -> Value? {
        lock.lock()
        defer {
            lock.unlock()
        }
        return self.container.removeValue(forKey: key)
    }
    
    public mutating func removeAll(keepingCapacity keepCapacity: Bool = false) {
        lock.lock()
        defer {
            lock.unlock()
        }
        self.container.removeAll(keepingCapacity: keepCapacity)
    }
    
    
    public var keys: Dictionary<Key, Value>.Keys {
        lock.lock()
        defer {
            lock.unlock()
        }
        return self.container.keys
    }
    
    
    public var values: Dictionary<Key, Value>.Values {
        lock.lock()
        defer {
            lock.unlock()
        }
        return self.container.values
    }
    
    public func makeIterator() -> DictionaryIterator<Key, Value> {
        lock.lock()
        defer {
            lock.unlock()
        }
        return self.container.makeIterator()
    }
}

/// 标识请求回调的Token类型定义，用于取消回调，但不取消下载
public typealias LGWebImageCallbackToken = String

/// 同意下载图片的Manager
public class LGWebImageManager {
    private lazy var workQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 10
        queue.isSuspended = false
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
                                  completion: LGWebImageCompletionBlock? = nil) -> LGWebImageCallbackToken
    {
        let operation = LGWebImageWorkOperation(withURL: url,
                                                options: options,
                                                imageCache: self.cache,
                                                progress: progress,
                                                completion: completion)
        let token = UUID().uuidString + "\(CACurrentMediaTime())"
        operation.name = token
        workQueue.addOperation(operation)
        return token
    }
    
    /// 通过token取消回调，但不会取消下载
    ///
    /// - Parameter callbackToken: 某次请求对应的token
    public func cancelWith(callbackToken: LGWebImageCallbackToken) {
        for operation in self.workQueue.operations {
            if operation.isExecuting {
                operation.cancel()
            }
        }
    }
    
    /// 清理所有缓存，包含内存缓存，磁盘缓存，断点续传临时文件等
    ///
    /// - Parameter block: 清理完成后的回调
    
    public func clearAllCache(withBolck block: (() -> Void)?) {
        var clearCacheMark: Int = 0 {
            didSet {
                if clearCacheMark == 2 {
                    block?()
                }
            }
        }
        
        LGImageCache.default.clearAllCache {
            clearCacheMark += 1
        }
        DispatchQueue.background.async { [unowned self] in
//            let dir = NSTemporaryDirectory() + self.tempDirSuffix
//            do {
//                try FileManager.default.removeItem(at: URL(fileURLWithPath: dir))
//                self.createTempFileDirIfNeeded()
//                clearCacheMark += 1
//            } catch {
//                clearCacheMark += 1
//            }
        }
    }

}

fileprivate var currentActiveRequestCount: Int = 0 {
    didSet {
        UIApplication.shared.isNetworkActivityIndicatorVisible = currentActiveRequestCount > 0
    }
}

fileprivate func networkIndicatorStart() {
    if Thread.current.isMainThread {
        currentActiveRequestCount += 1
    } else {
        DispatchQueue.main.async {
            currentActiveRequestCount += 1
        }
    }
}

fileprivate func networkIndicatorStop() {
    func reduceCurrentActiveRequestCount() {
        currentActiveRequestCount -= 1
        if currentActiveRequestCount < 0 {
            currentActiveRequestCount = 0
        }
    }
    if Thread.current.isMainThread {
        reduceCurrentActiveRequestCount()
    } else {
        DispatchQueue.main.async {
            reduceCurrentActiveRequestCount()
        }
    }
}



// MARK: - LGHTTPRequest Hashable
extension LGHTTPRequest: Hashable {
    public static func == (lhs: LGHTTPRequest, rhs: LGHTTPRequest) -> Bool {
        return lhs === rhs
    }
    
    public var hashValue: Int {
        return self.delegate.hashValue
    }
}

// MARK: -  在有设置的情况下将下载失败的URL加入黑名单进行忽略操作
fileprivate class LGURLBlackList {
    var blackListContainer: Set<URL>
    var blackListContainerLock: DispatchSemaphore
    init() {
        blackListContainer = Set<URL>()
        blackListContainerLock = DispatchSemaphore(value: 1)
    }
    
    static let `default`: LGURLBlackList = {
        return LGURLBlackList()
    }()
    
    func isContains(url: LGURLConvertible) -> Bool {
        do {
            let tempUrl = try url.asURL()
            _ = blackListContainerLock.wait(timeout: DispatchTime.distantFuture)
            let contains = self.blackListContainer.contains(tempUrl)
            _ = blackListContainerLock.signal()
            return contains
        } catch {
            return false
        }
    }
    
    func addURL(_ url: LGURLConvertible) {
        do {
            let tempUrl = try url.asURL()
            _ = blackListContainerLock.wait(timeout: DispatchTime.distantFuture)
            self.blackListContainer.insert(tempUrl)
            _ = blackListContainerLock.signal()
        } catch {
            // do nothing
        }
    }
}

fileprivate extension UIDevice {
    static let physicalMemory: UInt64 = {
        return ProcessInfo().physicalMemory
    }()
}


// MARK: -  下载过程中出现的错误枚举

/// 下载过程中出现的错误枚举
///
/// - cannotReadFile: 无法读取目标文件
/// - targetURLOrOriginURLInvalid: 目标文件地址无效
/// - urlIsInTheBlackList: 下载地址在黑名单中，无法重试
fileprivate enum LGImageDownloadError: Error {
    case cannotReadFile
    case targetURLOrOriginURLInvalid(targetURL: URL?, originURL: URL?)
    case urlIsInTheBlackList(url: LGURLConvertible)
}

fileprivate struct LGWebImageProgressiveContainer {
    var progressiveDecoder: LGImageDecoder?
    var progressiveIgnored: Bool = false
    var lastProgressiveDecodeTimestamp: TimeInterval = CACurrentMediaTime()
    var progressiveDetected = false
    var progressiveScanedLength: Int = 0
    var progressiveDisplayCount: Int = 0
    
    init() {
    }
}
