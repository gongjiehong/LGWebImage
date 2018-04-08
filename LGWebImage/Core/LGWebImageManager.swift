//
//  LGWebImageManager.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2017/10/16.
//  Copyright © 2017年 龚杰洪. All rights reserved.
//

import Foundation
import LGHTTPRequest

class LGWebImageDownloadRequest: LGDownloadRequest {
    
}

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
    
    public func requestImageWith(url: LGURLConvertible, options: LGWebImageOptions, progress: LGProgressHandler) {
        do {
            let remoteURL = try url.asURL()
            let urlString = remoteURL.absoluteString
            let urlNSSString = NSString(string: urlString)
            if let request = requestContainer.object(forKey: urlNSSString) as? LGDownloadRequest {
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


fileprivate class LGWebImageApplicationNetworkIndicatorInfo {
    
    static let shared: LGWebImageApplicationNetworkIndicatorInfo = {
        return LGWebImageApplicationNetworkIndicatorInfo()
    }()
    
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
