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
    fileprivate var _sessionManager: LGURLSessionManager
    
    public init() {
        requestContainer = NSMapTable<NSString, LGHTTPRequest>(keyOptions: NSPointerFunctions.Options.strongMemory,
                                                               valueOptions: NSPointerFunctions.Options.weakMemory)
        cache = LGImageCache.default
        
        _sessionManager = LGURLSessionManager.default
    }
    

    /// 根据一些选项设置和信任的host进行初始化
    ///
    /// - Parameters:
    ///   - options: 固定设置
    ///   - trustHosts: 信任的host，设置后不会验证SSL有效性
    public init(options: LGWebImageOptions, trustHosts: [String] = []) {
        requestContainer = NSMapTable<NSString, LGHTTPRequest>(keyOptions: NSPointerFunctions.Options.strongMemory,
                                                               valueOptions: NSPointerFunctions.Options.weakMemory)
        cache = LGImageCache.default
        
        _sessionManager = LGURLSessionManager.default
        
        let sessionConfig = URLSessionConfiguration.default
        if options.contains(LGWebImageOptions.refreshImageCache) {
            sessionConfig.requestCachePolicy = URLRequest.CachePolicy.reloadIgnoringCacheData
        }
        
        var policies: [String : LGServerTrustPolicy] = [String : LGServerTrustPolicy]()
        
        for key in trustHosts {
            policies[key] = LGServerTrustPolicy.disableEvaluation
        }
        
        let sslTrust = LGServerTrustPolicyManager(policies: policies)
        
        _sessionManager = LGURLSessionManager(configuration: sessionConfig,
                                              delegate: LGURLSessionDelegate(),
                                              serverTrustPolicyManager: sslTrust)
    }
    
    public static let `default`: LGWebImageManager = {
        return LGWebImageManager()
    }()
    
    private var progressBlocksMap = [LGDataRequest: [LGWebImageProgressBlock]]()
    private var completionBlocksMap = [LGDataRequest: [LGWebImageCompletionBlock]]()
    private var progressiveContainerMap = [LGDataRequest: LGWebImageProgressiveContainer]()
    
    public func downloadImageWith(url: LGURLConvertible,
                                  options: LGWebImageOptions,
                                  progress: LGWebImageProgressBlock? = nil,
                                  completion: @escaping LGWebImageCompletionBlock)
    {
        // 处理忽略下载失败的URL和和名单
        if options.contains(LGWebImageOptions.ignoreFailedURL) &&
            LGURLBlackList.default.isContains(url: url)
        {
            completion(nil,
                       nil,
                       LGWebImageSourceType.memoryCacheFast,
                       LGWebImageStage.finished,
                       LGImageDownloadError.urlIsInTheBlackList(url: url))
            return
        }
        
        
        do {
            /**
             ** 处理菊花
             */
            if options.contains(LGWebImageOptions.showNetworkActivity) {
                networkIndicatorStart()
            }
            
            /**
             ** 转换url参数为目标类型
             **/
            let remoteURL = try url.asURL()
            let urlString = remoteURL.absoluteString
            
            /**
             ** 根据所需缓存数据类型读取数据
             **/
            var cacheType: LGImageCacheType
            if options.contains(LGWebImageOptions.ignoreDiskCache) {
                cacheType = LGImageCacheType.memory
            } else {
                cacheType = LGImageCacheType.all
            }
            if let image = self.cache.getImage(forKey: urlString, withType: cacheType) {
                completion(image,
                           remoteURL,
                           LGWebImageSourceType.memoryCacheFast,
                           LGWebImageStage.finished,
                           nil)
                networkIndicatorStop()
                return
            }
            
            /**
             ** 组装下载文件的目标路径，这里直接写入缓存的最终路径
             **/
            let destinationURL = self.cache.diskCache.filePathForDiskStorage(withKey: urlString)

            /**
             ** 处理唯一request，保证每个独立URL只处理一次
             **/
            let urlNSSString = NSString(string: urlString)
            _ = self._lock.wait(timeout: DispatchTime.distantFuture)
            var targetRequest: LGDataRequest
            if let request = requestContainer.object(forKey: urlNSSString) as? LGDataRequest {
                targetRequest = request
            } else {
                let request = LGURLSessionManager.default.request(url,
                                                    method: LGHTTPMethod.get,
                                                    parameters: nil,
                                                    encoding: LGURLEncoding.default,
                                                    headers: nil)
                targetRequest = request
                requestContainer.setObject(targetRequest, forKey: urlNSSString)
                targetRequest.stream { [weak self](data) in
                    // Write Data
                    let inputStream = InputStream(data: data)
                    // 此处需要先创建文件夹，如果未创建文件夹则无法使用stream
                    guard let outputStream = OutputStream(url: destinationURL,
                                                          append: true) else { return }
                    
                    inputStream.schedule(in: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)
                    outputStream.schedule(in: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)
                    inputStream.open()
                    outputStream.open()
                    
                    while inputStream.hasBytesAvailable && outputStream.hasSpaceAvailable {
                        var buffer = [UInt8](repeating: 0, count: 1024)
                        
                        let bytesRead = inputStream.read(&buffer, maxLength: 1024)
                        if inputStream.streamError != nil || bytesRead < 0 {
                            break
                        }
                        
                        let bytesWritten = outputStream.write(&buffer, maxLength: bytesRead)
                        if outputStream.streamError != nil || bytesWritten < 0 {
                            break
                        }
                        
                        if bytesRead == 0 && bytesWritten == 0 {
                            break
                        }
                    }
                    
                    outputStream.close()
                    inputStream.close()
                    outputStream.remove(from: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)
                    inputStream.remove(from: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)
                    
                    self?.decodeDataToUIImageIfNeeded(data,
                                                     options: options,
                                                     destinationFileURL: destinationURL,
                                                     targetRequest: targetRequest)
                }
            }
            _ = _lock.signal()
            
            /**
             ** 将进度条回调添加到缓存
             **/
            if progress != nil {
                addProgressBlockToMap(targetRequest, progress: progress!)
            }
            
            /**
             ** 处理进度回调
             **/
            targetRequest.downloadProgress(queue: _cacheQueue)
            {[weak self](progress) in
                self?.invokeProgressBlocks(targetRequest, progress: progress)
            }
            
            addCompletionBlocksToMap(targetRequest, completion: completion)
            
            // 下载完成结果处理
            targetRequest.validate().response(queue: _cacheQueue)
            {[unowned self] (response) in
                if response.error != nil {
                    completion(nil, nil, LGWebImageSourceType.none, LGWebImageStage.finished, response.error)
                } else {
                    if let originURL = response.request?.url
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
                            if options.contains(LGWebImageOptions.ignoreFailedURL) {
                                LGURLBlackList.default.addURL(url)
                            }
                            completion(nil,
                                       originURL,
                                       LGWebImageSourceType.memoryCacheFast,
                                       LGWebImageStage.finished,
                                       LGImageDownloadError.cannotReadFile)
                        }
                    } else {
                        if options.contains(LGWebImageOptions.ignoreFailedURL) {
                            LGURLBlackList.default.addURL(url)
                        }
                        completion(nil,
                                   nil,
                                   LGWebImageSourceType.memoryCacheFast,
                                   LGWebImageStage.finished,
                                   LGImageDownloadError.targetURLOrOriginURLInvalid(targetURL: destinationURL,
                                                                                    originURL: response.request?.url))
                    }
                }
                _ = self._lock.wait(timeout: DispatchTime.distantFuture)
                self.progressBlocksMap.removeValue(forKey: targetRequest)
                self.completionBlocksMap.removeValue(forKey: targetRequest)
                self.progressiveContainerMap.removeValue(forKey: targetRequest)
                self.requestContainer.removeObject(forKey: urlNSSString)
                _ = self._lock.signal()
                networkIndicatorStop()
            }
        } catch {
            println(error)
            networkIndicatorStop()
        }
    }
    
    
    /// 将进度条回调添加到缓存
    ///
    /// - Parameters:
    ///   - targetRequest: key
    ///   - block: LGWebImageProgressBlock value
    private func addProgressBlockToMap(_ targetRequest: LGDataRequest, progress: @escaping LGWebImageProgressBlock) {
        _ = _lock.wait(timeout: DispatchTime.distantFuture)
        if var tempArray = progressBlocksMap[targetRequest] {
            tempArray.append(progress)
            progressBlocksMap[targetRequest] = tempArray
        } else {
            progressBlocksMap[targetRequest] = [progress]
        }
        _ = _lock.signal()
    }
    
    /// 处理进度条回调
    ///
    /// - Parameters:
    ///   - request: 目标请求
    ///   - progress: Progress
    private func invokeProgressBlocks(_ request: LGDataRequest, progress: Progress) {
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
    

    private func addCompletionBlocksToMap(_ targetRequest: LGDataRequest,
                                         completion: @escaping LGWebImageCompletionBlock)
    {
        _ = _lock.wait(timeout: DispatchTime.distantFuture)
        if var tempArray = completionBlocksMap[targetRequest] {
            tempArray.append(completion)
            completionBlocksMap[targetRequest] = tempArray
        } else {
            completionBlocksMap[targetRequest] = [completion]
        }
        _ = _lock.signal()
    }

    private func invokeCompletionBlocks(_ request: LGDataRequest,
                                       image: UIImage?,
                                       url: URL?,
                                       sourceType: LGWebImageSourceType,
                                       imageStatus: LGWebImageStage,
                                       error: Error?)
    {
        _ = _lock.wait(timeout: DispatchTime.distantFuture)
        if let tempArray = self.completionBlocksMap[request] {
            if tempArray.count > 0 {
                for block in tempArray {
                    block(image, url, sourceType, imageStatus, error)
                }
            }
        }
        _ = _lock.signal()
    }
    
    private func decodeDataToUIImageIfNeeded(_ data: Data,
                                             options: LGWebImageOptions,
                                             destinationFileURL: URL,
                                             targetRequest: LGDataRequest)
    {
        let progressive = options.contains(LGWebImageOptions.progressive)
        let progressiveBlur = options.contains(LGWebImageOptions.progressiveBlur)
        
        if !(progressiveBlur || progressive) {
            return
        }
        
        do {
            var progressiveContainer: LGWebImageProgressiveContainer
            if let container = progressiveContainerMap[targetRequest] {
                progressiveContainer = container
            } else {
                progressiveContainer = LGWebImageProgressiveContainer()
                progressiveContainerMap[targetRequest] = progressiveContainer
            }
            
            // 数据足够长且马上要下载完成了，不再继续处理
            if targetRequest.progress.fractionCompleted > 0.9 {
                return
            }
            
            // 忽略则不处理
            var progressiveIgnored: Bool = progressiveContainer.progressiveIgnored
            
            if progressiveIgnored == true { return }
            
            let min: TimeInterval = progressiveBlur ? .minProgressiveBlurTimeInterval : .minProgressiveTimeInterval
            let now = CACurrentMediaTime()
            if now - progressiveContainer.lastProgressiveDecodeTimestamp < min {
                return
            }
            return
            let writedData = try Data(contentsOf: destinationFileURL)
            
            // 不够解码长度
            if data.count <= 16 {
                return
            }
            
            var progressiveDecoder = progressiveContainer.progressiveDecoder
            if progressiveDecoder == nil {
                progressiveDecoder = LGImageDecoder(withScale: UIScreen.main.scale)
                progressiveContainer.progressiveDecoder = progressiveDecoder
            }
            _ = progressiveDecoder?.updateData(data: writedData, final: false)
            
            // webp 和其它未知格式无法进行扫描显示
            if progressiveDecoder?.imageType == LGImageType.unknow ||
                progressiveDecoder?.imageType == LGImageType.webp ||
                progressiveDecoder?.imageType == LGImageType.other {
                progressiveDecoder = nil
                progressiveContainer.progressiveIgnored = true
                return
            }
            
            if progressiveBlur {
                // 只支持 png & jpg
                if !(progressiveDecoder?.imageType == LGImageType.jpeg ||
                    progressiveDecoder?.imageType == LGImageType.png) {
                    progressiveDecoder = nil
                    progressiveContainer.progressiveIgnored = true
                    return
                }
            }
            
            
            if progressiveDecoder?.frameCount == 0 {return}
            
            if !progressiveBlur {
                let frame = progressiveDecoder?.frameAtIndex(index: 0, decodeForDisplay: true)
                if frame?.image != nil {
                    self.invokeCompletionBlocks(targetRequest,
                                                image: frame?.image,
                                                url: targetRequest.request?.url,
                                                sourceType: LGWebImageSourceType.remoteServer,
                                                imageStatus: LGWebImageStage.progress,
                                                error: nil)
                }
                return
            } else {
                if progressiveDecoder?.imageType == LGImageType.jpeg {
                    if !progressiveContainer.progressiveDetected {
                        if let dic = progressiveDecoder?.frameProperties(atIndex: 0) {
                            let jpeg = dic[kCGImagePropertyJFIFIsProgressive as String] as? [String: Any]
                            if let isProg = jpeg?[kCGImagePropertyJFIFIsProgressive as String] as? NSNumber {
                                if !isProg.boolValue {
                                    progressiveIgnored = true
                                    progressiveDecoder = nil
                                    return
                                }
                                progressiveContainer.progressiveDetected = true
                            }
                            
                        }
                        
                    }
                    let scanLength = writedData.count - progressiveContainer.progressiveScanedLength - 4
                    if scanLength <= 2 {return}
                    let endIndex = Data.Index(progressiveContainer.progressiveScanedLength + scanLength)
                    let scanRange: Range<Data.Index> = Data.Index(progressiveContainer.progressiveScanedLength)..<endIndex
                    let markerRange = writedData.range(of: JPEGSOSMarker,
                                                         options: Data.SearchOptions.backwards,
                                                         in: scanRange)
                    progressiveContainer.progressiveScanedLength = writedData.count
                    if markerRange == nil {return}
                } else if progressiveDecoder?.imageType == LGImageType.png {
                    if !progressiveContainer.progressiveDetected {
                        let dic = progressiveDecoder?.frameProperties(atIndex: 0)
                        let png = dic?[kCGImagePropertyPNGDictionary as String] as? [String: Any]
                        let isProg = png?[kCGImagePropertyPNGInterlaceType as String] as? NSNumber
                        if isProg != nil && !isProg!.boolValue {
                            progressiveIgnored = true
                            progressiveDecoder = nil
                            return
                        }
                        progressiveContainer.progressiveDetected = true
                    }
                }
                
                let frame = progressiveDecoder?.frameAtIndex(index: 0, decodeForDisplay: true)
                guard let image = frame?.image else {
                    return
                }
                
                if image.cgImage?.lastPixelFilled() == false {
                    return
                }
                
                progressiveContainer.progressiveDisplayCount += 1
                var radius: CGFloat = 32
                if targetRequest.expectedContentLength > 0 {
                    radius *= 1.0 / (3.0 * CGFloat(writedData.count) / CGFloat(targetRequest.totalBytesReceived) + 0.6) - 0.25
                } else {
                    radius /= CGFloat(progressiveContainer.progressiveDisplayCount)
                }
                let temp = image.lg_imageByBlurRadius(radius,
                                                      tintColor: nil,
                                                      tintBlendMode: CGBlendMode.normal,
                                                      saturation: 1, maskImage: nil)
                if temp != nil {
                    self.invokeCompletionBlocks(targetRequest,
                                                image: temp,
                                                url: targetRequest.request?.url,
                                                sourceType: LGWebImageSourceType.remoteServer,
                                                imageStatus: LGWebImageStage.progress,
                                                error: nil)
                }
            }
        } catch {
            println(error)
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
