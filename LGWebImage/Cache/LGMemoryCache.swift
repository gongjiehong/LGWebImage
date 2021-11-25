//
//  LGMemoryCache.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2017/9/15.
//  Copyright © 2017年 龚杰洪. All rights reserved.
//

import Foundation

public class LGMemoryCache<KeyType: Hashable, ValueType: LGMemoryCost> {
    
    fileprivate var _lock: pthread_mutex_t = pthread_mutex_t()
    fileprivate var _lru: LGLinkedList<KeyType, ValueType> = LGLinkedList<KeyType, ValueType>()
    fileprivate var _workQueue: DispatchQueue = DispatchQueue(label: "com.cxylg.cache.memory")
    
    public let config: LGMemoryConfig
    
    public var didReceiveMemoryWarningBlock: ((_ cache: LGMemoryCache) -> Void)?
    
    public var didEnterBackgroundBlock: ((_ cache: LGMemoryCache) -> Void)?
    
    public var releaseOnMainThread: Bool {
        set {
            pthread_mutex_lock(&_lock)
            defer {
                pthread_mutex_unlock(&_lock)
            }
            _lru.isReleaseOnMainThread = newValue
        }
        get {
            pthread_mutex_lock(&_lock)
            defer {
                pthread_mutex_unlock(&_lock)
            }
            let value = _lru.isReleaseOnMainThread
            return value
        }
    }
    
    public var releaseAsynchronously: Bool {
        set {
            pthread_mutex_lock(&_lock)
            defer {
                pthread_mutex_unlock(&_lock)
            }
            _lru.isReleaseAsynchronously = newValue
        }
        get {
            pthread_mutex_lock(&_lock)
            defer {
                pthread_mutex_unlock(&_lock)
            }
            let value = _lru.isReleaseAsynchronously
            return value
        }
    }
    
    public var totalCount: UInt64 {
        pthread_mutex_lock(&_lock)
        defer {
            pthread_mutex_unlock(&_lock)
        }
        let count = _lru.totalCount
        return count
    }

    public var totalCost: UInt64 {
        pthread_mutex_lock(&_lock)
        defer {
            pthread_mutex_unlock(&_lock)
        }
        let cost = _lru.totalCost
        return cost
    }
    
    public init(config: LGMemoryConfig = LGMemoryConfig(name: "LGWebImage.default")) {
        self.config = config

        _ = pthread_mutex_init(&_lock, nil)
        
        _lru.isReleaseOnMainThread = config.isReleaseOnMainThread
        _lru.isReleaseAsynchronously = config.isReleaseAsynchronously
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(_appDidEnterBackgroundNotification(_:)),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(_appDidReceiveMemoryWarningNotification(_:)),
                                               name: UIApplication.didReceiveMemoryWarningNotification,
                                               object: nil)
        _trimRecursively()
        
        
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        pthread_mutex_destroy(&_lock)
        _lru.removeAll()
    }
    
    public func containsObject(forKey key: KeyType) -> Bool  {
        pthread_mutex_lock(&_lock)
        defer {
            pthread_mutex_unlock(&_lock)
        }
        return _lru.containsValue(forKey: key)
    }
    
    public func object(forKey key: KeyType) -> ValueType? {
        pthread_mutex_lock(&_lock)
        let node = _lru[key]
        pthread_mutex_unlock(&_lock)
        return node
    }
    
    public func setObject(_ object: ValueType?, forKey key: KeyType) {
        guard let toSaveObj = object else {
            removeObject(forKey: key)
            return
        }
        
        pthread_mutex_lock(&_lock)
        defer {
            pthread_mutex_unlock(&_lock)
        }
        
        _lru[key] = toSaveObj
        
        switch config.totalCostLimit {
        case .unlimited, .zero:
            break
        case let .byte(cost):
            if _lru.totalCost > cost {
                _workQueue.async {
                    self.trimToCost(cost)
                }
            }
            break
        }
        
        if config.countLimit != LGCountLimit.unlimited, _lru.totalCount > config.countLimit {
            _workQueue.async {
                self.trimToCount(self.config.countLimit)
            }
        }
    }
    
    public func removeObject(forKey key: KeyType) {

        pthread_mutex_lock(&_lock)
        defer {
            pthread_mutex_unlock(&_lock)
        }
        _lru[key] = nil
    }
    
    public func removeAllObjects() {
        pthread_mutex_lock(&_lock)
        defer {
            pthread_mutex_unlock(&_lock)
        }
        _lru.removeAll()
    }
    
    public func trimToCount(_ count: UInt64) {
        if count == 0 {
            removeAllObjects()
            return
        }
        _trimToCount(count)
    }

    public func trimToCost(_ cost: UInt64) {
        _trimToCost(cost)
    }
    
    public func trimToAge(age: TimeInterval) {
        switch self.config.expiry {
        case let .ageLimit(seconds):
            _trimToAge(seconds)
            break
        default:
            break
        }
    }
    
    
    @objc fileprivate func _appDidEnterBackgroundNotification(_ noti: Notification) {
        if didEnterBackgroundBlock != nil {
            didEnterBackgroundBlock!(self)
        }
        if config.shouldRemoveAllObjectsWhenEnteringBackground {
            self.removeAllObjects()
        }
    }
    
    @objc fileprivate func _appDidReceiveMemoryWarningNotification(_ noti: Notification) {
        if didReceiveMemoryWarningBlock != nil {
            didReceiveMemoryWarningBlock!(self)
        }
        if config.shouldRemoveAllObjectsOnMemoryWarning {
            self.removeAllObjects()
        }
    }
}

extension LGMemoryCache {
    fileprivate func _trimRecursively() {
        _workQueue.asyncAfter(deadline: DispatchTime.now() + config.autoTrimInterval) { [weak self] in
            guard let weakSelf = self else {
                return
            }
            weakSelf._trimInBackground()
            weakSelf._trimRecursively()
        }
    }
    
    fileprivate func _trimInBackground() {
        _workQueue.async {
            switch self.config.totalCostLimit {
            case .unlimited, .zero:
                break
            case let .byte(cost):
                self._trimToCost(cost)
                break
            }
            self._trimToCount(self.config.countLimit)
            switch self.config.expiry {
            case let .ageLimit(seconds):
                self._trimToAge(seconds)
                break
            default:
                break
            }
        }
    }
    
    fileprivate func _trimToCost(_ costLimit: UInt64) {
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
        
        var holder: [Any] = []
        
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
                usleep(10 * 1000) // 10
            }
        }
        
        if holder.count > 0 {
            if config.isReleaseAsynchronously {
                let tempQueue = config.isReleaseOnMainThread ? DispatchQueue.main: DispatchQueue.global(qos: .background)
                tempQueue.async {
                    _ = holder.count
                }
            } else if config.isReleaseOnMainThread && pthread_main_np() == 0 {
                DispatchQueue.main.async {
                    _ = holder.count
                }
            } else {
            }
        }
    }
        
    fileprivate func _trimToCount(_ countLimit: UInt64) {
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
        
        var holder: [Any] = []
        
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
                usleep(10 * 1000) // 10
            }
        }
        
        if holder.count > 0 {
            if config.isReleaseAsynchronously {
                let tempQueue = config.isReleaseOnMainThread ? DispatchQueue.main: DispatchQueue.global(qos: .background)
                tempQueue.async {
                    _ = holder.count
                }
            } else if config.isReleaseOnMainThread && pthread_main_np() == 0 {
                DispatchQueue.main.async {
                    _ = holder.count
                }
            } else {
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
        
        var holder: [Any] = []

        while !finish {
            if pthread_mutex_trylock(&_lock) == 0 {
                if let last = _lru.tail, now - last.time > ageLimit {
                    if let node = _lru.removeTailNode() {
                        holder.append(node)
                    }
                } else {
                    finish = true
                }
                pthread_mutex_unlock(&_lock)
            } else {
                usleep(10 * 1000) // 10
            }
        }
        
        if holder.count > 0 {
            if config.isReleaseAsynchronously {
                let tempQueue = config.isReleaseOnMainThread ? DispatchQueue.main: DispatchQueue.global(qos: .background)
                tempQueue.async {
                    _ = holder.count
                }
            } else if config.isReleaseOnMainThread && pthread_main_np() == 0 {
                DispatchQueue.main.async {
                    _ = holder.count
                }
            } else {
            }
        }
    }
}

public final class LGLinkedList<KeyType: Hashable, ValueType: LGMemoryCost> {
    public class LinkedListNode {
        weak var previous: LinkedListNode?
        var next: LinkedListNode?
        var key: KeyType
        var value: ValueType
        var cost: UInt64
        var time: TimeInterval
        
        public init(key: KeyType, value: ValueType, time: TimeInterval = 0.0) {
            self.key = key
            self.value = value
            self.cost = value.memoryCost()
            self.time = time
        }
        
        static func == (lhs: LGLinkedList.LinkedListNode, rhs: LGLinkedList.LinkedListNode?) -> Bool {
            return lhs.key == rhs?.key
        }
        
        static func == (lhs: LGLinkedList.LinkedListNode?, rhs: LGLinkedList.LinkedListNode) -> Bool {
            return lhs?.key == rhs.key
        }
    }
    

    
    public typealias Node = LinkedListNode
    
    private var cache: [KeyType: Node] = [KeyType: Node]()

    public private(set) var totalCost: UInt64 = 0
    public private(set) var totalCount: UInt64 = 0
    
    public var isReleaseOnMainThread: Bool = false
    public var isReleaseAsynchronously: Bool = true
    
    public private(set) var head: Node?
    public private(set) weak var tail: Node?
    
    public init() {}
    
    public func containsValue(forKey key: KeyType) -> Bool {
        return self.cache.contains(where: { (item) -> Bool in
            return key == item.key
        })
    }
    
    public func insertNode(atHead node: Node) {
        cache[node.key] = node
        totalCost += node.cost
        totalCount += 1
        
        if let head = head {
            node.next = head
            head.previous = node
            self.head = node
        } else {
            head = node
            tail = node
        }
    }
    
    public func bringNode(toHead node: Node) {
        if head == node {
            return
        }
        
        if tail == node {
            tail = node.previous
            tail?.next = nil
        } else {
            node.next?.previous = node.previous
            node.previous?.next = node.next
        }
        
        node.next = head
        node.previous = nil
        
        self.head?.previous = node
        self.head = node
    }

    public func removeNode(_ node: Node) {
        cache[node.key] = nil
        totalCost -= node.cost
        totalCount -= 1
        if let next = node.next {
            next.previous = node.previous
        }
        
        if let previous = node.previous {
            previous.next = node.next
        }
        
        if head == node {
            head = node.next
        }
        
        if tail == node {
            tail = node.previous
        }
    }

    @discardableResult
    public func removeTailNode() -> Node? {
        guard let tail = self.tail else { return nil }
        cache[tail.key] = nil
        
        totalCost -= tail.cost
        totalCount -= 1
        
        if head == tail {
            head = nil
            self.tail = nil
        } else {
            self.tail = tail.previous
            tail.next = nil
        }
        return tail
    }
    
    public func removeAll() {
        totalCount = 0
        totalCost = 0
        
        head = nil
        tail = nil
        
        if self.cache.count > 0 {
            if isReleaseAsynchronously {
                var queue: DispatchQueue
                if isReleaseOnMainThread {
                    queue = DispatchQueue.main
                } else {
                    queue = DispatchQueue.global(qos: DispatchQoS.QoSClass.background)
                }
                queue.async { [weak self] in
                    guard let strongSelf = self else {return}
                    strongSelf.cache.removeAll()
                }
            } else if isReleaseOnMainThread, pthread_main_np() == 0 {
                DispatchQueue.main.async { [weak self] in
                    guard let strongSelf = self else {return}
                    strongSelf.cache.removeAll()
                }
            } else {
                self.cache.removeAll()
            }
        }
    }
}

extension LGLinkedList {
    public subscript(_ key: KeyType) -> ValueType? {
        get {
            if let value = self.cache[key] {
                self.bringNode(toHead: value)
                return value.value
            } else {
                return nil
            }
        } set {
            if let value = newValue {
                if let node = self.cache[key] {
                    node.value = value
                    node.time = CACurrentMediaTime()
                    self.bringNode(toHead: node)
                } else {
                    let node = Node(key: key, value: value, time: CACurrentMediaTime())
                    self.insertNode(atHead: node)
                }
            } else {
                if let node = self.cache[key] {
                    self.removeNode(node)
                }
            }
            println(self.cache.count)
            println(self.totalCost)
        }
    }
}
