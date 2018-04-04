//
//  LGWebImageDefins.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2017/10/16.
//  Copyright © 2017年 龚杰洪. All rights reserved.
//

import Foundation

public struct LGWebImageOptions: OptionSet {
    public var rawValue: Int
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    public static let showNetworkActivity: LGWebImageOptions = {
        return LGWebImageOptions(rawValue: 1 << 0)
    }()
    
    public static let progressive: LGWebImageOptions = {
        return LGWebImageOptions(rawValue: 1 << 1)
    }()
    
    public static let progressiveBlur: LGWebImageOptions = {
        return LGWebImageOptions(rawValue: 1 << 2)
    }()
    
    public static let useURLCache: LGWebImageOptions = {
        return LGWebImageOptions(rawValue: 1 << 3)
    }()
    
    public static let allowBackgroundTask: LGWebImageOptions = {
        return LGWebImageOptions(rawValue: 1 << 4)
    }()
    
    public static let allowInvalidSSLCertificates: LGWebImageOptions = {
        return LGWebImageOptions(rawValue: 1 << 5)
    }()
    
    public static let handleCookies: LGWebImageOptions = {
        return LGWebImageOptions(rawValue: 1 << 6)
    }()
    
    public static let refreshImageCache: LGWebImageOptions = {
        return LGWebImageOptions(rawValue: 1 << 7)
    }()
    
    public static let ignoreDiskCache: LGWebImageOptions = {
        return LGWebImageOptions(rawValue: 1 << 8)
    }()
    
    public static let ignorePlaceHolder: LGWebImageOptions = {
        return LGWebImageOptions(rawValue: 1 << 9)
    }()
    
    public static let ignoreImageDecoding: LGWebImageOptions = {
        return LGWebImageOptions(rawValue: 1 << 10)
    }()
    
    public static let ignoreAnimatedImage: LGWebImageOptions = {
        return LGWebImageOptions(rawValue: 1 << 11)
    }()
    
    public static let setImageWithFadeAnimation: LGWebImageOptions = {
        return LGWebImageOptions(rawValue: 1 << 12)
    }()
    
    public static let avoidSetImage: LGWebImageOptions = {
        return LGWebImageOptions(rawValue: 1 << 13)
    }()
    
    public static let ignoreFailedURL: LGWebImageOptions = {
        return LGWebImageOptions(rawValue: 1 << 14)
    }()
    
    public static let `default`: LGWebImageOptions = {
        return [LGWebImageOptions.setImageWithFadeAnimation, LGWebImageOptions.allowBackgroundTask]
    }()
}

public enum LGWebImageSourceType {
    case none
    case memoryCacheFase
    case memoryCache
    case diskCache
    case remoteServer
}

public enum LGWebImageStage {
    case progress
    case cancelled
    case finished
}

public extension TimeInterval {
    public static let minProgressiveTimeInterval: TimeInterval = {
        return 0.2
    }()
    
    public static let minProgressiveBlurTimeInterval: TimeInterval = {
        return 0.4
    }()
}

public var JPEGSOSMarker: Data {
    return Data(bytes: [0xFF, 0xDA])
}




