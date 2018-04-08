//
//  LGWebImageDownloadSessionManager.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2017/11/30.
//  Copyright © 2017年 龚杰洪. All rights reserved.
//

import Foundation


public class LGWebImageDownloadSessionManager {
    
    open var downloadTasks: [URLSessionDownloadTask] {
        var tasks: [URLSessionDownloadTask] = [URLSessionDownloadTask]()
        
        /// 加锁，强行异步变同步
        let lock = DispatchSemaphore(value: 1)
        
        session.getTasksWithCompletionHandler { (dataTasks, uploadTasks, downloadTasks) in
            tasks = downloadTasks
            _ = lock.signal()
        }
        
        _ = lock.wait(timeout: DispatchTime.distantFuture)
        return tasks
    }
    open private(set) var session: URLSession
    
    private var progressBlock: LGWebImageProgressBlock?
    private var transformBlock: LGWebImageTransformBlock?
    private var completedBlock: LGWebImageCompletionBlock?
    
    public private(set) var response: HTTPURLResponse?
    public private(set) var cache: LGImageCache = LGImageCache.shared
    public private(set) var cacheKey: String?
    public private(set) var options: LGWebImageOptions = LGWebImageOptions.default
    
    private var lock: NSRecursiveLock = NSRecursiveLock()
    
    public var credential: URLCredential?
    
    public lazy var downloadQueue: OperationQueue = {
        let temp = OperationQueue()
        temp.maxConcurrentOperationCount = 1
        temp.name = "com.lgwebimage.download.queue"
        temp.qualityOfService = QualityOfService.background
        return temp
    }()
    
    public init(sessionConfig: URLSessionConfiguration?, options: LGWebImageOptions) {
        var tempConfig: URLSessionConfiguration
        if nil == sessionConfig {
            tempConfig = URLSessionConfiguration.default
            tempConfig.timeoutIntervalForRequest = 15.0
        } else {
            tempConfig = sessionConfig!
        }
        
        if options.contains(LGWebImageOptions.refreshImageCache) {
            tempConfig.requestCachePolicy = URLRequest.CachePolicy.reloadIgnoringCacheData
        } else {
            tempConfig.requestCachePolicy = URLRequest.CachePolicy.reloadIgnoringLocalAndRemoteCacheData
        }
        
        self.session = URLSession(configuration: tempConfig,
                                  delegate: self,
                                  delegateQueue: downloadQueue)
    }
    
//    public init(request: LGWebImageURLRequestConvertible,
//                options: LGWebImageOptions,
//                cache: LGImageCache = LGImageCache.shared,
//                progress: LGWebImageProgressBlock? = nil,
//                transform: LGWebImageTransformBlock? = nil,
//                completion: LGWebImageCompletionBlock? = nil) throws {
//
//        self.request = try request.asURLRequest()
//        self.request.httpShouldHandleCookies = options.contains(LGWebImageOptions.handleCookies)
//        self.cache = cache
//
//        let sessionConfig = URLSessionConfiguration.default
//
//        if options.contains(LGWebImageOptions.refreshImageCache) {
//            sessionConfig.requestCachePolicy = URLRequest.CachePolicy.reloadIgnoringCacheData
//        } else {
//            sessionConfig.requestCachePolicy = URLRequest.CachePolicy.reloadIgnoringLocalAndRemoteCacheData
//        }
//
//        // 15秒请求超时时间
//        sessionConfig.timeoutIntervalForRequest = 15
//        self.session = URLSession(configuration: sessionConfig,
//                                  delegate: self,
//                                  delegateQueue: downloadQueue)
//
//        self.progressBlock = progress
//        self.transformBlock = transform
//        self.completedBlock = completion
//
//        self.downloadTask = self.session.downloadTask(with: self.request!)
//    }
    
    
    fileprivate var receivedData: Data = Data()
    fileprivate var expectedReceiveSize: Int64 = Int64.max
    
    fileprivate var lastProgressiveDecodeTimestamp: TimeInterval = 0.0
    fileprivate var progressiveDecoder: LGImageDecoder?
    fileprivate var progressiveIgnored: Bool = false
    fileprivate var progressiveDetected: Bool = false
    fileprivate var progressiveScanedLength: Int = 0
    fileprivate var progressiveDisplayCount: Int = 0
}

class LGWebImageDownloadSessionDataDelegate: NSObject, URLSessionDataDelegate {
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                           didFinishDownloadingTo location: URL) {
        
    }
    
    public func urlSession(_ session: URLSession,
                           dataTask: URLSessionDataTask,
                           didReceive response: URLResponse,
                           completionHandler: @escaping (URLSession.ResponseDisposition) -> Swift.Void) {
        
        if let httpResponse = response as? HTTPURLResponse {
            let expectedRecieve = httpResponse.expectedContentLength == 0 ? INT64_MAX : httpResponse.expectedContentLength
            self.expectedReceiveSize = expectedRecieve
            let statCode = httpResponse.statusCode
            if statCode != 304 && statCode < 400 {
                self.response = httpResponse
                receivedData = Data()
            }
            else if statCode == 416 {
                // 超出资源range
                self.done()
            }
            else if statCode == 304 {
                // 需要重新请求，直接放弃
                self.done()
            }
            else {
                
            }
        }
        else {
            
        }
        completionHandler(URLSession.ResponseDisposition.allow)
    }
    
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if self.isCancelled {
            return
        }
        receivedData.append(data)
        if let progress = self.progressBlock {
            progress(Int64(receivedData.count), self.expectedReceiveSize)
        }
        
        let progressive = options.contains(LGWebImageOptions.progressive)
        let progressiveBlur = options.contains(LGWebImageOptions.progressiveBlur)
        
        if completedBlock == nil || !(progressiveBlur || progressive) {
            return
        }
        
        // 不够解码长度
        if data.count <= 16 {
            return
        }
        
        // 数据足够长且马上要下载完成了，不再继续处理
        if expectedReceiveSize > 0 && data.count >= Int64(Double(expectedReceiveSize) * 0.99) {
            return
        }
        // 忽略则不处理
        if progressiveIgnored { return }
        
        let min: TimeInterval = progressiveBlur ? .minProgressiveBlurTimeInterval : .minProgressiveTimeInterval
        let now = CACurrentMediaTime()
        if now - lastProgressiveDecodeTimestamp < min {
            return
        }
        if progressiveDecoder == nil {
            progressiveDecoder = LGImageDecoder(withScale: UIScreen.main.scale)
        }
        _ = progressiveDecoder?.updateData(data: receivedData, final: false)
        if self.isCancelled {return}
        
        // webp 和其它未知格式无法进行扫描显示
        if progressiveDecoder?.imageType == LGImageType.unknow ||
            progressiveDecoder?.imageType == LGImageType.webp ||
            progressiveDecoder?.imageType == LGImageType.other {
            progressiveDecoder = nil
            progressiveIgnored = true
            return
        }
        
        if progressiveBlur {
            // 只支持 png & jpg
            if !(progressiveDecoder?.imageType == LGImageType.jpeg ||
                progressiveDecoder?.imageType == LGImageType.png) {
                progressiveDecoder = nil
                progressiveIgnored = true
                return
            }
        }
        
        
        if progressiveDecoder?.frameCount == 0 {return}
        
        if !progressiveBlur {
            let frame = progressiveDecoder?.frameAtIndex(index: 0, decodeForDisplay: true)
            if frame?.image != nil {
                if !self.isCancelled {
                    if let comp = self.completedBlock {
                        comp(frame?.image,
                             request?.url,
                             LGWebImageSourceType.remoteServer,
                             LGWebImageStage.progress,
                             nil)
                    }
                }
            }
            return
        } else {
            if progressiveDecoder?.imageType == LGImageType.jpeg {
                if !progressiveDetected {
                    if let dic = progressiveDecoder?.frameProperties(atIndex: 0) {
                        let jpeg = dic[kCGImagePropertyJFIFIsProgressive as String] as? [String: Any]
                        if let isProg = jpeg?[kCGImagePropertyJFIFIsProgressive as String] as? NSNumber {
                            if !isProg.boolValue {
                                progressiveIgnored = true
                                progressiveDecoder = nil
                                return
                            }
                            progressiveDetected = true
                        }
                        
                    }
                    
                }
                let scanLength = receivedData.count - progressiveScanedLength - 4
                if scanLength <= 2 {return}
                let endIndex = Data.Index(progressiveScanedLength + scanLength)
                let scanRange: Range<Data.Index> = Data.Index(progressiveScanedLength)..<endIndex
                let markerRange = receivedData.range(of: JPEGSOSMarker,
                                                     options: Data.SearchOptions.backwards,
                                                     in: scanRange)
                progressiveScanedLength = receivedData.count
                if markerRange == nil {return}
                if self.isCancelled {return}
            } else if progressiveDecoder?.imageType == LGImageType.png {
                if !progressiveDetected {
                    let dic = progressiveDecoder?.frameProperties(atIndex: 0)
                    let png = dic?[kCGImagePropertyPNGDictionary as String] as? [String: Any]
                    let isProg = png?[kCGImagePropertyPNGInterlaceType as String] as? NSNumber
                    if isProg != nil && !isProg!.boolValue {
                        progressiveIgnored = true
                        progressiveDecoder = nil
                        return
                    }
                    progressiveDetected = true
                }
            }
            
            let frame = progressiveDecoder?.frameAtIndex(index: 0, decodeForDisplay: true)
            guard let image = frame?.image else {
                return
            }
            if self.isCancelled {return}
            if image.cgImage?.lastPixelFilled() == false {
                return
            }
            
            progressiveDisplayCount += 1
            var radius: CGFloat = 32
            if expectedReceiveSize > 0 {
                radius *= 1.0 / (3.0 * CGFloat(receivedData.count) / CGFloat(expectedReceiveSize) + 0.6) - 0.25
            } else {
                radius /= CGFloat(progressiveDisplayCount)
            }
            let temp = image.lg_imageByBlurRadius(radius,
                                                  tintColor: nil,
                                                  tintBlendMode: CGBlendMode.normal,
                                                  saturation: 1, maskImage: nil)
            if temp != nil {
                if !isCancelled {
                    if let comp = self.completedBlock {
                        comp(temp, request?.url, LGWebImageSourceType.remoteServer, LGWebImageStage.progress, nil)
                        lastProgressiveDecodeTimestamp = now
                    };
                }
            }
        }
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error != nil {
            
        } else {
            
        }
    }
    
    public func urlSession(_ session: URLSession,
                           dataTask: URLSessionDataTask,
                           willCacheResponse proposedResponse: CachedURLResponse,
                           completionHandler: @escaping (CachedURLResponse?) -> Void) {
        if options.contains(LGWebImageOptions.useURLCache) {
            completionHandler(proposedResponse)
        } else {
            completionHandler(nil)
        }
    }
}

class LGWebImageDownloadSessionDelegate: URLSessionDelegate {
    
    weak var manager: LGWebImageDownloadSessionManager?
    
    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        guard let completedBlock = self.completedBlock else {
            return
        }
        let errorDes = "session did become invalid \(error?.localizedDescription ?? "")"
        let fatalError = LGWebImageDownloaderError.errorWith(code: LGWebImageDownloaderError.ErrorCode.sessionInvalid,
                                                             description: errorDes)
        
        completedBlock(nil,
                       self.request?.url,
                       LGWebImageSourceType.none,
                       LGWebImageStage.finished,
                       fatalError)
    }
    
    public func urlSession(_ session: URLSession,
                           didReceive challenge: URLAuthenticationChallenge,
                           completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            if options.contains(LGWebImageOptions.allowInvalidSSLCertificates) {
                let credential = URLCredential(trust: challenge.protectionSpace.serverTrust!)
                completionHandler(URLSession.AuthChallengeDisposition.useCredential, credential)
            } else {
                completionHandler(URLSession.AuthChallengeDisposition.performDefaultHandling, nil)
            }
        } else {
            if challenge.previousFailureCount == 1 {
                if self.credential != nil {
                    completionHandler(URLSession.AuthChallengeDisposition.useCredential, self.credential)
                } else {
                    completionHandler(URLSession.AuthChallengeDisposition.performDefaultHandling, nil)
                }
            } else {
                completionHandler(URLSession.AuthChallengeDisposition.performDefaultHandling, nil)
            }
        }
    }
    
    //    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    //
    //    }
}

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
    
    func isContains(url: LGWebImageURLConvertible) -> Bool {
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
    
    func addURL(_ url: LGWebImageURLConvertible) {
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


