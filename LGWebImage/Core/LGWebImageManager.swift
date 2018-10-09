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
    /// 请求容器，用于存储当前活跃的请求，避免重复下载同一个文件
    public var requestContainer: LGThreadSafeDictionary<String, LGDataRequest>
    
    /// 图片缓存工具
    public var cache: LGImageCache
    
    public var workQueue: DispatchQueue {
        return _cacheQueue
    }
    
    /// 处理队列
    fileprivate var _cacheQueue = DispatchQueue(label: "com.LGWebImageManager.cacheQueue",
                                                qos: DispatchQoS.utility,
                                                attributes: DispatchQueue.Attributes.concurrent,
                                                autoreleaseFrequency: DispatchQueue.AutoreleaseFrequency.inherit,
                                                target: DispatchQueue.utility)
    
    /// 下载URLSession管理器
    fileprivate var _sessionManager: LGURLSessionManager
    
    /// 大图的最大字节数，这里设置为1MB，超过1MB不处理渐进显示，在显示的时候根据屏幕大小生成缩略图进行展示
    fileprivate let _maxFileSize: UInt64 = 1_024 * 1_024
    
    private typealias ProgressBlockMapItem = [LGWebImageCallbackToken: LGWebImageProgressBlock]
    private typealias CompletionBlockMapItem = [LGWebImageCallbackToken: LGWebImageCompletionBlock]
    
    private var progressBlocksMap = LGThreadSafeDictionary<LGDataRequest, ProgressBlockMapItem>()
    private var completionBlocksMap = LGThreadSafeDictionary<LGDataRequest, CompletionBlockMapItem>()
    private var progressiveContainerMap = LGThreadSafeDictionary<LGDataRequest, LGWebImageProgressiveContainer>()
    
    private var tokenValidMap = LGThreadSafeDictionary<LGWebImageCallbackToken, Bool>()
    
    private let tempDirSuffix = "LGWebImage/TempFile/"
    
    /// 根据一些选项设置和信任的host进行初始化
    ///
    /// - Parameters:
    ///   - options: 固定设置
    ///   - trustHosts: 信任的host，设置后不会验证SSL有效性
    public init(options: LGWebImageOptions = LGWebImageOptions.default, trustHosts: [String] = []) {
        requestContainer = LGThreadSafeDictionary<String, LGDataRequest>()
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
                                  transform: LGWebImageTransformBlock? = nil,
                                  completion: LGWebImageCompletionBlock? = nil) -> LGWebImageCallbackToken
    {
        let token = UUID().uuidString + "\(CACurrentMediaTime())"
        
        
        tokenValidMap[token] = true
        
        
        _cacheQueue.async { [unowned self] in
            // 处理忽略下载失败的URL和和名单
            if options.contains(LGWebImageOptions.ignoreFailedURL) &&
                LGURLBlackList.default.isContains(url: url)
            {
                if self.tokenValidMap[token] == true {
                    completion?(nil,
                                nil,
                                LGWebImageSourceType.none,
                                LGWebImageStage.cancelled,
                                LGImageDownloadError.urlIsInTheBlackList(url: url))
                }
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
                
                if self.tokenValidMap[token] != true {
                    return
                }
                
                if var image = self.cache.getImage(forKey: urlString, withType: cacheType) {
                    if let transformBlock = transform {
                        if let temp = transformBlock(image, remoteURL) {
                            image = temp
                        }
                    }
                    if self.tokenValidMap[token] == true {
                        completion?(image,
                                    remoteURL,
                                    LGWebImageSourceType.memoryCacheFast,
                                    LGWebImageStage.finished,
                                    nil)
                    }
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
                var targetRequest: LGDataRequest?
                let request = self.requestContainer[urlString]
                if request != nil {
                    targetRequest = request
                } else {
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
                        
                        inputStream.schedule(in: RunLoop.current, forMode: RunLoop.Mode.default)
                        outputStream.schedule(in: RunLoop.current, forMode: RunLoop.Mode.default)
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
                        
                        inputStream.remove(from: RunLoop.current, forMode: RunLoop.Mode.default)
                        outputStream.remove(from: RunLoop.current, forMode: RunLoop.Mode.default)
                        
                        inputStream.close()
                        outputStream.close()
                        
                        guard let weakTargetRequest = targetRequest else {
                            return
                        }
                        if self.tokenValidMap[token] != true {
                            return
                        }
                        self.decodeDataToUIImageIfNeeded(receivedData,
                                                         options: options,
                                                         targetRequest: weakTargetRequest,
                                                         transform: transform)
                    })

                    /**
                     ** 处理进度回调
                     **/
                    targetRequest = targetRequest!.downloadProgress(queue: self._cacheQueue)
                    {[unowned self] (progress) in
                        guard let targetRequest = targetRequest else {return}
                        self.invokeProgressBlocks(targetRequest, progress: progress)
                    }

                    // 下载完成结果处理
                    targetRequest = targetRequest!.validate().response(queue: self._cacheQueue)
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
                                    if var image: UIImage = LGImage.imageWith(data: receivedData) {
                                        self.cache.memoryCache.setObject(LGCacheItem(data: image,
                                                                                     extendedData: nil),
                                                                         forKey: originURL.absoluteString,
                                                                         withCost: image.imageCost)
                                        if let transformBlock = transform {
                                            if let temp = transformBlock(image, remoteURL) {
                                                image = temp
                                            }
                                        }
                                        self.invokeCompletionBlocks(weakTargetRequest,
                                                                    image: image,
                                                                    url: originURL,
                                                                    sourceType: LGWebImageSourceType.memoryCacheFast,
                                                                    imageStatus: LGWebImageStage.finished,
                                                                    error: nil)
                                    } else if var image = self.cache.getImage(forKey: originURL.absoluteString,
                                                                              withType: LGImageCacheType.disk)
                                    {
                                        if let transformBlock = transform {
                                            if let temp = transformBlock(image, remoteURL) {
                                                image = temp
                                            }
                                        }
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
                                            if var image = decoder.largePictureCreateThumbnail() {
                                                self.cache.setImage(image: image, forKey: originURL.absoluteString)
                                                if let transformBlock = transform {
                                                    if let temp = transformBlock(image, remoteURL) {
                                                        image = temp
                                                    }
                                                }
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
                        self.clearMaps(targetRequest!, urlString: urlString)
                        networkIndicatorStop()
                        targetRequest = nil
                    }
                    
                    self.requestContainer[urlString] = targetRequest
                    
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
        if var tempDic = progressBlocksMap[targetRequest] {
            tempDic[callbackToken] = progress
            progressBlocksMap[targetRequest] = tempDic
        } else {
            progressBlocksMap[targetRequest] = [callbackToken: progress]
        }
    }
    
    /// 处理进度条回调
    ///
    /// - Parameters:
    ///   - request: 目标请求
    ///   - progress: Progress
    private func invokeProgressBlocks(_ request: LGDataRequest, progress: Progress) {
        if let tempDic = self.progressBlocksMap[request] {
            if tempDic.count > 0 {
                for (token, block) in tempDic {
                    let tokenIsValid = (tokenValidMap[token] == true)
                    if tokenIsValid {
                        block(progress)
                    }
                }
            }
        }
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
        if var tempDic = completionBlocksMap[targetRequest] {
            tempDic[callbackToken] = completion
            completionBlocksMap[targetRequest] = tempDic
        } else {
            completionBlocksMap[targetRequest] = [callbackToken: completion]
        }
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
        if let tempDic = self.completionBlocksMap[request] {
            if tempDic.count > 0 {
                for (token, block) in tempDic {
                    let tokenIsValid = (tokenValidMap[token] == true)
                    if tokenIsValid {
                        block(image, url, sourceType, imageStatus, error)
                    }
                }
            }
        }
    }
    
    /// 根据对应的request清理各个container
    ///
    /// - Parameters:
    ///   - targetRequest: 对应的request
    ///   - urlNSSString: 图片原始地址
    private func clearMaps(_ targetRequest: LGDataRequest, urlString: String) {
        self.requestContainer.removeValue(forKey: urlString)
        self.progressBlocksMap.removeValue(forKey: targetRequest)
        self.completionBlocksMap.removeValue(forKey: targetRequest)
        self.progressiveContainerMap.removeValue(forKey: targetRequest)
    }
    
    /// progressive或者progressiveBlur方式展示图片解码，如果图片超过1MB，则会直接返回，不执行此操作
    ///
    /// - Parameters:
    ///   - data: 图片的原始data
    ///   - options: 解码属性设置
    ///   - targetRequest: 对应的请求
    private func decodeDataToUIImageIfNeeded(_ data: Data,
                                             options: LGWebImageOptions,
                                             targetRequest: LGDataRequest,
                                             transform: LGWebImageTransformBlock? = nil)
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
            if var tempImage = frame?.image {
                if let transformBlock = transform {
                    if let temp = transformBlock(tempImage, targetRequest.request?.url) {
                        tempImage = temp
                    }
                }
                self.invokeCompletionBlocks(targetRequest,
                                            image: tempImage,
                                            url: targetRequest.request?.url,
                                            sourceType: LGWebImageSourceType.remoteServer,
                                            imageStatus: LGWebImageStage.progress,
                                            error: nil)
            }
            return
        } else {
            if progressiveDecoder?.imageType == LGImageType.jpeg {
//                if !progressiveContainer.progressiveDetected {
//                    if let dic = progressiveDecoder?.frameProperties(atIndex: 0) {
//                        let jpeg = dic[kCGImagePropertyJFIFDictionary as String] as? [String: Any]
//                        if let isProg = jpeg?[kCGImagePropertyJFIFIsProgressive as String] as? NSNumber {
//                            if !isProg.boolValue {
//                                progressiveContainer.progressiveIgnored = true
//                                progressiveContainer.progressiveDecoder = nil
//                                progressiveContainerMap[targetRequest] = progressiveContainer
//                                return
//                            }
//                        } else {
//                            progressiveContainer.progressiveIgnored = true
//                            progressiveContainer.progressiveDecoder = nil
//                            progressiveContainerMap[targetRequest] = progressiveContainer
//                            return
//                        }
                        progressiveContainer.progressiveDetected = true
                        progressiveContainerMap[targetRequest] = progressiveContainer
//                    }
//                }
                let scanLength = writedData.count - progressiveContainer.progressiveScanedLength - 4
                if scanLength <= 2 {return}
                let endIndex = Data.Index(progressiveContainer.progressiveScanedLength + scanLength)
                let scanRange: Range<Data.Index> = Data.Index(progressiveContainer.progressiveScanedLength)..<endIndex
                let markerRange = writedData.range(of: JPEGSOSMarker,
                                                   options: Data.SearchOptions(rawValue: 0),
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
            
            if image.cgImage?.lastPixelFilled() != true {
                return
            }
            
            progressiveContainer.progressiveDisplayCount += 1
            progressiveContainerMap[targetRequest] = progressiveContainer
            var radius: CGFloat = 32
            if targetRequest.expectedContentLength > 0 {
                radius *= 1.0 / (3.0 * CGFloat(writedData.count) /
                    CGFloat(targetRequest.expectedContentLength) + 0.6) - 0.25
            } else {
                radius /= CGFloat(progressiveContainer.progressiveDisplayCount)
            }
            var temp = image.lg_imageByBlurRadius(radius,
                                                  tintColor: nil,
                                                  tintBlendMode: CGBlendMode.normal,
                                                  saturation: 1,
                                                  maskImage: nil)
            if temp != nil {
                if let transformBlock = transform {
                    if let tempImage = transformBlock(temp, targetRequest.request?.url) {
                        temp = tempImage
                    }
                }
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
        tokenValidMap[callbackToken] = nil
        
        for (key, value) in self.progressBlocksMap {
            for (token, _) in value {
                if token == callbackToken {
                    self.progressBlocksMap[key]?[token] = nil
                    key.cancel()
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
            let dir = NSTemporaryDirectory() + self.tempDirSuffix
            do {
                try FileManager.default.removeItem(at: URL(fileURLWithPath: dir))
                self.createTempFileDirIfNeeded()
                clearCacheMark += 1
            } catch {
                clearCacheMark += 1
            }
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
        if let cfData = self.dataProvider?.data {
            let dataLength = CFDataGetLength(cfData)
            if let buffer = CFDataGetBytePtr(cfData) {
                let lastByte = buffer[dataLength - 1]
                return lastByte != 0
            }
            return false
        } else {
            return false
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
