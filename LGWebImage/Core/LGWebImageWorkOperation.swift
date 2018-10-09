////
////  LGWebImageWorkOperation.swift
////  LGWebImage
////
////  Created by 龚杰洪 on 2018/9/14.
////  Copyright © 2018年 龚杰洪. All rights reserved.
////
//
//import UIKit
//import LGHTTPRequest
//
//fileprivate class LGRequestMap {
//    var requestTable: NSMapTable<NSString, LGDataRequest>
//    var lock: NSLock = NSLock()
//    
//    init() {
//        requestTable = NSMapTable<NSString, LGDataRequest>(keyOptions: NSPointerFunctions.Options.strongMemory,
//                                                           valueOptions: NSPointerFunctions.Options.weakMemory,
//                                                           capacity: 0)
//    }
//    
//    static let `default`: LGRequestMap = {
//        return LGRequestMap()
//    }()
//    
//    func object(forKey aKey: NSString?) -> LGDataRequest? {
//        lock.lock()
//        defer {
//            lock.unlock()
//        }
//        
//        return self.requestTable.object(forKey: aKey)
//    }
//    
//    func removeObject(forKey aKey: NSString?) {
//        lock.lock()
//        defer {
//            lock.unlock()
//        }
//        self.requestTable.removeObject(forKey: aKey)
//    }
//    
//    func setObject(_ anObject: LGDataRequest?, forKey aKey: NSString?) {
//        lock.lock()
//        defer {
//            lock.unlock()
//        }
//        self.requestTable.setObject(anObject, forKey: aKey)
//    }
//
//}
//
//public class LGWebImageWorkOperation: Operation {
//    private var _isFinished: Bool = false
//    public override var isFinished: Bool {
//        get {
//            lock.lock()
//            defer {
//                lock.unlock()
//            }
//            return _isFinished
//        } set {
//            lock.lock()
//            defer {
//                lock.unlock()
//            }
//            if _isFinished != newValue {
//                willChangeValue(forKey: "isFinished")
//                _isFinished = newValue
//                didChangeValue(forKey: "isFinished")
//            }
//        }
//    }
//    
//    private var _isCancelled: Bool = false
//    public override var isCancelled: Bool {
//        get {
//            lock.lock()
//            defer {
//                lock.unlock()
//            }
//            return _isCancelled
//        }
//        set {
//            lock.lock()
//            defer {
//                lock.unlock()
//            }
//            if _isCancelled != newValue {
//                willChangeValue(forKey: "isCancelled")
//                _isCancelled = newValue
//                didChangeValue(forKey: "isCancelled")
//            }
//        }
//    }
//    
//    private var _isExecuting: Bool = false
//    public override var isExecuting: Bool {
//        get{
//            lock.lock()
//            defer {
//                lock.unlock()
//            }
//            return _isExecuting
//        }
//        set {
//            lock.lock()
//            defer {
//                lock.unlock()
//            }
//            
//            if _isExecuting != newValue {
//                willChangeValue(forKey: "isExecuting")
//                _isExecuting = newValue
//                didChangeValue(forKey: "isExecuting")
//            }
//        }
//    }
//    
//    public override var isConcurrent: Bool {
//        return true
//    }
//    
//    public override var isAsynchronous: Bool {
//        return true
//    }
//    
//    private var isStarted: Bool = false
//    private var lock: NSRecursiveLock = NSRecursiveLock()
//    private var taskId: UIBackgroundTaskIdentifier = UIBackgroundTaskIdentifier.invalid
//    
//    
//    weak var request: LGDataRequest?
//    var progress: LGWebImageProgressBlock?
//    var transform: LGWebImageTransformBlock?
//    var completion: LGWebImageCompletionBlock?
//    var options: LGWebImageOptions = LGWebImageOptions.default
//    var url: LGURLConvertible = ""
//
//    public init(withURL url: LGURLConvertible,
//                options: LGWebImageOptions = LGWebImageOptions.default,
//                progress: LGWebImageProgressBlock? = nil,
//                transform: LGWebImageTransformBlock? = nil,
//                completion: LGWebImageCompletionBlock? = nil)
//    {
//        super.init()
//        self.url = url
//        self.options = options
//        self.progress = progress
//        self.transform = transform
//        self.completion = completion
//    }
//
//    
//    public override func start() {
//        lock.lock()
//        defer {
//            lock.unlock()
//        }
//        
//        isStarted = true
//        
//        if isCancelled {
//            cancelOperation()
//            isFinished = true
//        } else if isReady, !isFinished, !isExecuting {
//            do {
//                let url = try self.url.asURL()
//                let urlKey = NSString(string: url.absoluteString)
//                if let request = LGRequestMap.default.object(forKey: urlKey) {
//                    request.responseData(queue: DispatchQueue.utility) { (dataResponse) in
//                        
//                    }
//                } else {
//                    request?.stream(closure: { (data) in
//                        
//                    })
//                }
//            } catch {
//                cancelOperation()
//            }
//        }
//        
//        
//    }
//
//    public override func cancel() {
//        lock.lock()
//        defer {
//            lock.unlock()
//        }
//        
//        if !isCancelled {
//            super.cancel()
//            isCancelled = true
//            
//            if isExecuting {
//                isExecuting = false
//            }
//            cancelOperation()
//        }
//        
//        if isStarted {
//            isFinished = true
//        }
//    }
//    
//    override public class func automaticallyNotifiesObservers(forKey key: String) -> Bool {
//        if key == "isExecuting" || key == "isFinished" || key == "isCancelled" {
//            return false
//        } else {
//            return super.automaticallyNotifiesObservers(forKey: key)
//        }
//    }
//    
//    
//    // MARK: - private
//    
//    func finish() {
//        isExecuting = false
//        isFinished = true
//        endBackgroundTask()
//    }
//    
//    private func cancelOperation() {
//        autoreleasepool { () -> Void in
//            if let completion = self.completion {
//                completion(nil, self.request?.request?.url, LGWebImageSourceType.none, LGWebImageStage.cancelled, nil)
//                endBackgroundTask()
//            }
//        }
//    }
//
//    private func endBackgroundTask() {
//        lock.lock()
//        defer {
//            lock.unlock()
//        }
//        
//        if self.taskId != UIBackgroundTaskIdentifier.invalid {
//            UIApplication.shared.endBackgroundTask(self.taskId)
//            self.taskId = UIBackgroundTaskIdentifier.invalid
//        }
//    }
//    
//    // MARK: - 销毁
//    deinit {
//        lock.lock()
//        defer {
//            lock.unlock()
//        }
//        
//        if isExecuting {
//            isCancelled = true
//            isFinished = true
//            
//        }
//        
//        cancelOperation()
//        
//        println("LGWebImageWorkOperation deinit")
//    }
//}
