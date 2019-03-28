//
//  LGDiskCache.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2017/9/7.
//  Copyright © 2017年 龚杰洪. All rights reserved.
//

import Foundation

fileprivate class LGDiskCacheContainer {
    let container: LGWeakValueDictionary<URL, AnyObject>
    let lock: NSLock
    
    init() {
        container = LGWeakValueDictionary<URL, AnyObject>()
        lock = NSLock()
    }
    
    static let `default`: LGDiskCacheContainer = {
       return LGDiskCacheContainer()
    }()
    
    func setCache(_ cache: AnyObject, forKey key: URL) {
        lock.lock()
        defer {
            lock.unlock()
        }
        self.container.setValue(cache, forKey: key)
        
    }
    
    func getCache(forKey key: URL) -> AnyObject? {
        lock.lock()
        defer {
            lock.unlock()
        }
        return self.container.value(forKey: key)
    }
}

public class LGDiskCache<KeyType: Hashable, ValueType: LGCacheItem> {
    
    fileprivate var _storage: LGDataStorage!
    fileprivate var _lock: DispatchSemaphore
    fileprivate var _queue: DispatchQueue
    
    @inline(__always) func keyTypeToString(_ hashable: KeyType) -> String {
        if hashable is String {
            return hashable as! String
        } else {
            return "\(hashable.hashValue)"
        }
    }
    
    /// 磁盘缓存配置
    public let config: LGDiskConfig

    public var customFileNameBlock: ((String) -> String)?
    
    public static func cache(withConfig config: LGDiskConfig) -> LGDiskCache<KeyType, ValueType> {
        if let cache = LGDiskCacheContainer.default.getCache(forKey: config.directory) {
            return cache as! LGDiskCache<KeyType, ValueType>
        } else {
            return LGDiskCache<KeyType, ValueType>(config)
        }
    }
    
    /// 通过配置初始化
    ///
    /// - Parameter config: LGDiskConfig
    public init(_ config: LGDiskConfig = LGDiskConfig(name: "LGDiskCache")) {
        self.config = config
        var type: LGDataStorage.StorageType
        switch config.inlineThreshold {
        case .zero:
            type = .file
            break
        case .unlimited:
            type = .SQLite
            break
        case .byte(_):
            type = .mixed
            break
        }
    
        do {
            _storage = try LGDataStorage(path: config.directory.path, type: type)
        } catch {
            println(error)
        }
        
        _lock = DispatchSemaphore(value: 1)
        _queue = DispatchQueue(label: "com.cxylg.cache.disk")
        
        _trimRecursively()
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(_appWillBeTerminated),
                                               name: UIApplication.willTerminateNotification,
                                               object: nil)
        
        LGDiskCacheContainer.default.setCache(self, forKey: config.directory)
    }

    public func containsObject(forKey key: KeyType) -> Bool {
        _ = _lock.wait(timeout: DispatchTime.distantFuture)
        let contains = _storage.itemExists(forKey: self.keyTypeToString(key))
        _ = _lock.signal()
        return contains
    }
    
    public func containsObject(forKey key: KeyType, withBlock block: ((_ key: KeyType, _ contains: Bool) -> Void)?) {
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
    
    public func object(forKey key: KeyType) -> ValueType? {
        _ = _lock.wait(timeout: DispatchTime.distantFuture)
        let item = _storage.getItem(forKey: self.keyTypeToString(key))
        _ = _lock.signal()
        if item?.data == nil {
            return nil
        }

        return ValueType(data: item!.data, extendedData: item?.extendedData)
    }
    
    public func object(forKey key: KeyType, withBlock block: ((KeyType, ValueType?) -> Void)?) {
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
    
    public func setObject(withFileURL fileURL: URL, forKey key: KeyType) {
        let key = self.keyTypeToString(key)
        if key.lg_length == 0 {
            return
        }
        let filename: String = _filename(for: key)
        _ = _lock.wait(timeout: DispatchTime.distantFuture)
        _ = _storage.saveItem(with: key, fileURL: fileURL, filename: filename, extendedData: nil)
        _ = _lock.signal()
    }
    
    public func setObject(_ object: ValueType?, forKey key: KeyType) {
        let originalKey = key
        let key = self.keyTypeToString(key)
        
        if key.lg_length == 0 {
            return
        }
        if object == nil {
            removeObject(forKey: originalKey)
            return
        }
        let extendedData = object?.extendedData
        var value: Data? = object?.data.asData()
        
        if value == nil {
            return
        }
        
        var filename: String? = nil
        if _storage.type != LGDataStorage.StorageType.SQLite {
            switch config.inlineThreshold {
            case .unlimited:
                break
            case let .byte(cost):
                if value!.count > cost {
                    filename = _filename(for: key)
                }
                break
            case .zero:
                filename = _filename(for: key)
                break
            }
        }
        
        _ = _lock.wait(timeout: DispatchTime.distantFuture)
        _ = _storage.saveItem(with: key, value: value!, filename: filename, extendedData: extendedData?.asData())
        _ = _lock.signal()
    }

    public func setObject(_ object: ValueType?, forKey key: KeyType, withBlock block: (() -> Void)?) {
        _queue.async { [weak self] in
            guard let weakSelf = self else {
                return
            }
            weakSelf.setObject(object, forKey: key)
            if let block = block {
                block()
            }
        }
    }
    
    public func removeObject(forKey key: KeyType) {
        let key = keyTypeToString(key)
        if key.lg_length == 0 {
            return
        }
        _ = _lock.wait(timeout: DispatchTime.distantFuture)
        _ = _storage.removeItem(forKey: key)
        _ = _lock.signal()
    }

    public func removeObject(forKey key: KeyType, withBlock block: ((KeyType) -> Void)?) {
        _queue.async { [weak self] in
            guard let weakSelf = self else {
                return
            }
            weakSelf.removeObject(forKey: key)
            if let block = block {
                block(key)
            }
        }
    }
    
    public func removeAllObjects() {
        _ = _lock.wait(timeout: DispatchTime.distantFuture)
        _ = _storage.removeAllItems()
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
            _ = weakSelf._storage.removeAllItems(with: progressBlock, endBlock: endBlock)
            _ = weakSelf._lock.signal()
        }
    }
    
    public var totalCount: Int {
        _ = _lock.wait(timeout: DispatchTime.distantFuture)
        let count = _storage.getItemsCount()
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
        let count = _storage.getItemsSize()
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
    
    public func trimToCount(_ count: UInt64) {
        _ = _lock.wait(timeout: DispatchTime.distantFuture)
        _trimToCount(countLimit: count)
        _ = _lock.signal()
    }
    
    public func trimToCount(_ count: UInt64, withBlock block: @escaping (() -> Void)) {
        _queue.async { [weak self] in
            guard let weakSelf = self else {
                return
            }
            weakSelf.trimToCount(count)
            block()
        }
    }
    
    public func trimToCost(_ cost: UInt64) {
        _ = _lock.wait(timeout: DispatchTime.distantFuture)
        _trimToCost(costLimit: cost)
        _ = _lock.signal()
    }
    
    public func trimToCost(_ cost: UInt64, withBlock block: @escaping (() -> Void)) {
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
    
    public func filePathForDiskStorage(withKey key: KeyType) -> URL {
        let key = keyTypeToString(key)
        let pathURL = self._storage.filePathURL(withFileName: _filename(for: key))
        return pathURL
    }
    
    /// App将要被终止的时候关闭数据库连接，防止数据库损坏导致数据丢失
    @objc fileprivate func _appWillBeTerminated() {
        _ = self._lock.wait(timeout: DispatchTime.distantFuture)
        _storage = nil
        _ = self._lock.signal()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        _storage = nil
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

extension LGDiskCache {
    fileprivate func _trimRecursively() {
        _queue.after(config.autoTrimInterval) { [weak self] in
            guard let weakSelf = self else {
                return
            }
            weakSelf._trimInBackground()
            weakSelf._trimRecursively()
        }
    }
    
    fileprivate func _trimInBackground() {
        _queue.async { [weak self] in
            guard let weakSelf = self else {
                return
            }
            _ = weakSelf._lock.wait(timeout: DispatchTime.distantFuture)
            
            switch weakSelf.config.totalCostLimit {
            case .unlimited, .zero:
                break
            case let .byte(cost):
                weakSelf._trimToCost(costLimit: cost)
                break
            }
            
            if weakSelf.config.countLimit != .unlimited {
                weakSelf._trimToCount(countLimit: weakSelf.config.countLimit)
            }
            
            switch weakSelf.config.expiry {
            case .never:
                break
            case let .ageLimit(ageLimit):
                weakSelf._trimToAge(ageLimit: Int(ageLimit))
                break
            }
            
            switch weakSelf.config.freeDiskSpaceLimit {
            case .unlimited:
                break
            case .zero:
                weakSelf._trimToFreeDiskSpace(0)
                break
            case let .byte(freeDiskSpaceLimit):
                weakSelf._trimToFreeDiskSpace(freeDiskSpaceLimit)
                break
            }
            _ = weakSelf._lock.signal()
        }
    }
    
    fileprivate func _trimToCost(costLimit: UInt64) {
        if costLimit >= Int.max {
            return
        }
        _ = _storage.removeItems(toFitSize: Int(costLimit))
    }
    
    fileprivate func _trimToCount(countLimit: UInt64) {
        if countLimit >= Int.max {
            return
        }
        _ = _storage.removeItems(toFitCount: Int(countLimit))
    }
    
    fileprivate func _trimToAge(ageLimit: Int) {
        if ageLimit <= 0 {
            _storage.removeAllItems()
            return
        }
        let timeStamp = time(nil)
        if timeStamp < ageLimit {
            return
        }
        let age = timeStamp - ageLimit
        _ = _storage.removeItems(earlierThanTime: age)
    }

    /// 自动释放磁盘空间。
    ///
    /// - Parameter targetFreeDiskSpace: 释放的空间大小
    fileprivate func _trimToFreeDiskSpace(_ targetFreeDiskSpace: UInt64) {
        if targetFreeDiskSpace == 0 {
            return
        }

        let totalBytes = _storage.getItemsSize()
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
        _trimToCost(costLimit: UInt64(costLimit))
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
}

