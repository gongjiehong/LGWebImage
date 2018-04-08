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
    
    public init() {
        requestContainer = NSMapTable<NSString, LGHTTPRequest>(keyOptions: NSPointerFunctions.Options.strongMemory,
                                                               valueOptions: NSPointerFunctions.Options.weakMemory)
        cache = LGImageCache.shared
    }
    
    public static let `default`: LGWebImageManager = {
       return LGWebImageManager()
    }()
    
    private var progressBlocksArray = [LGDownloadRequest: [LGWebImageTransformBlock]]()
    
    public func downloadImageWith(url: LGURLConvertible,
                                  options: LGWebImageOptions,
                                  progress: @escaping LGWebImageProgressBlock,
                                  transform: @escaping LGWebImageTransformBlock,
                                  completion: @escaping LGWebImageCompletionBlock)
    {
        do {
            let remoteURL = try url.asURL()
            let urlString = remoteURL.absoluteString
            let urlNSSString = NSString(string: urlString)
            if let request = requestContainer.object(forKey: urlNSSString) as? LGDownloadRequest {
                request.downloadProgress(queue: DispatchQueue.userInitiated, closure: progress)
                request.validate().response(queue: DispatchQueue.userInitiated) { (response) in
                }
            } else {
                let request = LGURLSessionManager.default.download(url)
                requestContainer.setObject(request, forKey: urlNSSString)
                request.validate().response(queue: DispatchQueue.userInitiated) { (response) in
                }
            }
            
        } catch {
            println(error)
        }
    }
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
