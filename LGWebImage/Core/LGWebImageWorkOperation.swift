//
//  LGWebImageWorkOperation.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2018/9/14.
//  Copyright © 2018年 龚杰洪. All rights reserved.
//

import UIKit
import LGHTTPRequest

public class LGWebImageWorkOperation: Operation {
    private var _isFinished: Bool = false
    public override var isFinished: Bool {
        get {
            lock.lock()
            defer {
                lock.unlock()
            }
            return _isFinished
        } set {
            lock.lock()
            defer {
                lock.unlock()
            }
            if _isFinished != newValue {
                willChangeValue(forKey: "isFinished")
                _isFinished = newValue
                didChangeValue(forKey: "isFinished")
            }
        }
    }
    
    private var _isCancelled: Bool = false
    public override var isCancelled: Bool {
        get {
            lock.lock()
            defer {
                lock.unlock()
            }
            return _isCancelled
        }
        set {
            lock.lock()
            defer {
                lock.unlock()
            }
            if _isCancelled != newValue {
                willChangeValue(forKey: "isCancelled")
                _isCancelled = newValue
                didChangeValue(forKey: "isCancelled")
            }
        }
    }
    
    private var _isExecuting: Bool = false
    public override var isExecuting: Bool {
        get{
            lock.lock()
            defer {
                lock.unlock()
            }
            return _isExecuting
        }
        set {
            lock.lock()
            defer {
                lock.unlock()
            }
            
            if _isExecuting != newValue {
                willChangeValue(forKey: "isExecuting")
                _isExecuting = newValue
                didChangeValue(forKey: "isExecuting")
            }
        }
    }
    
    public override var isConcurrent: Bool {
        return true
    }
    
    public override var isAsynchronous: Bool {
        return true
    }
    
    private var isStarted: Bool = false
    private var lock: NSRecursiveLock = NSRecursiveLock()
    private var taskId: UIBackgroundTaskIdentifier = UIBackgroundTaskIdentifier.invalid
    /// 大图的最大字节数，这里设置为1MB，超过1MB不处理渐进显示，在显示的时候根据屏幕大小生成缩略图进行展示
    private let maxFileSize: UInt64 = 1_024 * 1_024
    
    
    weak var request: LGStreamDownloadRequest?
    weak var imageCache: LGImageCache?
    var progress: LGWebImageProgressBlock?
    var completion: LGWebImageCompletionBlock?
    var options: LGWebImageOptions = LGWebImageOptions.default
    var url: LGURLConvertible = ""
    
    public init(withURL url: LGURLConvertible,
                options: LGWebImageOptions = LGWebImageOptions.default,
                imageCache: LGImageCache?,
                progress: LGWebImageProgressBlock? = nil,
                completion: LGWebImageCompletionBlock? = nil)
    {
        super.init()
        self.url = url
        self.options = options
        self.progress = progress
        self.completion = completion
        self.imageCache = imageCache
    }
    
    public override func start() {
        lock.lock()
        defer {
            lock.unlock()
        }
        
        isStarted = true
        
        if isCancelled {
            cancelOperation()
            isFinished = true
        } else if isReady, !isFinished, !isExecuting {
            self.isExecuting = true
            var localReadFinished: Bool = false
            getImageFromLoacal(finished: &localReadFinished)
            if localReadFinished {
                finish()
            } else {
                downloadImageFromRemote()
            }
        }
    }
    
    
    func getImageFromLoacal(finished: inout Bool) {
        // 处理忽略下载失败的URL和和名单
        if options.contains(LGWebImageOptions.ignoreFailedURL) &&
            LGURLBlackList.default.isContains(url: url)
        {
            if !isCancelled {
                println("cancel")
                self.invokeCompletionOnMainThread(nil,
                                                  remoteURL: nil,
                                                  sourceType: LGWebImageSourceType.none,
                                                  imageStage: LGWebImageStage.cancelled,
                                                  error: LGImageDownloadError.urlIsInTheBlackList(url: url))
            }
            finished = true
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
            
            if isCancelled {
                finished = true
                return
            }
            
            if let imageCache = self.imageCache, let image = imageCache.getImage(forKey: urlString,
                                                                                 withType: cacheType)
            {
                if isCancelled {
                    finished = true
                    println("cancel")
                    return
                }
                
                self.invokeCompletionOnMainThread(image,
                                                  remoteURL: remoteURL,
                                                  sourceType: LGWebImageSourceType.memoryCacheFast,
                                                  imageStage: LGWebImageStage.finished,
                                                  error: nil)
                networkIndicatorStop()
                finished = true
                return
            }
        }
        catch {
            println(error)
            networkIndicatorStop()
            println("cancel")
        }
    }
    
    
    private var temporaryURL: URL?
    
    private var destinationURL: URL?
    
    func downloadImageFromRemote() {
        let request = LGURLSessionManager.default.streamDownload(self.url,
                                                                 method: LGHTTPMethod.get,
                                                                 parameters: nil,
                                                                 encoding: LGURLEncoding.default,
                                                                 headers: nil,
                                                                 to: nil)
        self.request = request
        request.validate().downloadProgress(queue: DispatchQueue.utility) { [weak self] (progress) in
            guard let weakSelf = self  else {return}
            if weakSelf.isCancelled || weakSelf.isFinished {
                return
            }
            
            if let receivedData = weakSelf.request?.delegate.receivedData {
                weakSelf.decodeDataToUIImageIfNeeded(receivedData)
            }
            
            DispatchQueue.main.async { [weak self] in
                guard let weakSelf = self  else {return}
                if let progressBlock = weakSelf.progress {
                    progressBlock(progress)
                }
            }
        }
        
        request.validate().responseData(queue: DispatchQueue.utility) { [weak self] (response) in
            guard let weakSelf = self  else {return}
            if weakSelf.isCancelled || weakSelf.isFinished {
                return
            }
            
            weakSelf.downloadCompleteProcessor(response)
        }
        self.temporaryURL = request.temporaryURL
        self.destinationURL = request.destinationURL
    }
    
    func downloadCompleteProcessor(_ response: LGHTTPDataResponse<Data>){
        if let error = response.error {
            self.invokeCompletionOnMainThread(nil,
                                              remoteURL: nil,
                                              sourceType: .none,
                                              imageStage: .finished,
                                              error: error)
        } else {
            if let originURL = response.request?.url
            {
                guard let destinationURL = self.destinationURL,
                    let imageCache = self.imageCache,
                    let receivedData = response.value else {
                        println("returned")
                        return
                }
                
                func checkNormalImage() {
                    // 通过拷贝文件的方式设置磁盘缓存
                    self.imageCache?.diskCache.setObject(withFileURL: destinationURL,
                                                         forKey: originURL.absoluteString)
                    
                    // 首先直接对data进行解码，解码不成功再说后续
                    if let image: UIImage = LGImage.imageWith(data: receivedData) {
                        imageCache.memoryCache.setObject(LGCacheItem(data: image,
                                                                     extendedData: nil),
                                                         forKey: originURL.absoluteString,
                                                         withCost: image.imageCost)
                        self.invokeCompletionOnMainThread(image,
                                                          remoteURL: originURL,
                                                          sourceType: LGWebImageSourceType.memoryCacheFast,
                                                          imageStage: LGWebImageStage.finished,
                                                          error: nil)
                    } else if let image = imageCache.getImage(forKey: originURL.absoluteString,
                                                              withType: LGImageCacheType.all)
                    {
                        self.invokeCompletionOnMainThread(image,
                                                          remoteURL: originURL,
                                                          sourceType: LGWebImageSourceType.memoryCacheFast,
                                                          imageStage: LGWebImageStage.finished,
                                                          error: nil)
                    } else {
                        if options.contains(LGWebImageOptions.ignoreFailedURL) {
                            LGURLBlackList.default.addURL(url)
                        }
                        self.invokeCompletionOnMainThread(nil,
                                                          remoteURL: originURL,
                                                          sourceType: LGWebImageSourceType.none,
                                                          imageStage: LGWebImageStage.finished,
                                                          error: LGImageDownloadError.cannotReadFile)
                    }
                }
                
                if UInt64(receivedData.count) > self.maxFileSize &&
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
                                imageCache.setImage(image: image, forKey: originURL.absoluteString)
                                self.invokeCompletionOnMainThread(image,
                                                                  remoteURL: originURL,
                                                                  sourceType: LGWebImageSourceType.memoryCacheFast,
                                                                  imageStage: LGWebImageStage.finished,
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
                let error = LGImageDownloadError.targetURLOrOriginURLInvalid(targetURL: self.destinationURL,
                                                                             originURL: originalURL)
                self.invokeCompletionOnMainThread(nil,
                                                  remoteURL: nil,
                                                  sourceType: LGWebImageSourceType.none,
                                                  imageStage: LGWebImageStage.finished,
                                                  error: error)
            }
        }
        networkIndicatorStop()
    }
    
    
    func invokeCompletionOnMainThread(_ image: UIImage?,
                                      remoteURL: URL?,
                                      sourceType: LGWebImageSourceType,
                                      imageStage: LGWebImageStage,
                                      error: Error?)
    {

        guard let completion = self.completion else {return}
        DispatchQueue.main.async { [weak self] in
            completion(image,
                       remoteURL,
                       sourceType,
                       imageStage,
                       error)
            guard let weakSelf = self else {return}
            if imageStage != .progress {
                weakSelf.finish()
            }
        }
    }
    
    
    private var progressiveDecoder: LGImageDecoder?
    private var progressiveIgnored: Bool = false
    private var lastProgressiveDecodeTimestamp: TimeInterval = CACurrentMediaTime()
    private var progressiveDetected = false
    private var progressiveScanedLength: Int = 0
    private var progressiveDisplayCount: Int = 0
    
    private func decodeDataToUIImageIfNeeded(_ data: Data) {
        // 图片解码会占用大量内存，如果大于1MB则直接不进行处理
        if let targetRequest = self.request, targetRequest.expectedContentLength >= maxFileSize {
            return
        }
        
        let progressive = options.contains(LGWebImageOptions.progressive)
        let progressiveBlur = options.contains(LGWebImageOptions.progressiveBlur)
        
        if !(progressiveBlur || progressive) {
            return
        }
        
        // 数据足够长且马上要下载完成了，不再继续处理
        if let targetRequest = self.request, targetRequest.progress.fractionCompleted > 0.9 {
            return
        }
        
        // 忽略则不处理
        var progressiveIgnored: Bool = self.progressiveIgnored
        
        if progressiveIgnored == true { return }
        
        let min: TimeInterval = progressiveBlur ? .minProgressiveBlurTimeInterval : .minProgressiveTimeInterval
        let now = CACurrentMediaTime()
        if now - lastProgressiveDecodeTimestamp < min {
            return
        }
        
        let writedData = data
        
        // 不够解码长度
        if writedData.count <= 16 {
            return
        }
        
        if progressiveDecoder == nil {
            progressiveDecoder = LGImageDecoder(withScale: UIScreen.main.scale)
        }
        
        if isCancelled {
            return
        }
        _ = progressiveDecoder?.updateData(data: writedData, final: false)
        
        // webp 和其它未知格式无法进行扫描显示
        if progressiveDecoder?.imageType == LGImageType.unknow ||
            progressiveDecoder?.imageType == LGImageType.webp ||
            progressiveDecoder?.imageType == LGImageType.other {
            progressiveDecoder = nil
            self.progressiveIgnored = true
            return
        }
        
        if progressiveBlur {
            // 只支持 png & jpg
            if !(progressiveDecoder?.imageType == LGImageType.jpeg ||
                progressiveDecoder?.imageType == LGImageType.png) {
                progressiveDecoder = nil
                self.progressiveIgnored = true
                return
            }
        }
        
        
        if progressiveDecoder?.frameCount == 0 {return}
        
        if !progressiveBlur {
            if isCancelled {
                return
            }
            let frame = progressiveDecoder?.frameAtIndex(index: 0, decodeForDisplay: true)
            if let tempImage = frame?.image {
                self.invokeCompletionOnMainThread(tempImage,
                                                  remoteURL: self.request?.request?.url,
                                                  sourceType: LGWebImageSourceType.remoteServer,
                                                  imageStage: LGWebImageStage.progress,
                                                  error: nil)
            }
            return
        } else {
            if progressiveDecoder?.imageType == LGImageType.jpeg {
                if isCancelled {
                    return
                }
                if !self.progressiveDetected {
                    if let dic = progressiveDecoder?.frameProperties(atIndex: 0) {
                        let jpeg = dic[kCGImagePropertyJFIFDictionary as String] as? [String: Any]
                        if let isProg = jpeg?[kCGImagePropertyJFIFIsProgressive as String] as? NSNumber {
                            if !isProg.boolValue {
                                self.progressiveIgnored = true
                                self.progressiveDecoder = nil
                                return
                            }
                        } else {
                            self.progressiveIgnored = true
                            self.progressiveDecoder = nil
                            return
                        }
                        self.progressiveDetected = true
                    }
                }
                let scanLength = writedData.count - self.progressiveScanedLength - 4
                if scanLength <= 2 {return}
                let endIndex = Data.Index(self.progressiveScanedLength + scanLength)
                let scanRange: Range<Data.Index> = Data.Index(self.progressiveScanedLength)..<endIndex
                let markerRange = writedData.range(of: JPEGSOSMarker,
                                                   options: Data.SearchOptions(rawValue: 0),
                                                   in: scanRange)
                self.progressiveScanedLength = writedData.count
                if markerRange == nil {return}
            } else if progressiveDecoder?.imageType == LGImageType.png {
                if isCancelled {
                    return
                }
                if !self.progressiveDetected {
                    let dic = progressiveDecoder?.frameProperties(atIndex: 0)
                    let png = dic?[kCGImagePropertyPNGDictionary as String] as? [String: Any]
                    let isProg = png?[kCGImagePropertyPNGInterlaceType as String] as? NSNumber
                    if isProg != nil && !isProg!.boolValue {
                        progressiveIgnored = true
                        progressiveDecoder = nil
                        return
                    }
                    self.progressiveDetected = true
                }
            }
            
            if isCancelled {
                return
            }
            let frame = progressiveDecoder?.frameAtIndex(index: 0, decodeForDisplay: true)
            guard let image = frame?.image else {
                return
            }
            
            if isCancelled {
                return
            }
            if image.cgImage?.lastPixelFilled() != true {
                return
            }
            
            self.progressiveDisplayCount += 1
            var radius: CGFloat = 32
            if let targetRequest = self.request, targetRequest.expectedContentLength > 0 {
                radius *= 1.0 / (3.0 * CGFloat(writedData.count) /
                    CGFloat(targetRequest.expectedContentLength) + 0.6) - 0.25
            } else {
                radius /= CGFloat(self.progressiveDisplayCount)
            }
            
            if isCancelled {
                return
            }
            let temp = image.lg_imageByBlurRadius(radius,
                                                  tintColor: nil,
                                                  tintBlendMode: CGBlendMode.normal,
                                                  saturation: 1,
                                                  maskImage: nil)
            
            if let tempImage = temp {
                self.invokeCompletionOnMainThread(tempImage,
                                                  remoteURL: self.request?.request?.url,
                                                  sourceType: LGWebImageSourceType.remoteServer,
                                                  imageStage: LGWebImageStage.progress,
                                                  error: nil)
            }
        }
    }
    
    public override func cancel() {
        lock.lock()
        defer {
            lock.unlock()
        }
        
        if !isCancelled {
            super.cancel()
            isCancelled = true
            
            if isExecuting {
                isExecuting = false
            }
            cancelOperation()
        }
        
        if isStarted {
            isFinished = true
        }
    }
    
    override public class func automaticallyNotifiesObservers(forKey key: String) -> Bool {
        if key == "isExecuting" || key == "isFinished" || key == "isCancelled" {
            return false
        } else {
            return super.automaticallyNotifiesObservers(forKey: key)
        }
    }
    
    // MARK: - private
    
    func finish() {
        isExecuting = false
        isFinished = true
        endBackgroundTask()
    }
    
    private func cancelOperation() {
        autoreleasepool { () -> Void in
//            if let _ = self.completion {
//                self.invokeCompletionOnMainThread(nil,
//                                                  remoteURL: self.request?.request?.url,
//                                                  sourceType: LGWebImageSourceType.none,
//                                                  imageStage: LGWebImageStage.cancelled,
//                                                  error: nil)
//
//            }
            
            endBackgroundTask()
            
            // 物理内存小于1GB，真取消，大于1GB，只是取消当前工作，不取消下载
            if UIDevice.physicalMemory <= 1_073_741_824 {
                self.request?.cancel()
            }
        }
    }
    
    private func endBackgroundTask() {
        lock.lock()
        defer {
            lock.unlock()
        }
        
        if self.taskId != UIBackgroundTaskIdentifier.invalid {
            UIApplication.shared.endBackgroundTask(self.taskId)
            self.taskId = UIBackgroundTaskIdentifier.invalid
        }
    }
    
    // MARK: - 销毁
    deinit {
        lock.lock()
        defer {
            lock.unlock()
        }
        
        if isExecuting {
            cancelOperation()
            isCancelled = true
            isFinished = true
        }
//        println("LGWebImageWorkOperation deinit")
    }
}

fileprivate extension UIDevice {
    static let physicalMemory: UInt64 = {
        return ProcessInfo().physicalMemory
    }()
}

// MARK: - 填充最后个像素
extension CGImage {
    public func lastPixelFilled() -> Bool {
        if let cfData = self.dataProvider?.data {
            let dataLength = CFDataGetLength(cfData)
            if let buffer = CFDataGetBytePtr(cfData), dataLength >= 1 {
                let lastByte = buffer[dataLength - 1]
                return lastByte == 0
            }
            return false
        } else {
            return false
        }
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
