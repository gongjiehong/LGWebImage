////
////  LGWebImageManager.swift
////  LGWebImage
////
////  Created by 龚杰洪 on 2017/10/16.
////  Copyright © 2017年 龚杰洪. All rights reserved.
////
//
//import Foundation
//
//public typealias LGHTTPHeaders = [String: String]
//
//
//public class LGWebImageManager {
//    
//    public var cache: LGImageCache?
//    public var queue: OperationQueue?
//    public var timeOut: TimeInterval = 15.0
//    
//    
//    /// 特殊header
//    public var headers: LGHTTPHeaders = LGHTTPHeaders()
//    
//    
//    /// 服务器需要登录时使用
//    public var username: String?
//    public var password: String?
//    
//    /// 通过图片缓存和队列初始化
//    ///
//    /// - Parameters:
//    ///   - cache: LGImageCache
//    ///   - queue: OperationQueue
//    public init(withCache cache: LGImageCache?, queue: OperationQueue?) {
//        self.cache = cache
//        self.queue = queue
//        self.timeOut = 15.0
//        self.headers["Accept"] = "image/webp,image/*;q=0.8"
//    }
//    
//    
//    /// 单例初始化
//    public static let shared: LGWebImageManager = {
//        let cache = LGImageCache.shared
//        let queue = OperationQueue()
//        queue.qualityOfService = QualityOfService.background
//        return LGWebImageManager(withCache: cache, queue: queue)
//    }()
//    
//    public func requestImage(withURL url: LGWebImageURLConvertible,
//                             options: LGWebImageOptions,
//                             progress: LGWebImageProgressBlock? = nil,
//                             transform: LGWebImageTransformBlock? = nil,
//                             completion: LGWebImageCompletionBlock? = nil) -> LGWebImageDownloadOperation? {
//        do {
//            var request = try URLRequest(url: url.asURL())
//            request.timeoutInterval = timeOut
//            request.httpShouldHandleCookies = options.contains(LGWebImageOptions.handleCookies)
//            request.allHTTPHeaderFields = headers
//            request.httpShouldUsePipelining = true
//            if options.contains(LGWebImageOptions.useURLCache) {
//                request.cachePolicy = URLRequest.CachePolicy.useProtocolCachePolicy
//            } else {
//                request.cachePolicy = URLRequest.CachePolicy.reloadIgnoringLocalCacheData
//            }
//            
//            let operation = try LGWebImageDownloadOperation(request: request,
//                                                            options: options,
//                                                            cache: self.cache,
//                                                            progress: progress,
//                                                            transform: transform,
//                                                            completion: completion)
//            if username != nil && password != nil {
//                operation.credential = URLCredential(user: username!, password: password!, persistence: URLCredential.Persistence.forSession)
//            }
//            
//            if self.queue != nil {
//                self.queue!.addOperation(operation)
//            } else {
//                operation.start()
//            }
//            
//            return operation
//            
//        } catch {
//            return nil
//        }
//        
//    }
//    
//    public func cacheKeyForURL(_ url: LGWebImageURLConvertible) -> String {
//        do {
//            let tempUrl = try url.asURL()
//            return tempUrl.absoluteString
//        } catch {
//            return ""
//        }
//    }
//    
//    public class func incrementNetworkActivityCount() {
//        LGWebImageApplicationNetworkIndicatorInfo.shared.changeNetworkActivityCount(withDelta: 1)
//    }
//
//    public class func decrementNetworkActivityCount() {
//        LGWebImageApplicationNetworkIndicatorInfo.shared.changeNetworkActivityCount(withDelta: -1)
//    }
//    
//    public class func currentNetworkActivityCount() -> Int {
//        return LGWebImageApplicationNetworkIndicatorInfo.shared.count
//    }
//}
//
//fileprivate class LGWebImageApplicationNetworkIndicatorInfo {
//    
//    static let shared: LGWebImageApplicationNetworkIndicatorInfo = {
//        return LGWebImageApplicationNetworkIndicatorInfo()
//    }()
//    
//    var count: Int = 0
//    
//    init() {
//        
//    }
//    
//    func changeNetworkActivityCount(withDelta delta: Int) {
//        if Thread.current.isMainThread {
//            self.count += delta
//            print(self)
//            UIApplication.shared.isNetworkActivityIndicatorVisible = self.count > 0
//        } else {
//            DispatchQueue.main.async {
//                self.count += delta
//                UIApplication.shared.isNetworkActivityIndicatorVisible = self.count > 0
//            }
//        }
//    }
//}
