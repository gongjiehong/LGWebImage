//
//  LGDiskCache.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2017/9/7.
//  Copyright © 2017年 龚杰洪. All rights reserved.
//

import Foundation



public class LGDiskCache {
    
    fileprivate var _storage: LGDataStorage?
    fileprivate var _lock: DispatchSemaphore
    fileprivate var _queue: DispatchQueue

    /// 缓存的名字
    public var name: String?
    
    /// 默认在Cache/LGDiskCache路径下
    public private(set) var path: String

    /// 默认10240(10KB)，默认10KB以上的内容会存到磁盘path路径下
    public private(set) var inlineThreshold: Int
    
    /// 缓存中最多保存多少个对象
    public var countLimit: Int = Int.max
    
    /// 队列开始赶出最后的对象时最大容纳数
    public var costLimit: Int = Int.max
    
    /// 缓存对象的过期时间, 默认30天 60S * 60S * 24H * 30D = 2592000S
    public var ageLimit: Int = 2_592_000
    
    /// 需要多少空余磁盘，无限制，不过在磁盘没有剩余空间时队列中中后面的任务会被放弃
    public var freeDiskSpaceLimit: Int = 0
    
    /// 多长时间检查一次自动修整，默认60秒
    public var autoTrimInterval: TimeInterval = 60
    
    public var customFileNameBlock: ((String) -> String)?
    
    public init() {
        self.path = FileManager.lg_cacheDirectoryPath + "/LGDiskCache"
        self.inlineThreshold = 10_240
        
        _storage = LGDataStorage(path: path, type: LGDataStorageType.mixed)
        _lock = DispatchSemaphore(value: 1)
        _queue = DispatchQueue(label: "com.cxylg.cache.disk")
    }
    
    
    /// 通过缓存路径和内存缓存阈值初始化
    ///
    /// - Parameters:
    ///   - path: 缓存路径
    ///   - inlineThreshold: 缓存阈值，默认10KB（10 * 1024）
    public init(path: String, inlineThreshold: Int = 10_240) {
        self.path = path
        self.inlineThreshold = inlineThreshold
        
        var type: LGDataStorageType
        if (inlineThreshold == 0) {
            type = LGDataStorageType.file
        } else if (inlineThreshold == Int.max) {
            type = LGDataStorageType.SQLite
        } else {
            type = LGDataStorageType.mixed
        }
        
        _storage = LGDataStorage(path: path, type: type)
        _lock = DispatchSemaphore(value: 1)
        _queue = DispatchQueue(label: "com.cxylg.cache.disk")
        
        _trimRecursively()
        _LGDiskCacheSetGlobal(cache: self)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(_appWillBeTerminated),
                                               name: UIApplication.willTerminateNotification,
                                               object: nil)
    }
    
    
    /// 通过MapTable实现更人性的单例
    ///
    /// - Parameters:
    ///   - path: 缓存路径
    ///   - inlineThreshold: 文件或SQLite直接存储的选择阈值，默认10KB
    /// - Returns: LGDiskCache
    public class func instanse(with path: String, inlineThreshold: Int = 10_240) -> LGDiskCache {
        if let cache = _LGDiskCacheGetGlobal(path: path) {
            return cache
        }
        else {
            return LGDiskCache(path: path, inlineThreshold: inlineThreshold)
        }
    }

    public func containsObject(forKey key: String) -> Bool {
        _ = _lock.wait(timeout: DispatchTime.distantFuture)
        let contains = _storage?.itemExists(forKey: key)
        _ = _lock.signal()
        return contains ?? false
    }
    
    public func containsObject(forKey key: String, withBlock block: ((_ key: String, _ contains: Bool) -> Void)?) {
        if block != nil {
            _queue.async { [weak self] in
                guard let weakSelf = self else {
                    return
                }
                let contains = weakSelf.containsObject(forKey: key)
                block!(key, contains)
            }
        }
    }
    
    public func object(forKey key: String) -> LGCacheItem? {
        _ = _lock.wait(timeout: DispatchTime.distantFuture)
        let item = _storage?.getItem(forKey: key)
        _ = _lock.signal()
        if item?.data == nil {
            return nil
        }

        return LGCacheItem(data: item!.data, extendedData: item?.extendedData)
    }
    
    public func object(forKey key: String, withBlock block: ((String, LGCacheItem?) -> Void)?) {
        if block == nil {
            return
        }
        _queue.async {[weak self] in
            guard let weakSelf = self else {
                return
            }
           let object = weakSelf.object(forKey: key)
           block!(key, object)
        }
        
    }
    
    public func setObject(withFileURL fileURL: URL, forKey key: String) {
        if key.lg_length == 0 {
            return
        }
        let filename: String = _filename(for: key)
        _ = _lock.wait(timeout: DispatchTime.distantFuture)
        _ = _storage?.saveItem(with: key, fileURL: fileURL, filename: filename, extendedData: nil)
        _ = _lock.signal()
    }
    
    public func setObject(_ object: LGCacheItem?, forKey key: String) {
        if key.lg_length == 0 {
            return
        }
        if object == nil {
            removeObject(forKey: key)
            return
        }
        let extendedData = object?.extendedData
        var value: Data? = object?.data.asData()
        
        if value == nil {
            return
        }
        
        var filename: String? = nil
        if _storage?.type != LGDataStorageType.SQLite {
            if value!.count > inlineThreshold {
                filename = _filename(for: key)
            }
        }
        _ = _lock.wait(timeout: DispatchTime.distantFuture)
        _ = _storage?.saveItem(with: key, value: value!, filename: filename, extendedData: extendedData?.asData())
        _ = _lock.signal()
    }

    public func setObject(_ object: LGCacheItem?, forKey key: String, withBlock block: (() -> Void)?) {
        _queue.async { [weak self] in
            guard let weakSelf = self else {
                return
            }
            weakSelf.setObject(object, forKey: key)
            if block != nil {
                block!()
            }
        }
    }
    
    public func removeObject(forKey key: String) {
        if key.lg_length == 0 {
            return
        }
        _ = _lock.wait(timeout: DispatchTime.distantFuture)
        _ = _storage?.removeItem(forKey: key)
        _ = _lock.signal()
    }

    public func removeObject(forKey key: String, withBlock block: ((String) -> Void)?) {
        _queue.async { [weak self] in
            guard let weakSelf = self else {
                return
            }
            weakSelf.removeObject(forKey: key)
            if block != nil {
                block!(key)
            }
        }
    }
    
    public func removeAllObjects() {
        _ = _lock.wait(timeout: DispatchTime.distantFuture)
        _ = _storage?.removeAllItems()
        _ = _lock.signal()
    }
    
    public func removeAllObjects(withBlock block: (() -> Void)?) {
        _queue.async { [weak self] in
            guard let weakSelf = self else {
                return
            }
            weakSelf.removeAllObjects()
            if block != nil {
                block!()
            }
        }
    }
    
    public func removeAllObjects(withProgressBlock progressBlock: ((_ removedCount: Int, _ totalCount: Int) -> Void)?,
                                 endBlock: ((_ error: Bool) -> Void)?) {
        _queue.async {[weak self] in
            guard let weakSelf = self else {
                if (endBlock != nil) {
                    endBlock!(true)
                }
                return
            }
            _ = weakSelf._lock.wait(timeout: DispatchTime.distantFuture)
            _ = weakSelf._storage?.removeAllItems(with: progressBlock, endBlock: endBlock)
            _ = weakSelf._lock.signal()
        }
    }
    
    public var totalCount: Int {
        _ = _lock.wait(timeout: DispatchTime.distantFuture)
        let count = _storage!.getItemsCount()
        _ = _lock.signal()
        return count
    }
    
    public func totalCount(withBlock block: @escaping ((_ totalCount: Int) -> Void)) {
        _queue.async { [weak self] in
            guard let weakSelf = self else {
                return
            }
            let totalCount = weakSelf.totalCount
            block(totalCount)
        }
    }
    
    public var totalCost: Int {
        _ = _lock.wait(timeout: DispatchTime.distantFuture)
        let count = _storage!.getItemsSize()
        _ = _lock.signal()
        return count
    }
    
    public func totalCost(withBlock block: @escaping ((_ totalCost: Int) -> Void)) {
        _queue.async { [weak self] in
            guard let weakSelf = self else {
                return
            }
            let totalCost = weakSelf.totalCost
            block(totalCost)
        }
    }
    
    public func trimToCount(_ count: Int) {
        _ = _lock.wait(timeout: DispatchTime.distantFuture)
        _trimToCount(countLimit: count)
        _ = _lock.signal()
    }
    
    public func trimToCount(_ count: Int, withBlock block: @escaping (() -> Void)) {
        _queue.async { [weak self] in
            guard let weakSelf = self else {
                return
            }
            weakSelf.trimToCount(count)
            block()
        }
    }
    
    public func trimToCost(_ cost: Int) {
        _ = _lock.wait(timeout: DispatchTime.distantFuture)
        _trimToCost(costLimit: cost)
        _ = _lock.signal()
    }
    
    public func trimToCost(_ cost: Int, withBlock block: @escaping (() -> Void)) {
        _queue.async { [weak self] in
            guard let weakSelf = self else {
                return
            }
            weakSelf.trimToCost(cost)
            block()
        }
    }
    
    public func trimToAge(_ age: Int) {
        _ = _lock.wait(timeout: DispatchTime.distantFuture)
        _trimToAge(ageLimit: age)
        _ = _lock.signal()
    }
    
    public func trimToAge(_ age: Int, withBlock block: @escaping (() -> Void)) {
        _queue.async { [weak self] in
            guard let weakSelf = self else {
                return
            }
            weakSelf.trimToAge(age)
            block()
        }
    }
    
    public func filePathForDiskStorage(withKey key: String) -> URL {
        guard let pathURL = self._storage?.filePathURL(withFileName: _filename(for: key)) else {
            assert(false, "缓存对象异常")
            return URL(fileURLWithPath: "")
        }
        return pathURL
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

fileprivate var lg_diskSpaceFree: Int64 {
    do {
        let attrs = try FileManager.default.attributesOfItem(atPath: NSHomeDirectory())
        let space = attrs[FileAttributeKey.systemFreeSize]
        if let spaceValue = space as? Int64 {
            return spaceValue
        }
        return -1
    } catch {
        return -1
    }
}

fileprivate let _globalInstances = NSMapTable<NSString, LGDiskCache>(keyOptions: .strongMemory,
                                                                     valueOptions: .weakMemory,
                                                                     capacity: 0)
fileprivate let _globalInstancesLock = DispatchSemaphore(value: 1)

fileprivate func _LGDiskCacheGetGlobal(path: String) -> LGDiskCache? {
    if path.lg_length == 0 {
        return nil
    }
    _ = _globalInstancesLock.wait(timeout: DispatchTime.distantFuture)
    let cache = _globalInstances.object(forKey: NSString(string: path))
    _ = _globalInstancesLock.signal()
    return cache
}

fileprivate func _LGDiskCacheSetGlobal(cache: LGDiskCache) {
    if cache.path.lg_length == 0 {
        return
    }
    _ = _globalInstancesLock.wait(timeout: DispatchTime.distantFuture)
    _globalInstances.setObject(cache, forKey: NSString(string: cache.path))
    _ = _globalInstancesLock.signal()
}

extension LGDiskCache {
    
    fileprivate func _trimRecursively() {
        let deadLine = DispatchTime.now() + DispatchTimeInterval.seconds(Int(autoTrimInterval))
        DispatchQueue.main.asyncAfter(deadline: deadLine) { [weak self] in
            DispatchQueue.global(qos: DispatchQoS.QoSClass.utility).sync { [weak self] in
                guard let weakSelf = self else {
                    return
                }
                weakSelf._trimInBackground()
                weakSelf._trimRecursively()
            }
        }
    }
    
    fileprivate func _trimInBackground() {
        _queue.async { [weak self] in
            guard let weakSelf = self else {
                return
            }
            _ = weakSelf._lock.wait(timeout: DispatchTime.distantFuture)
            weakSelf._trimToCost(costLimit: weakSelf.costLimit)
            weakSelf._trimToCount(countLimit: weakSelf.countLimit)
            weakSelf._trimToAge(ageLimit: weakSelf.ageLimit)
            weakSelf._trimToFreeDiskSpace(targetFreeDiskSpace: weakSelf.freeDiskSpaceLimit)
            _ = weakSelf._lock.signal()
        }
    }
    
    fileprivate func _trimToCost(costLimit: Int) {
        if costLimit >= Int.max {
            return
        }
        _ = _storage?.removeItems(toFitSize: costLimit)
    }
    
    fileprivate func _trimToCount(countLimit: Int) {
        if countLimit >= Int.max {
            return
        }
        _ = _storage?.removeItems(toFitCount: countLimit)
    }
    
    fileprivate func _trimToAge(ageLimit: Int) {
        if ageLimit <= 0 {
            _storage?.removeAllItems()
            return
        }
        let timeStamp = time(nil)
        if timeStamp < ageLimit {
            return
        }
        let age = timeStamp - ageLimit
        _ = _storage?.removeItems(earlierThanTime: age)
    }

    /// 自动释放磁盘空间。
    ///
    /// - Parameter targetFreeDiskSpace: 释放的空间大小
    fileprivate func _trimToFreeDiskSpace(targetFreeDiskSpace: Int) {
        if targetFreeDiskSpace == 0 {
            return
        }
        guard let storage = _storage else {
            return
        }
        let totalBytes = storage.getItemsSize()
        if totalBytes <= 0 {
            return
        }
        
        let diskFreeBytes = lg_diskSpaceFree
        if diskFreeBytes < 0 {
            return
        }
        
        let needTrimBytes = Int64(targetFreeDiskSpace) - diskFreeBytes
        if needTrimBytes <= 0 {
            return
        }
        
        var costLimit = Int64(totalBytes) - needTrimBytes
        if costLimit < 0 {
            costLimit = 0
        }
        // On 32-bit platforms, not safe
        _trimToCost(costLimit: Int(costLimit))
    }

    fileprivate func _filename(for key: String) -> String {
        var filename: String? = nil
        if customFileNameBlock != nil {
            filename = customFileNameBlock!(key)
        }
        if filename == nil {
            filename = key.md5Hash()
        }
        return filename ?? ""
    }
    
    @objc fileprivate func _appWillBeTerminated() {
        _ = self._lock.wait(timeout: DispatchTime.distantFuture)
        self._storage = nil
        _ = self._lock.signal()
    }
}

