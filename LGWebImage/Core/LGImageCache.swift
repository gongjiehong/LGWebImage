//
//  LGImageCache.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2017/10/15.
//  Copyright © 2017年 龚杰洪. All rights reserved.
//

import Foundation

public struct LGImageCacheType: OptionSet {
    public var rawValue: Int
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    public static let none: LGImageCacheType = {
        return LGImageCacheType(rawValue: 0)
    }()
    
    public static let disk: LGImageCacheType = {
        return LGImageCacheType(rawValue: 1 << 0)
    }()
    
    public static let memory: LGImageCacheType = {
        return LGImageCacheType(rawValue: 1 << 1)
    }()
    
    public static let all: LGImageCacheType = {
        return [LGImageCacheType.disk, LGImageCacheType.memory]
    }()
    
    public static let `default`: LGImageCacheType = {
        return LGImageCacheType.all
    }()
}



public class LGImageCache {
    public var name: String?
    public private(set) var memoryCache: LGMemoryCache
    public private(set) var diskCache: LGDiskCache
    
    public var isAllowAnimatedImage: Bool = true
    public var isDecodeForDisplay: Bool = true
    
    public static let `default`: LGImageCache = {
        var cachePath = FileManager.lg_cacheDirectoryPath
        cachePath += "/com.lgwebimage.caches"
        cachePath += "/images"
        return LGImageCache(cachePath: cachePath)
    }()
    
    public init(cachePath path: String) {
        let memoryCache = LGMemoryCache()
        
        /// 12（小时） * 60（分） * 60（秒）
        memoryCache.ageLimit = 12 * 60 * 60
        
        /// 物理内存的百分之五用作缓存内存缓存
        memoryCache.costLimit = Int(Double(ProcessInfo().physicalMemory) * 0.05)
        
        let diskCache = LGDiskCache(path: path)
        // 最大占用1GB磁盘 1024 * 1024 * 1024
        diskCache.costLimit = 1_024 * 1_024 * 1_024
        // 最多存储30天，30天 * 24小时 * 60分 * 60秒
        diskCache.ageLimit = 2_592_000
        self.memoryCache = memoryCache
        self.diskCache = diskCache
    }
    
    public func setImage(image: UIImage?,
                         imageData: Data? = nil,
                         forKey key: String,
                         withType type: LGImageCacheType = LGImageCacheType.default)
    {
        if (image == nil && imageData == nil) || key.lg_length == 0 {
            return
        }
        
        if type.contains(LGImageCacheType.memory) {
            if image != nil {
                if image!.lg_isDecodedForDisplay {
                    self.memoryCache.setObject(LGCacheItem(data: image!, extendedData: nil),
                                               forKey: key,
                                               withCost: image!.imageCost)
                } else {
                    lg_imageCacheIOQueue.async { [weak self] in
                        self?.memoryCache.setObject(LGCacheItem(data: image!.lg_imageByDecoded, extendedData: nil),
                                                    forKey: key,
                                                    withCost: image!.imageCost)
                    }
                }
            } else if imageData != nil {
                let workItem = DispatchWorkItem(qos: DispatchQoS.utility,
                                                flags: DispatchWorkItemFlags.barrier)
                { [weak self] in
                    guard let weakSelf = self else {
                        return
                    }
                    if let newImage = UIImage.imageFrom(cacheItem: LGCacheItem(data: image!, extendedData: nil),
                                                        isAllowAnimatedImage: weakSelf.isAllowAnimatedImage,
                                                        isDecodeForDisplay: weakSelf.isDecodeForDisplay) {
                        weakSelf.memoryCache.setObject(LGCacheItem(data: newImage, extendedData: nil),
                                                       forKey: key,
                                                       withCost: newImage.imageCost)
                    }
                }
                lg_imageCacheDecodeQueue.async(execute: workItem)
            }
        }
        
        if type.contains(LGImageCacheType.disk) {
            if imageData != nil {
                if image != nil {
                    let cacheItem = LGCacheItem(data: imageData!, extendedData: image!.scale)
                    self.diskCache.setObject(cacheItem, forKey: key)
                }
            } else if image != nil {
                lg_imageCacheIOQueue.async { [weak self] in
                    guard let weakSelf = self else {
                        return
                    }
                    if let data = image?.lg_imageDataRepresentation {
                        let cacheItem = LGCacheItem(data: data, extendedData: image!.scale)
                        weakSelf.diskCache.setObject(cacheItem, forKey: key)
                    }
                    
                }
            }
        }
    }
    
    public func getImage(forKey key: String, withType type: LGImageCacheType = LGImageCacheType.default) -> UIImage?
    {
        if key.lg_length == 0 {
            return nil
        }
        if type.contains(LGImageCacheType.memory) {
            if let imageItem = self.memoryCache.object(forKey: key) {
                return imageItem.data as? UIImage
            }
        }
        if type.contains(LGImageCacheType.disk) {
            if let imageItem = self.diskCache.object(forKey: key) {
                let image = UIImage.imageFrom(cacheItem: imageItem,
                                              isAllowAnimatedImage: isAllowAnimatedImage,
                                              isDecodeForDisplay: isDecodeForDisplay)
                if image != nil {
                    self.memoryCache.setObject(LGCacheItem(data: image!, extendedData: imageItem.extendedData),
                                               forKey: key,
                                               withCost: image!.imageCost)
                }
                return image
            } else {
                return nil
            }
            
        }
        return nil
    }
    
    public func getImage(forKey key: String,
                         withType type: LGImageCacheType,
                         andBlock block: @escaping (UIImage?, LGImageCacheType) -> Void) {
        DispatchQueue.global(qos: DispatchQoS.QoSClass.utility).async {
            var image: UIImage? = nil
            if type.contains(LGImageCacheType.memory) {
                if let cacheItem = self.memoryCache.object(forKey: key) {
                    image = UIImage.imageFrom(cacheItem: cacheItem,
                                              isAllowAnimatedImage: self.isAllowAnimatedImage,
                                              isDecodeForDisplay: self.isDecodeForDisplay)
                    if image != nil {
                        DispatchQueue.main.async {
                            block(image, LGImageCacheType.memory)
                        }
                        return
                    }
                }
                
            }
            if type.contains(LGImageCacheType.disk) {
                if let cacheItem = self.diskCache.object(forKey: key) {
                    image = UIImage.imageFrom(cacheItem: cacheItem,
                                              isAllowAnimatedImage: self.isAllowAnimatedImage,
                                              isDecodeForDisplay: self.isDecodeForDisplay)
                    if image != nil {
                        self.memoryCache.setObject(LGCacheItem(data: image!, extendedData: cacheItem.extendedData),
                                                   forKey: key,
                                                   withCost: image!.imageCost)
                        DispatchQueue.main.async {
                            block(image, LGImageCacheType.disk)
                        }
                        return
                    }
                    
                }
                
            }
            DispatchQueue.main.async {
                block(nil, LGImageCacheType.none)
            }
        }
    }
    
    public func getImageData(forKey key: String) -> Data? {
        return self.diskCache.object(forKey: key)?.data.asData()
    }
    
    public func getImageData(forKey key: String, withBlock block: @escaping (Data?) -> Void) {
        DispatchQueue.global(qos: DispatchQoS.QoSClass.userInitiated).async {
            let data = self.diskCache.object(forKey: key)?.data.asData()
            DispatchQueue.main.async {
                block(data)
            }
        }
    }
    
    public func removeImage(forKey key: String, withType type: LGImageCacheType = LGImageCacheType.default) {
        if type.contains(LGImageCacheType.memory) {
            self.memoryCache.removeObject(forKey: key)
        }
        if type.contains(LGImageCacheType.disk) {
            self.diskCache.removeObject(forKey: key)
        }
    }
    
    public func containsImage(forKey key: String,
                              withType type: LGImageCacheType = LGImageCacheType.default) -> Bool
    {
        if type.contains(LGImageCacheType.memory) {
            return self.memoryCache.containsObject(forKey: key) == true
        }
        if type.contains(LGImageCacheType.disk) {
            return self.diskCache.containsObject(forKey: key) == true
        }
        return false
    }
    
    subscript(key: String) -> UIImage? {
        set {
            if newValue != nil {
                self.setImage(image: newValue!, forKey: key)
            } else {
                self.removeImage(forKey: key)
            }
        }
        get {
            return self.getImage(forKey: key)
        }
    }
    
    public func clearMemoryCache() {
        self.memoryCache.removeAllObjects()
    }
    
    public func clearDiskCache(withBlock block: (() -> Void)?) {
        self.diskCache.removeAllObjects(withBlock: block)
    }
    
    /// 清理内存缓存和磁盘缓存，磁盘缓存会在异步线程中清理
    public func clearAllCache(withBlock block: (() -> Void)?) {
        self.clearMemoryCache()
        self.clearDiskCache(withBlock: block)
    }
}

extension UIImage {
    var imageCost: Int {
        if let cgImage = self.cgImage {
            let height = cgImage.height
            let bytesPerRow = cgImage.bytesPerRow
            var cost = height * bytesPerRow
            if cost == 0 {
                cost = 1
            }
            return cost
        } else {
            return 1
        }
    }
    
    class func imageFrom(cacheItem: LGCacheItem,
                         isAllowAnimatedImage: Bool,
                         isDecodeForDisplay: Bool) -> UIImage? {
        if let image = cacheItem.data as? UIImage {
            return image.lg_imageByDecoded
        }
        let scaleData = cacheItem.extendedData
        var scale: CGFloat = 0
        if scaleData != nil {
            scale = NSKeyedUnarchiver.unarchiveObject(with: scaleData!.asData()) as? CGFloat ?? 0.0
        }
        if scale <= 0 {
            scale = UIScreen.main.scale
        }
        
        var result: UIImage?
        
        if isAllowAnimatedImage {
            result = LGImage.imageWith(data: cacheItem.data.asData(), scale: scale)
            if isDecodeForDisplay {
                result = result?.lg_imageByDecoded
            }
        } else {
            do {
                let decoder = try LGImageDecoder(withData: cacheItem.data.asData(), scale: scale)
                result = decoder.frameAtIndex(index: 0, decodeForDisplay: isDecodeForDisplay)?.image
            } catch {
                
            }
        }
        return result
    }
}

fileprivate let lg_imageCacheIOQueue = DispatchQueue.global(qos: DispatchQoS.QoSClass.userInitiated)
fileprivate let lg_imageCacheDecodeQueue = DispatchQueue.global(qos: DispatchQoS.QoSClass.utility)
