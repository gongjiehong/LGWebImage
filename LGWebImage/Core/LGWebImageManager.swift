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

/// 标识请求回调的Token类型定义，用于取消回调，但不取消下载
public typealias LGWebImageCallbackToken = String

/// 同意下载图片的Manager
public class LGWebImageManager {
    /// 请求容器，用于存储当前活跃的请求，避免重复下载同一个文件
    public var requestContainer: NSMapTable<NSString, LGHTTPRequest>
    
    /// 图片缓存工具
    public var cache: LGImageCache
    
    /// 单线程锁
    fileprivate var _lock = DispatchSemaphore(value: 1)
    
    /// 同步处理队列
    fileprivate var _cacheQueue = DispatchQueue(label: "com.LGWebImageManager.cacheQueue",
                                                qos: DispatchQoS.utility,
                                                attributes: DispatchQueue.Attributes.concurrent,
                                                autoreleaseFrequency: DispatchQueue.AutoreleaseFrequency.inherit,
                                                target: DispatchQueue.utility)
    
    /// 下载URLSession管理器
    fileprivate var _sessionManager: LGURLSessionManager
    
    /// 大图的最大字节数，这里设置为1MB，超过1MB不处理渐进显示，在显示的时候根据屏幕大小生成缩略图进行展示
    fileprivate let _maxFileSize: UInt64 = 1024 * 1024
    
    private var progressBlocksMap = [LGDataRequest: [LGWebImageCallbackToken: LGWebImageProgressBlock]]()
    private var completionBlocksMap = [LGDataRequest: [LGWebImageCallbackToken: LGWebImageCompletionBlock]]()
    private var progressiveContainerMap = [LGDataRequest: LGWebImageProgressiveContainer]()
    
    private let tempDirSuffix = "LGWebImage/TempFile/"
    
    /// 根据一些选项设置和信任的host进行初始化
    ///
    /// - Parameters:
    ///   - options: 固定设置
    ///   - trustHosts: 信任的host，设置后不会验证SSL有效性
    public init(options: LGWebImageOptions = LGWebImageOptions.default, trustHosts: [String] = []) {
        requestContainer = NSMapTable<NSString, LGHTTPRequest>(keyOptions: NSPointerFunctions.Options.weakMemory,
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
        
        createTempFileDirIfNeeded()
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
        let token = UUID().uuidString + "\(CACurrentMediaTime())"
        _cacheQueue.async(flags: DispatchWorkItemFlags.barrier) { [unowned self] in
            // 处理忽略下载失败的URL和和名单
            if options.contains(LGWebImageOptions.ignoreFailedURL) &&
                LGURLBlackList.default.isContains(url: url)
            {
                completion?(nil,
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
                    completion?(image,
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
                let destinationURL = self.getDownloadTempPathURL(from: remoteURL)
                
                /**
                 ** 处理唯一request，保证每个独立URL只处理一次
                 **/
                let urlNSSString = NSString(string: urlString)
                var targetRequest: LGDataRequest?
                _ = self._lock.wait(timeout: DispatchTime.distantFuture)
                if let request = self.requestContainer.object(forKey: urlNSSString) as? LGDataRequest {
                    targetRequest = request
                    _ = self._lock.signal()
                } else {
                    _ = self._lock.signal()
                    var header: LGHTTPHeaders = [:]
                    var resumeData: Data? = nil
                    
                    if options.contains(LGWebImageOptions.enableBreakpointPass) {
                        do {
                            resumeData = try Data(contentsOf: destinationURL)
                            if resumeData!.count > 0 {
                                // 设置header，从指定的位置开始继续往后下载
                                header["Range"] = "bytes=\(resumeData!.count)-"
                            }
                        } catch {
                            
                        }
                    } else {
                        do {
                            try FileManager.default.removeItem(at: destinationURL)
                        } catch {
                            
                        }
                    }
                    
                    let request = self._sessionManager.request(url,
                                                               method: LGHTTPMethod.get,
                                                               parameters: nil,
                                                               encoding: LGURLEncoding.default,
                                                               headers: header)
                    targetRequest = request
                    
                    
                    var receivedData: Data
                    if options.contains(LGWebImageOptions.enableBreakpointPass) {
                        receivedData = resumeData ?? Data()
                    } else {
                        receivedData = Data()
                    }
                    
                    targetRequest = targetRequest?.stream(closure: {[unowned self] (data) in
                        receivedData.append(data)
                        
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
                        
                        inputStream.remove(from: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)
                        outputStream.remove(from: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)
                        
                        inputStream.close()
                        outputStream.close()
                        
                        guard let weakTargetRequest = targetRequest else {
                            return
                        }
                        self.decodeDataToUIImageIfNeeded(receivedData,
                                                         options: options,
                                                         targetRequest: weakTargetRequest)
                    })

                    /**
                     ** 处理进度回调
                     **/
                    targetRequest = targetRequest!.downloadProgress(queue: DispatchQueue.utility)
                    {[unowned self] (progress) in
                        self.invokeProgressBlocks(targetRequest!, progress: progress)
                    }

                    // 下载完成结果处理
                    targetRequest = targetRequest!.validate().response(queue: DispatchQueue.utility)
                    {[unowned self] (response) in
                        guard let weakTargetRequest = targetRequest else {
                            return
                        }
                        if response.error != nil {
                            self.invokeCompletionBlocks(weakTargetRequest,
                                                        image: nil,
                                                        url: nil,
                                                        sourceType: LGWebImageSourceType.none,
                                                        imageStatus: LGWebImageStage.finished,
                                                        error: response.error)
                        } else {
                            if let originURL = response.request?.url
                            {
                                func checkNormalImage() {
                                    // 通过拷贝文件的方式设置磁盘缓存
                                    self.cache.diskCache.setObject(withFileURL: destinationURL,
                                                                   forKey: originURL.absoluteString)
                                    
                                    // 首先直接对data进行解码，解码不成功再说后续
                                    if let image = LGImage.imageWith(data: receivedData) {
                                        self.cache.memoryCache.setObject(LGCacheItem(data: image,
                                                                                     extendedData: nil),
                                                                         forKey: originURL.absoluteString,
                                                                         withCost: image.imageCost)
                                        self.invokeCompletionBlocks(weakTargetRequest,
                                                                    image: image,
                                                                    url: originURL,
                                                                    sourceType: LGWebImageSourceType.memoryCacheFast,
                                                                    imageStatus: LGWebImageStage.finished,
                                                                    error: nil)
                                    } else if let image = self.cache.getImage(forKey: originURL.absoluteString,
                                                                              withType: LGImageCacheType.disk)
                                    {
                                        self.invokeCompletionBlocks(weakTargetRequest,
                                                                    image: image,
                                                                    url: originURL,
                                                                    sourceType: LGWebImageSourceType.memoryCacheFast,
                                                                    imageStatus: LGWebImageStage.finished,
                                                                    error: nil)
                                    } else {
                                        if options.contains(LGWebImageOptions.ignoreFailedURL) {
                                            LGURLBlackList.default.addURL(url)
                                        }
                                        self.invokeCompletionBlocks(weakTargetRequest,
                                                                    image: nil,
                                                                    url: originURL,
                                                                    sourceType: LGWebImageSourceType.none,
                                                                    imageStatus: LGWebImageStage.finished,
                                                                    error: LGImageDownloadError.cannotReadFile)
                                    }
                                }
                                
                                if UInt64(receivedData.count) > self._maxFileSize &&
                                    options.contains(LGWebImageOptions.enableLargePictureOptimization)
                                {
                                    do {
                                        let decoder = try LGImageDecoder(withData: receivedData,
                                                                         scale: UIScreen.main.scale)
                                        if decoder.imageType != LGImageType.webp &&
                                            decoder.imageType != LGImageType.other &&
                                            decoder.imageType != LGImageType.unknow
                                        {
                                            if let image = decoder.largePictureCreateThumbnail() {
                                                self.cache.setImage(image: image, forKey: originURL.absoluteString)
                                                self.invokeCompletionBlocks(weakTargetRequest,
                                                                            image: image,
                                                                            url: originURL,
                                                                            sourceType: .memoryCacheFast,
                                                                            imageStatus: .finished,
                                                                            error: nil)
                                            } else {
                                                checkNormalImage()
                                            }
                                        } else {
                                            checkNormalImage()
                                        }
                                        
                                    } catch {
                                       checkNormalImage()
                                    }

                                } else {
                                    checkNormalImage()
                                }
                            } else {
                                if options.contains(LGWebImageOptions.ignoreFailedURL) {
                                    LGURLBlackList.default.addURL(url)
                                }
                                let originalURL = response.request?.url
                                let error = LGImageDownloadError.targetURLOrOriginURLInvalid(targetURL: destinationURL,
                                                                                             originURL: originalURL)
                                self.invokeCompletionBlocks(weakTargetRequest,
                                                            image: nil,
                                                            url: nil,
                                                            sourceType: LGWebImageSourceType.none,
                                                            imageStatus: LGWebImageStage.finished,
                                                            error: error)
                            }
                        }
                        self.clearMaps(targetRequest!, urlNSSString: urlNSSString)
                        networkIndicatorStop()
                        targetRequest = nil
                    }
                    
                    _ = self._lock.wait(timeout: DispatchTime.distantFuture)
                    self.requestContainer.setObject(targetRequest, forKey: urlNSSString)
                    _ = self._lock.signal()
                    
                }
                
                /**
                 ** 将进度条回调添加到缓存
                 **/
                if progress != nil && targetRequest != nil {
                    self.addProgressBlockToMap(targetRequest!, progress: progress!, callbackToken: token)
                }

                /**
                 ** 将完成回调添加到缓存
                 **/
                if completion != nil && targetRequest != nil {
                    self.addCompletionBlocksToMap(targetRequest!, completion: completion!, callbackToken: token)
                }
            } catch {
                println(error)
                networkIndicatorStop()
            }
        }
        
        return token
    }
    
    
    /// 为每个需要下载第地址分配一个临时存储文件路径，用于零时存储和断点续传
    ///
    /// - Parameter remoteURL: 文件的服务端地址
    /// - Returns: 文件的零时路径
    private func getDownloadTempPathURL(from remoteURL: URL) -> URL {
        let fileName = remoteURL.absoluteString.md5Hash() ?? UUID().uuidString
        let tempDir = NSTemporaryDirectory() + tempDirSuffix
        return URL(fileURLWithPath: tempDir + fileName)
    }
    
    
    /// 如果需要则创建下载临时文件夹
    private func createTempFileDirIfNeeded() {
        let tempDir = NSTemporaryDirectory() + tempDirSuffix
        do {
            // 如果目标路径的文件夹未事先创建，则直接创建文件夹
            var isDirectory: ObjCBool = false
            let dirIsExists = FileManager.default.fileExists(atPath: tempDir,
                                                             isDirectory: &isDirectory)
            if !(isDirectory.boolValue && dirIsExists) {
                try FileManager.default.createDirectory(at: URL(fileURLWithPath: tempDir),
                                                        withIntermediateDirectories: true)
            } else {
                
            }
        } catch {
            
        }
    }
    
    
    /// 将进度条回调添加到缓存
    ///
    /// - Parameters:
    ///   - targetRequest: 对应的请求
    ///   - progress: 进度回调闭包
    ///   - callbackToken: 闭包对应的token
    private func addProgressBlockToMap(_ targetRequest: LGDataRequest,
                                       progress: @escaping LGWebImageProgressBlock,
                                       callbackToken: LGWebImageCallbackToken)
    {
        _ = _lock.wait(timeout: DispatchTime.distantFuture)
        if var tempDic = progressBlocksMap[targetRequest] {
            tempDic[callbackToken] = progress
            progressBlocksMap[targetRequest] = tempDic
        } else {
            progressBlocksMap[targetRequest] = [callbackToken: progress]
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
        if let tempDic = self.progressBlocksMap[request] {
            if tempDic.count > 0 {
                for (_, block) in tempDic {
                    block(progress)
                }
            }
        }
        _ = _lock.signal()
    }
    
    /// 将完成回调添加到缓存
    ///
    /// - Parameters:
    ///   - targetRequest: 对应的request
    ///   - completion: 完成回调闭包
    ///   - callbackToken: 闭包对应的token
    private func addCompletionBlocksToMap(_ targetRequest: LGDataRequest,
                                          completion: @escaping LGWebImageCompletionBlock,
                                          callbackToken: LGWebImageCallbackToken)
    {
        _ = _lock.wait(timeout: DispatchTime.distantFuture)
        if var tempDic = completionBlocksMap[targetRequest] {
            tempDic[callbackToken] = completion
            completionBlocksMap[targetRequest] = tempDic
        } else {
            completionBlocksMap[targetRequest] = [callbackToken: completion]
        }
        _ = _lock.signal()
    }
    
    /// 调用完成回调
    ///
    /// - Parameters:
    ///   - request: 对应的request
    ///   - image: 图片内容
    ///   - url: 图片原文件地址
    ///   - sourceType: 图片现在的来源
    ///   - imageStatus: 图片现在的状态
    ///   - error: 过程出现的error
    private func invokeCompletionBlocks(_ request: LGDataRequest,
                                        image: UIImage?,
                                        url: URL?,
                                        sourceType: LGWebImageSourceType,
                                        imageStatus: LGWebImageStage,
                                        error: Error?)
    {
        _ = _lock.wait(timeout: DispatchTime.distantFuture)
        if let tempDic = self.completionBlocksMap[request] {
            if tempDic.count > 0 {
                for (_, block) in tempDic {
                    block(image, url, sourceType, imageStatus, error)
                }
            }
        }
        _ = _lock.signal()
    }
    
    /// 根据对应的request清理各个container
    ///
    /// - Parameters:
    ///   - targetRequest: 对应的request
    ///   - urlNSSString: 图片原始地址
    private func clearMaps(_ targetRequest: LGDataRequest, urlNSSString: NSString) {
        _ = self._lock.wait(timeout: DispatchTime.distantFuture)
        self.requestContainer.removeObject(forKey: urlNSSString)
        self.progressBlocksMap.removeValue(forKey: targetRequest)
        self.completionBlocksMap.removeValue(forKey: targetRequest)
        self.progressiveContainerMap.removeValue(forKey: targetRequest)
        _ = self._lock.signal()
    }
    
    /// progressive或者progressiveBlur方式展示图片解码，如果图片超过1MB，则会直接返回，不执行此操作
    ///
    /// - Parameters:
    ///   - data: 图片的原始data
    ///   - options: 解码属性设置
    ///   - targetRequest: 对应的请求
    private func decodeDataToUIImageIfNeeded(_ data: Data,
                                             options: LGWebImageOptions,
                                             targetRequest: LGDataRequest)
    {
        // 图片解码会占用大量内存，如果大于1MB则直接不进行处理
        if targetRequest.expectedContentLength >= _maxFileSize {
            return
        }
        
        let progressive = options.contains(LGWebImageOptions.progressive)
        let progressiveBlur = options.contains(LGWebImageOptions.progressiveBlur)
        
        if !(progressiveBlur || progressive) {
            return
        }
        
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
        
        let writedData = data
        
        // 不够解码长度
        if writedData.count <= 16 {
            return
        }
        
        var progressiveDecoder = progressiveContainer.progressiveDecoder
        if progressiveDecoder == nil {
            progressiveDecoder = LGImageDecoder(withScale: UIScreen.main.scale)
            progressiveContainer.progressiveDecoder = progressiveDecoder
            progressiveContainerMap[targetRequest] = progressiveContainer
        }
        _ = progressiveDecoder?.updateData(data: writedData, final: false)
        
        // webp 和其它未知格式无法进行扫描显示
        if progressiveDecoder?.imageType == LGImageType.unknow ||
            progressiveDecoder?.imageType == LGImageType.webp ||
            progressiveDecoder?.imageType == LGImageType.other {
            progressiveDecoder = nil
            progressiveContainer.progressiveIgnored = true
            progressiveContainerMap[targetRequest] = progressiveContainer
            return
        }
        
        if progressiveBlur {
            // 只支持 png & jpg
            if !(progressiveDecoder?.imageType == LGImageType.jpeg ||
                progressiveDecoder?.imageType == LGImageType.png) {
                progressiveDecoder = nil
                progressiveContainer.progressiveIgnored = true
                progressiveContainerMap[targetRequest] = progressiveContainer
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
                            progressiveContainerMap[targetRequest] = progressiveContainer
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
                progressiveContainerMap[targetRequest] = progressiveContainer
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
                    progressiveContainerMap[targetRequest] = progressiveContainer
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
            progressiveContainerMap[targetRequest] = progressiveContainer
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
    }
    
    /// 通过token取消回调，但不会取消下载
    ///
    /// - Parameter callbackToken: 某次请求对应的token
    public func cancelWith(callbackToken: LGWebImageCallbackToken) {
        _cacheQueue.async(flags: DispatchWorkItemFlags.barrier) { [unowned self] in
            _ = self._lock.wait(timeout: DispatchTime.distantFuture)
            for (key, value) in self.progressBlocksMap {
                for (token, _) in value {
                    if token == callbackToken {
                        self.progressBlocksMap[key]?[token] = nil
                    }
                }
            }
            
            for (key, value) in self.completionBlocksMap {
                for (token, _) in value {
                    if token == callbackToken {
                        self.completionBlocksMap[key]?[token] = nil
                    }
                }
            }
            _ = self._lock.signal()
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
