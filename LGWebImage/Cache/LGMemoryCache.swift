//
//  LGMemoryCache.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2017/9/15.
//  Copyright © 2017年 龚杰洪. All rights reserved.
//

import Foundation

@inline(__always) fileprivate func LGMemoryCacheGetReleaseQueue() -> DispatchQueue {
    return DispatchQueue.global(qos: DispatchQoS.QoSClass.utility)
}

public class LGMemoryCache {
    
    fileprivate var _lock: pthread_mutex_t = pthread_mutex_t()
    fileprivate var _lru: LGLinkedMap = LGLinkedMap()
    fileprivate var _queue: DispatchQueue = DispatchQueue(label: "com.cxylg.cache.memory")
    
    /// 缓存的名字
    public var name: String? = nil
    
    /// 缓存中最多保存多少个对象
    public var countLimit: Int = Int.max
    
    /// 队列开始赶出最后的对象时最大容纳数
    public var costLimit: Int = Int.max
    
    /// 缓存对象的过期时间
    public var ageLimit: TimeInterval = Double.greatestFiniteMagnitude
    
    /// 多长时间检查一次自动修整，默认60秒
    public var autoTrimInterval: TimeInterval = 5
    
    public var shouldRemoveAllObjectsOnMemoryWarning: Bool = true
    
    public var shouldRemoveAllObjectsWhenEnteringBackground: Bool = true
    
    public var didReceiveMemoryWarningBlock: ((_ cache: LGMemoryCache) -> Void)?
    
    public var didEnterBackgroundBlock: ((_ cache: LGMemoryCache) -> Void)?
    
    public var releaseOnMainThread: Bool {
        set {
            pthread_mutex_lock(&_lock)
            _lru.releaseOnMainThread = newValue
            pthread_mutex_unlock(&_lock)
        }
        get {
            pthread_mutex_lock(&_lock)
            let value = _lru.releaseOnMainThread
            pthread_mutex_unlock(&_lock)
            return value
        }
    }
    
    public var releaseAsynchronously: Bool {
        set {
            pthread_mutex_lock(&_lock)
            _lru.releaseAsynchronously = newValue
            pthread_mutex_unlock(&_lock)
        }
        get {
            pthread_mutex_lock(&_lock)
            let value = _lru.releaseAsynchronously
            pthread_mutex_unlock(&_lock)
            return value
        }
    }
    
    public var totalCount: Int {
        pthread_mutex_lock(&_lock)
        let count = _lru.totalCount
        pthread_mutex_unlock(&_lock)
        return count
    }

    public var totalCost: Int {
        pthread_mutex_lock(&_lock)
        let cost = _lru.totalCost
        pthread_mutex_unlock(&_lock)
        return cost
    }
    
    public init() {
        _ = pthread_mutex_init(&_lock, nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(_appDidEnterBackgroundNotification(_:)),
                                               name: NSNotification.Name.UIApplicationDidEnterBackground,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(_appDidReceiveMemoryWarningNotification(_:)),
                                               name: NSNotification.Name.UIApplicationDidReceiveMemoryWarning,
                                               object: nil)
        _trimRecursively()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        pthread_mutex_destroy(&_lock)
        _lru.removeAll()
    }
    
    public func containsObject(forKey key: String) -> Bool  {
        pthread_mutex_lock(&_lock)
        let contains = (_lru.dic[key] != nil)
        pthread_mutex_unlock(&_lock)
        return contains
    }
    
    public func object(forKey key: String) -> LGCacheItem? {
        pthread_mutex_lock(&_lock)
        let node = _lru.dic[key]
        if node != nil {
            node?.time = CACurrentMediaTime()
            _lru.bringNode(toHead: node)
        }
        pthread_mutex_unlock(&_lock)
        return node?.value ?? nil
    }
    
    public func setObject(_ object: LGCacheItem?, forKey key: String, withCost cost: Int) {
        if key.lg_length == 0 {
            return
        }
        
        guard let toSaveObj = object else {
            removeObject(forKey: key)
            return
        }
        
        pthread_mutex_lock(&_lock)
        var node = _lru.dic[key]
        let now: TimeInterval = CACurrentMediaTime()
        if node != nil {
            _lru.totalCost -= node!.cost
            _lru.totalCost += cost
            node?.cost = cost
            node?.time = now
            node?.value = toSaveObj
            _lru.bringNode(toHead: node)
        } else {
            node = LGLinkedMapNode(key: key, value: toSaveObj, cost: cost, time: now)
            _lru.bringNode(toHead: node)
        }
        
        if _lru.totalCount > countLimit {
            _queue.async {
                _ = node?.key
            }
        }
        
        if _lru.releaseAsynchronously {
            let tempQueue = _lru.releaseOnMainThread ? DispatchQueue.main : LGMemoryCacheGetReleaseQueue()
            tempQueue.async {
                _ = node?.key
            }
        } else if _lru.releaseOnMainThread && pthread_main_np() == 0 {
            DispatchQueue.main.async {
                _ = node?.key
            }
        }
        pthread_mutex_unlock(&_lock)
    }
    
    public func removeObject(forKey key: String) {
        if key.lg_length == 0 {
            return
        }
        pthread_mutex_lock(&_lock)
        let node = _lru.dic[key]
        if node != nil {
            _lru.removeNode(node: node!)
        }
        if _lru.releaseAsynchronously {
            let tempQueue = _lru.releaseOnMainThread ? DispatchQueue.main : LGMemoryCacheGetReleaseQueue()
            tempQueue.async {
                _ = node?.key
            }
        } else if _lru.releaseOnMainThread && pthread_main_np() == 0 {
            DispatchQueue.main.async {
                _ = node?.key
            }
        }
        pthread_mutex_unlock(&_lock)
    }
    
    public func removeAllObjects() {
        pthread_mutex_lock(&_lock)
        _lru.removeAll()
        pthread_mutex_unlock(&_lock)
    }
    
    public func trimToCount(_ count: Int) {
        if count == 0 {
            removeAllObjects()
            return
        }
        _trimToCount(count)
    }

    public func trimToCost(_ cost: Int) {
        _trimToCost(cost)
    }
    
    public func trimToAge(age: TimeInterval) {
        _trimToAge(age)
    }
}

fileprivate extension LGMemoryCache {
    fileprivate func _trimRecursively() {
        let tempQueue = DispatchQueue.global(qos: DispatchQoS.QoSClass.utility)
        tempQueue.asyncAfter(deadline: DispatchTime.now() + autoTrimInterval) { [weak self] in
            guard let weakSelf = self else {
                return
            }
            weakSelf._trimInBackground()
            weakSelf._trimRecursively()
        }
    }
    
    fileprivate func _trimInBackground() {
        _queue.async {
            self._trimToCost(self.costLimit)
            self._trimToCount(self.countLimit)
            self._trimToAge(self.ageLimit)
            
        }
    }
    
    fileprivate func _trimToCost(_ costLimit: Int) {
        var finish = false
        pthread_mutex_lock(&_lock)
        if costLimit == 0 {
            _lru.removeAll()
            finish = true
        } else if _lru.totalCost <= costLimit {
            finish = true
        }
        pthread_mutex_unlock(&_lock)
        
        if finish {
            return
        }
        var holder = [LGLinkedMapNode]()
        while !finish {
            if pthread_mutex_trylock(&_lock) == 0 {
                if _lru.totalCost > costLimit {
                    if let node = _lru.removeTailNode() {
                        holder.append(node)
                    }
                } else {
                    finish = true
                }
                pthread_mutex_unlock(&_lock)
            } else {
                usleep(10 * 1000) // 10 秒钟
            }
        }
        if holder.count > 0 {
            let tempQueue = _lru.releaseOnMainThread ? DispatchQueue.main : LGMemoryCacheGetReleaseQueue()
            tempQueue.async {
                _ = holder.count // 随意调用个方法，方法结束后在当前队列释放
            }
        }
    }
    fileprivate func _trimToCount(_ countLimit: Int) {
        var finish = false
        pthread_mutex_lock(&_lock)
        if countLimit == 0 {
            _lru.removeAll()
            finish = true
        } else if _lru.totalCount <= countLimit {
            finish = true
        }
        pthread_mutex_unlock(&_lock)
        
        if finish {
            return
        }
        var holder = [LGLinkedMapNode]()
        while !finish {
            if pthread_mutex_trylock(&_lock) == 0 {
                if _lru.totalCount > countLimit {
                    if let node = _lru.removeTailNode() {
                        holder.append(node)
                    }
                } else {
                    finish = true
                }
                pthread_mutex_unlock(&_lock)
            } else {
                usleep(10 * 1000) // 10 秒钟
            }
        }
        if holder.count > 0 {
            let tempQueue = _lru.releaseOnMainThread ? DispatchQueue.main : LGMemoryCacheGetReleaseQueue()
            tempQueue.async {
                _ = holder.count // 随意调用个方法，方法结束后在当前队列释放
            }
        }
    }
    
    fileprivate func _trimToAge(_ ageLimit: TimeInterval) {
        var finish = false
        let now: TimeInterval = CACurrentMediaTime()
        pthread_mutex_lock(&_lock)
        if ageLimit <= 0 {
            _lru.removeAll()
            finish = true
        }
        pthread_mutex_unlock(&_lock)
        
        if finish {
            return
        }
        var holder = [LGLinkedMapNode]()
        while !finish {
            if pthread_mutex_trylock(&_lock) == 0 {
                if _lru.tail != nil && (now - TimeInterval((_lru.tail)!.time) > ageLimit) {
                    if let node = _lru.removeTailNode() {
                        holder.append(node)
                    }
                } else {
                    finish = true
                }
                pthread_mutex_unlock(&_lock)
            } else {
                usleep(10 * 1000) // 10 秒钟
            }
        }
        if holder.count > 0 {
            let tempQueue = _lru.releaseOnMainThread ? DispatchQueue.main : LGMemoryCacheGetReleaseQueue()
            tempQueue.async {
                _ = holder.count // 随意调用个方法，方法结束后在当前队列释放
            }
        }
    }
    
    @objc fileprivate func _appDidEnterBackgroundNotification(_ noti: Notification) {
        if didEnterBackgroundBlock != nil {
            didEnterBackgroundBlock!(self)
        }
        if shouldRemoveAllObjectsWhenEnteringBackground {
            self.removeAllObjects()
        }
    }
    
    @objc fileprivate func _appDidReceiveMemoryWarningNotification(_ noti: Notification) {
        if didReceiveMemoryWarningBlock != nil {
            didReceiveMemoryWarningBlock!(self)
        }
        if self.shouldRemoveAllObjectsOnMemoryWarning {
            self.removeAllObjects()
        }
    }
}

fileprivate class LGLinkedMapNode {
    fileprivate var prev: LGLinkedMapNode?
    fileprivate var next: LGLinkedMapNode?
    fileprivate var key: String
    fileprivate var value: LGCacheItem
    fileprivate var cost: Int
    fileprivate var time: TimeInterval
    fileprivate init(key: String, value: LGCacheItem, cost: Int = 0, time: TimeInterval = 0.0) {
        self.key = key
        self.value = value
        self.cost = cost
        self.time = time
    }
    
    deinit {
        println(String(format: "LGLinkedMapNode deinit in %@", Thread.current))
    }
}

fileprivate class LGLinkedMap {
    fileprivate var dic: [String: LGLinkedMapNode] = [String: LGLinkedMapNode]()
    fileprivate var totalCost: Int = 0
    fileprivate var totalCount: Int = 0
    fileprivate var head: LGLinkedMapNode?
    fileprivate var tail: LGLinkedMapNode?
    fileprivate var releaseOnMainThread: Bool = false
    fileprivate var releaseAsynchronously: Bool = true
    
    fileprivate init() {
        
    }
    
    fileprivate func insertNode(atHead node: LGLinkedMapNode) {
        dic[node.key] = node
        totalCost += node.cost
        totalCount += 1
        
        if head != nil {
            node.next = head
            head?.prev = node
            head = node
        }
        else {
            head = node
            tail = node
        }
    }
    
    fileprivate func bringNode(toHead node: LGLinkedMapNode?) {
        if head === node {
            return
        }
        
        if tail === node {
            tail = node?.prev
            tail?.next = nil
        } else {
            node?.next?.prev = node?.prev
            node?.prev?.next = node?.next
        }
        
        node?.next = head
        node?.prev = nil
        
        head?.prev = node
        head = node
        
    }
    
    fileprivate func removeNode(node: LGLinkedMapNode) {
        dic[node.key] = nil
        totalCost -= node.cost
        totalCount -= 1
        if node.next != nil {
            node.next?.prev = node.prev
        }
        
        if node.prev != nil {
            node.prev?.next = node.next
        }
        if head === node {
            head = node.next
        }
        if tail === node {
            tail = node.prev
        }
    }
    
    fileprivate func removeTailNode() -> LGLinkedMapNode? {
        guard let tailItem = tail else {
            return nil
        }
        
        dic[tailItem.key] = nil
        totalCost -= tailItem.cost
        totalCount -= 1
        if head === tail {
            head = nil
            tail = nil
        } else {
            tail = tail?.prev
            tail?.next = nil
        }
        return tailItem
    }
    
    fileprivate func removeAll() {
        totalCost = 0
        totalCount = 0
        head = nil
        tail = nil
        if dic.count > 0 {
            if releaseAsynchronously {
                let queue = releaseOnMainThread ? DispatchQueue.main : LGMemoryCacheGetReleaseQueue()
                queue.async { [weak self] in
                    self?.dic.removeAll()
                }
            } else if releaseOnMainThread && pthread_main_np() == 0 {
                DispatchQueue.main.async { [weak self] in
                    self?.dic.removeAll()
                }
            } else {
                self.dic.removeAll()
            }
        }
    }
}

