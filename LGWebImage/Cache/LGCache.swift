//
//  LGCache.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2017/9/15.
//  Copyright © 2017年 龚杰洪. All rights reserved.
//

import Foundation

public class LGCache<KeyType: Hashable, ValueType: LGCacheItem> {
    public private(set) var name: String = ""
    
    public private(set) var memoryCache: LGMemoryCache<KeyType, ValueType>
    
    public private(set) var diskCache: LGDiskCache<KeyType, ValueType>
    
    public convenience init(withName name: String) {
        assert(name.lg_length > 0, "缓存名字不合法")
        let path = FileManager.lg_cacheDirectoryPath + name
        self.init(withPath: path)
    }
    
    public init(withPath path: String) {
        assert(path.lg_length > 0, "缓存路径不合法")
        let name = NSString(string: path).lastPathComponent
        
        let diskCacheConfig = LGDiskConfig(name: "LGCache.Disk.\(name)",
                                           directory: URL(fileURLWithPath: path))
        let diskCache = LGDiskCache<KeyType, ValueType>.cache(withConfig: diskCacheConfig)
        
        let memoryCacheConfig = LGMemoryConfig(name: "LGCache.Memory.\(name)")
        let memoryCache = LGMemoryCache<KeyType, ValueType>(config: memoryCacheConfig)
        
        self.diskCache = diskCache
        self.memoryCache = memoryCache
        self.name = "LGCache.\(name)"
    }
    
    public func containsObject(forKey key: KeyType) -> Bool {
        return memoryCache.containsObject(forKey: key) || diskCache.containsObject(forKey: key)
    }
    
    public func containsObject(forKey key: KeyType, withBlock block: ((_ key: KeyType, _ contains: Bool) -> Void)?) {
        guard let tempBlock = block else {
            return
        }
        if memoryCache.containsObject(forKey: key) {
            DispatchQueue.global(qos: DispatchQoS.QoSClass.userInitiated).async {
                tempBlock(key, true)
            }
        } else {
            diskCache.containsObject(forKey: key, withBlock: block)
        }
    }
    
    public func object(forKey key: KeyType) -> ValueType? {
        if let objcet = memoryCache.object(forKey: key) {
            return objcet
        } else {
            if let object = diskCache.object(forKey: key) {
                memoryCache.setObject(object, forKey: key)
                return object
            } else {
                return nil
            }
        }
    }
    
    public func object(forKey key: KeyType, withBlock block: ((KeyType, ValueType?) -> Void)?) {
        guard let tempBlock = block else {
            return
        }
        if let objcet = memoryCache.object(forKey: key) {
            DispatchQueue.global(qos: DispatchQoS.QoSClass.userInitiated).async {
                tempBlock(key, objcet)
            }
        } else {
            diskCache.object(forKey: key, withBlock: {[weak self] (itemKey, item) in
                guard let weakSelf = self else {
                    return
                }
                if item != nil && !weakSelf.memoryCache.containsObject(forKey: itemKey) {
                    weakSelf.memoryCache.setObject(item, forKey: itemKey)
                }
                tempBlock(itemKey, item)
            })
        }
        
    }
    
    public func setObject(_ object: ValueType?, forKey key: KeyType) {
        memoryCache.setObject(object, forKey: key)
        diskCache.setObject(object, forKey: key)
    }
    
    public func setObject(_ object: ValueType?, forKey key: KeyType, withBlock block: (() -> Void)?) {
        memoryCache.setObject(object, forKey: key)
        diskCache.setObject(object, forKey: key, withBlock: block)
    }
    
    public func removeObject(forKey key: KeyType) {
        memoryCache.removeObject(forKey: key)
        diskCache.removeObject(forKey: key)
    }

    
    public func removeObject(forKey key: KeyType, withBlock block: ((KeyType) -> Void)?) {
        memoryCache.removeObject(forKey: key)
        diskCache.removeObject(forKey: key, withBlock: block)
    }
    
    public func removeAllObjects() {
        memoryCache.removeAllObjects()
        diskCache.removeAllObjects()
    }
    
    public func removeAllObjects(withBlock block: (() -> Void)?) {
        memoryCache.removeAllObjects()
        diskCache.removeAllObjects(withBlock: block)
    }
    
    public func removeAllObjects(withProgressBlock progressBlock: ((_ removedCount: Int, _ totalCount: Int) -> Void)?,
                                 endBlock: ((_ error: Bool) -> Void)?) {
        memoryCache.removeAllObjects()
        diskCache.removeAllObjects(withProgressBlock: progressBlock, endBlock: endBlock)
    }
}
