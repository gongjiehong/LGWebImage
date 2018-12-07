//
//  LGWebImageOperationSetter.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2018/12/7.
//  Copyright © 2018年 龚杰洪. All rights reserved.
//

import Foundation
import LGHTTPRequest

internal class LGWebImageOperationSetter {
    private var _imageURL: LGURLConvertible?
    var imageURL: LGURLConvertible? {
        _ = lock.wait(timeout: DispatchTime.distantFuture)
        defer {
            _ = lock.signal()
        }
        return _imageURL
    }
    
    typealias Sentinel = Int64
    
    private var _sentinel: Sentinel = 0
    var sentinel: Sentinel {
        _ = lock.wait(timeout: DispatchTime.distantFuture)
        defer {
            _ = lock.signal()
        }
        return _sentinel
    }
    
    private let lock = DispatchSemaphore(value: 1)
    private weak var operation: LGWebImageOperation?
    
    init() {
    }
    
    func setOperation(with sentinel: Sentinel,
                      URL url: LGURLConvertible,
                      options: LGWebImageOptions = LGWebImageOptions.default,
                      manager: LGWebImageManager = LGWebImageManager.default,
                      progress: LGWebImageProgressBlock? = nil,
                      completion: LGWebImageCompletionBlock? = nil) -> Sentinel
    {
        var tempSentinel = sentinel
        if (tempSentinel != _sentinel) {
            if let completion = completion {
                completion(nil, try? url.asURL(), LGWebImageSourceType.none, LGWebImageStage.cancelled, nil)
            }
            return _sentinel
        }
        
        let result = manager.downloadImageWith(url: url,
                                               options: options,
                                               progress: progress,
                                               completion: completion)
        _ = lock.wait(timeout: DispatchTime.distantFuture)
        defer {
            _ = lock.signal()
        }
        if tempSentinel == _sentinel {
            if self.operation != nil {
                self.operation?.cancel()
            }
            self.operation = result.operation
            tempSentinel = OSAtomicIncrement64(&_sentinel)
        } else {
            result.operation.cancel()
        }
        return tempSentinel
    }
    
    @discardableResult
    func cancel(withNewURL url: LGURLConvertible? = nil) -> Sentinel {
        var tempSentinel: Sentinel
        _ = lock.wait(timeout: DispatchTime.distantFuture)
        defer {
            _ = lock.signal()
        }
        
        if self.operation != nil {
            self.operation?.cancel()
            self.operation = nil
        }
        
        _imageURL = url
        tempSentinel = OSAtomicIncrement64(&_sentinel)
        return tempSentinel
    }
    
    static let setterQueue: DispatchQueue = {
        let queue = DispatchQueue(label: "cxylg.LGWebImageOperationSetter.setterQueue")
        return queue
    }()
    
    deinit {
        OSAtomicIncrement64(&_sentinel)
        if let operation = self.operation {
            operation.cancel()
        }
    }
}

