//
//  LGCacheItem.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2017/9/15.
//  Copyright © 2017年 龚杰洪. All rights reserved.
//

import Foundation

public protocol LGDataConvertible {
    func asData() -> Data
}

public struct LGCacheItem {
    public var data: LGDataConvertible
    public var extendedData: LGDataConvertible?
    
    public init(data: LGDataConvertible, extendedData: LGDataConvertible?) {
        self.data = data
        self.extendedData = extendedData
    }
}

extension String: LGDataConvertible {
    public func asData() -> Data {
        return self.data(using: String.Encoding.utf8) ?? Data()
    }
}

extension UIImage: LGDataConvertible {
    public func asData() -> Data {
        return lg_imageDataRepresentation ?? Data()
    }
}

extension Data: LGDataConvertible {
    public func asData() -> Data {
        return self
    }
}

extension CGFloat: LGDataConvertible {
    public func asData() -> Data {
        return NSKeyedArchiver.archivedData(withRootObject: self)
    }
}
