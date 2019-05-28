//
//  LGCacheItem.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2017/9/15.
//  Copyright © 2017年 龚杰洪. All rights reserved.
//

import Foundation

// MARK: - LGCacheItem
/// 缓存对象，包含主要数据和附加数据，附加数据可以为空
/// 附件数据可以用户存储图片缩放信息等内容
public final class LGCacheItem {
    public var data: LGDataConvertible
    public var extendedData: LGDataConvertible?
    public var time: TimeInterval
    
    public init(data: LGDataConvertible, extendedData: LGDataConvertible?, time: TimeInterval = CACurrentMediaTime()) {
        self.data = data
        self.extendedData = extendedData
        self.time = time
    }
}

extension LGCacheItem: LGMemoryCost {
    public func memoryCost() -> UInt64 {
        return self.data.memoryCost() + (self.extendedData?.memoryCost() ?? 0)
    }
}

// MARK: - LGDataConvertible
public protocol LGDataConvertible: LGMemoryCost {
    /// 将内存数据转换为Data，用户写入持久化存储
    ///
    /// - Returns: 转换后的Data
    func asData() -> Data
    
    /// 通过转换后的Data创建对象
    ///
    /// - Parameter data: 转换后的Data
    /// - Returns: 生成的对象，如果不能正常转换则会返回nil
    static func createWith(convertedData data: Data) -> Self?
}

public protocol LGMemoryCost {
    /// 获取实际内存占用大小，结果可能稍有偏差
    ///
    /// - Returns: 实际占用大小
    func memoryCost() -> UInt64
}

// MARK: - 协议实现
extension String: LGDataConvertible {
    public func memoryCost() -> UInt64 {
        return UInt64(self.lengthOfBytes(using: String.Encoding.utf8))
    }
    
    public static func createWith(convertedData data: Data) -> String? {
        return String(data: data, encoding: String.Encoding.utf8)
    }
    
    public func asData() -> Data {
        return self.data(using: String.Encoding.utf8) ?? Data()
    }

}

extension UIImage: LGDataConvertible {
    @objc public func memoryCost() -> UInt64 {
        guard let cgImage = self.cgImage else {
            return 1
        }
        return UInt64(cgImage.bytesPerRow * cgImage.height)
    }
    
    @objc public class func createWith(convertedData data: Data) -> Self? {
        return self.init(data: data)
    }
    
    @objc public func asData() -> Data {
        return lg_imageDataRepresentation ?? Data()
    }
}

extension LGImage {
    override public func memoryCost() -> UInt64 {
        var dataCost: Int = self.animatedImageData?.count ?? 1
        dataCost += animatedImageMemorySize
        return UInt64(dataCost)
    }
    
    override public class func createWith(convertedData data: Data) -> LGImage? {
        return LGImage.imageWith(data: data)
    }
    
    override public func asData() -> Data {
        return super.asData()
    }
}

extension Data: LGDataConvertible {
    public func memoryCost() -> UInt64 {
        return UInt64(self.count)
    }
    
    public static func createWith(convertedData data: Data) -> Data? {
        return data
    }
    
    public func asData() -> Data {
        return self
    }
}

extension CGFloat: LGDataConvertible {
    public func memoryCost() -> UInt64 {
        return UInt64(MemoryLayout.stride(ofValue: self))
    }
    
    public static func createWith(convertedData data: Data) -> CGFloat? {
        return data.withUnsafeBytes({ (pointer) -> CGFloat in
            pointer.load(as: CGFloat.self)
        })
    }
    
    public func asData() -> Data {
        var value = self
        let data = withUnsafeBytes(of: &value) {
            Data($0)
        }
        return data
    }
}

extension Double: LGDataConvertible {
    public func memoryCost() -> UInt64 {
        return UInt64(MemoryLayout.stride(ofValue: self))
    }
    
    public static func createWith(convertedData data: Data) -> Double? {
        return data.withUnsafeBytes({ (pointer) -> Double in
            pointer.load(as: Double.self)
        })
    }
    
    public func asData() -> Data {
        var value = self
        let data = withUnsafeBytes(of: &value) {
            Data($0)
        }
        return data
    }
}

extension Int: LGDataConvertible {
    public func memoryCost() -> UInt64 {
        return UInt64(MemoryLayout.stride(ofValue: self))
    }
    
    public static func createWith(convertedData data: Data) -> Int? {
        return data.withUnsafeBytes({ (pointer) -> Int in
            pointer.load(as: Int.self)
        })
    }
    
    public func asData() -> Data {
        var value = self
        let data = withUnsafeBytes(of: &value) {
            Data($0)
        }
        return data
    }
}

extension Float: LGDataConvertible {
    public func memoryCost() -> UInt64 {
        return UInt64(MemoryLayout.stride(ofValue: self))
    }
    
    public static func createWith(convertedData data: Data) -> Float? {
        return data.withUnsafeBytes({ (pointer) -> Float in
            pointer.load(as: Float.self)
        })
    }
    
    public func asData() -> Data {
        var value = self
        let data = withUnsafeBytes(of: &value) {
            Data($0)
        }
        return data
    }
}

