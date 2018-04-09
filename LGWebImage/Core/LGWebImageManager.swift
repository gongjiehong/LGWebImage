//
//  LGWebImageManager.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2017/10/16.
//  Copyright © 2017年 龚杰洪. All rights reserved.
//

import Foundation
import LGHTTPRequest

public class LGWebImageManager {
    public var requestContainer: NSMapTable<NSString, LGHTTPRequest>
    public var cache: LGImageCache
    
    fileprivate var _lock = DispatchSemaphore(value: 1)
    fileprivate var _cacheQueue = DispatchQueue.userInitiated
    
    public init() {
        requestContainer = NSMapTable<NSString, LGHTTPRequest>(keyOptions: NSPointerFunctions.Options.strongMemory,
                                                               valueOptions: NSPointerFunctions.Options.weakMemory)
        cache = LGImageCache.shared
    }
    
    public static let `default`: LGWebImageManager = {
        return LGWebImageManager()
    }()
    
    private var progressBlocksMap = [LGDownloadRequest: [LGWebImageProgressBlock]]()
    
    public func downloadImageWith(url: LGURLConvertible,
                                  options: LGWebImageOptions,
                                  progress: LGWebImageProgressBlock? = nil,
                                  completion: @escaping LGWebImageCompletionBlock)
    {
        do {
            networkIndicatorStart()
            
            // 处理请求
            let remoteURL = try url.asURL()
            let urlString = remoteURL.absoluteString
            // 先读取缓存
            if let image = self.cache.getImage(forKey: urlString) {
                completion(image,
                           remoteURL,
                           LGWebImageSourceType.memoryCacheFast,
                           LGWebImageStage.finished,
                           nil)
                networkIndicatorStop()
                return
            }
            let urlNSSString = NSString(string: urlString)
            var targetRequest: LGDownloadRequest
            if let request = requestContainer.object(forKey: urlNSSString) as? LGDownloadRequest {
                targetRequest = request
            } else {
                let destinitionURL = self.cache.diskCache.filePathForDiskStorage(withKey: urlString)
                let request = LGURLSessionManager.default.download(url, to: destinitionURL)
                targetRequest = request
            }
            requestContainer.setObject(targetRequest, forKey: urlNSSString)
            
            // 处理进度和图片结果转换回调
            func addBlockToMap() {
                _ = _lock.wait(timeout: DispatchTime.distantFuture)
                if progress != nil {
                    if var tempArray = progressBlocksMap[targetRequest] {
                        tempArray.append(progress!)
                        progressBlocksMap[targetRequest] = tempArray
                    } else {
                        progressBlocksMap[targetRequest] = [progress!]
                    }
                }
                _ = _lock.signal()
            }
            
            addBlockToMap()
            
            // 调用进度回调
            func invokeProgressBlocks(_ request: LGDownloadRequest, progress: Progress) {
                _ = _lock.wait(timeout: DispatchTime.distantFuture)
                if let tempArray = self.progressBlocksMap[request] {
                    if tempArray.count > 0 {
                        for block in tempArray {
                            block(progress)
                        }
                    }
                }
                _ = _lock.signal()
            }
            
            targetRequest.downloadProgress(queue: _cacheQueue)
            {(progress) in
                invokeProgressBlocks(targetRequest, progress: progress)
            }
            
            // 下载完成结果处理
            targetRequest.validate().response(queue: _cacheQueue)
            {[unowned self] (response) in
                if response.error != nil {
                    completion(nil, nil, LGWebImageSourceType.none, LGWebImageStage.finished, response.error)
                } else {
                    if let destinationURL = response.destinationURL,
                        let originURL = response.request?.url
                    {
                        // 通过拷贝文件的方式设置磁盘缓存
                        self.cache.diskCache.setObject(withFileURL: destinationURL,
                                                       forKey: originURL.absoluteString)
                        // 缓存中如果有，直接读取并返回
                        if let image = self.cache.getImage(forKey: originURL.absoluteString) {
                            completion(image,
                                       originURL,
                                       LGWebImageSourceType.memoryCacheFast,
                                       LGWebImageStage.finished,
                                       nil)
                        } else if let image = self.cache.getImage(forKey: originURL.absoluteString,
                                                                  withType: LGImageCacheType.disk)
                        {
                            completion(image,
                                       originURL,
                                       LGWebImageSourceType.memoryCacheFast,
                                       LGWebImageStage.finished,
                                       nil)
                        } else {
                            
                        }
                    } else {
                        
                    }
                    
                }
                _ = self._lock.wait(timeout: DispatchTime.distantFuture)
                self.progressBlocksMap.removeValue(forKey: targetRequest)
                _ = self._lock.signal()
                networkIndicatorStop()
            }
        } catch {
            println(error)
            networkIndicatorStop()
        }
    }
}

fileprivate func networkIndicatorStart() {
    LGWebImageApplicationNetworkIndicatorInfo.shared.changeNetworkActivityCount(withDelta: 1)
}

fileprivate func networkIndicatorStop() {
    LGWebImageApplicationNetworkIndicatorInfo.shared.changeNetworkActivityCount(withDelta: -1)
}

/// 处理状态栏网络请求菊花显示和隐藏
fileprivate class LGWebImageApplicationNetworkIndicatorInfo {
    
    /// 初始化单例
    static let shared: LGWebImageApplicationNetworkIndicatorInfo = {
        return LGWebImageApplicationNetworkIndicatorInfo()
    }()
    
    /// 当前正在进行的请求计数
    var count: Int = 0
    
    init() {
    }
    
    /// 根据偏移量控制是否显示和隐藏状态栏菊花
    ///
    /// - Parameter delta: 偏移量，请求开始+1，请求结束-1
    func changeNetworkActivityCount(withDelta delta: Int) {
        if Thread.current.isMainThread {
            self.count += delta
            UIApplication.shared.isNetworkActivityIndicatorVisible = self.count > 0
        } else {
            DispatchQueue.main.async {
                self.count += delta
                UIApplication.shared.isNetworkActivityIndicatorVisible = self.count > 0
            }
        }
    }
}

// MARK: - 填充最后个像素
extension CGImage {
    public func lastPixelFilled() -> Bool {
        let width = self.width
        let height = self.height
        if width == 0 || height == 0 {return false}
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrderMask.rawValue
        let context = CGContext(data: nil,
                                width: 1,
                                height: 1,
                                bitsPerComponent: 8,
                                bytesPerRow: 0,
                                space: LGCGColorSpaceDeviceRGB,
                                bitmapInfo: bitmapInfo)
        if context == nil {return false}
        context?.draw(self, in: CGRect(x: -width + 1, y: 0, width: width, height: height))
        let data = context?.data
        var isAlpha: Bool = false
        if data != nil {
            let array = data!.load(as: [UInt8].self)
            if array[0] == 0 {
                isAlpha = true
            }
        }
        
        return !isAlpha
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
    
    static let shared: LGURLBlackList = {
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
