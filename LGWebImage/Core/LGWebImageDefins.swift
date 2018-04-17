//
//  LGWebImageDefins.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2017/10/16.
//  Copyright © 2017年 龚杰洪. All rights reserved.
//

import Foundation
import LGHTTPRequest

/// 穷举处理过程中的一些选项
public struct LGWebImageOptions: OptionSet {
    
    /// 原始值
    public var rawValue: Int
    
    /// 通过原始值初始化
    ///
    /// - Parameter rawValue: 原始值，Int类型
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    /// 显示顶部状态栏的网络请求菊花
    public static let showNetworkActivity: LGWebImageOptions = {
        return LGWebImageOptions(rawValue: 1 << 0)
    }()
    
    /// 渐进显示
    public static let progressive: LGWebImageOptions = {
        return LGWebImageOptions(rawValue: 1 << 1)
    }()
    
    /// 渐进模糊
    public static let progressiveBlur: LGWebImageOptions = {
        return LGWebImageOptions(rawValue: 1 << 2)
    }()
    
    /// 允许断点续传，注意：本库使用(Range: bytes = *-*)实现（["Range": "bytes=*-*"]），请确定服务器是否支持Range协议
    /// Range: bytes=0-499 表示第 0-499 字节范围的内容
    /// Range: bytes=500-999 表示第 500-999 字节范围的内容
    /// Range: bytes=-500 表示最后 500 字节的内容
    /// Range: bytes=500- 表示从第 500 字节开始到文件结束部分的内容
    /// Range: bytes=0-0,-1 表示第一个和最后一个字节
    /// Range: bytes=500-600,601-999 同时指定几个范围
    public static let enableBreakpointPass: LGWebImageOptions = {
        return LGWebImageOptions(rawValue: 1 << 3)
    }()
    
    /// 允许后台下载
    public static let allowBackgroundTask: LGWebImageOptions = {
        return LGWebImageOptions(rawValue: 1 << 4)
    }()
    
    /// 在SSL证书无效的情况下允许下载
    public static let allowInvalidSSLCertificates: LGWebImageOptions = {
        return LGWebImageOptions(rawValue: 1 << 5)
    }()
    
    /// 开启大图优化，图片在解压缩时需要消耗大量内存，开启后会将大于1MB的大图进行压缩处理后显示，支持JPG，PNG，ICO等，不支持WEBP，HEIF
    public static let enableBigPictureOptimization: LGWebImageOptions = {
        return LGWebImageOptions(rawValue: 1 << 6)
    }()
    
    /// 刷新图片缓存
    public static let refreshImageCache: LGWebImageOptions = {
        return LGWebImageOptions(rawValue: 1 << 7)
    }()
    
    /// 忽略磁盘缓存
    public static let ignoreDiskCache: LGWebImageOptions = {
        return LGWebImageOptions(rawValue: 1 << 8)
    }()
    
    /// 忽略占位图
    public static let ignorePlaceHolder: LGWebImageOptions = {
        return LGWebImageOptions(rawValue: 1 << 9)
    }()
    
    /// 忽略图片解码，直接返回数据
    public static let ignoreImageDecoding: LGWebImageOptions = {
        return LGWebImageOptions(rawValue: 1 << 10)
    }()
    
    /// 不处理动图
    public static let ignoreAnimatedImage: LGWebImageOptions = {
        return LGWebImageOptions(rawValue: 1 << 11)
    }()
    
    /// 显示图片的时候使用Fade动画
    public static let setImageWithFadeAnimation: LGWebImageOptions = {
        return LGWebImageOptions(rawValue: 1 << 12)
    }()
    
    /// 避免设置图片
    public static let avoidSetImage: LGWebImageOptions = {
        return LGWebImageOptions(rawValue: 1 << 13)
    }()
    
    /// 忽略下载出错的URL
    public static let ignoreFailedURL: LGWebImageOptions = {
        return LGWebImageOptions(rawValue: 1 << 14)
    }()
    
    /// 默认，使用Fade动画，允许后台下载，开启渐进加载
    public static let `default`: LGWebImageOptions = {
        return [LGWebImageOptions.setImageWithFadeAnimation,
                LGWebImageOptions.allowBackgroundTask,
                LGWebImageOptions.progressiveBlur,
                LGWebImageOptions.enableBreakpointPass,
                LGWebImageOptions.enableBigPictureOptimization]
    }()
}

/// 图片处理状态
///
/// - none: 未知
/// - memoryCacheFase: 内存缓存处理中
/// - memoryCache: 在内存缓存里
/// - diskCache: 在磁盘上
/// - remoteServer: 还在服务器上
public enum LGWebImageSourceType {
    case none
    case memoryCacheFast
    case memoryCache
    case diskCache
    case remoteServer
}

/// 图片状态
///
/// - progress: 下载中
/// - cancelled: 取消
/// - finished: 完成下载
public enum LGWebImageStage {
    case progress
    case cancelled
    case finished
}

// MARK: - 定义渐进加载的最短时间间隔
public extension TimeInterval {
    
    /// 渐进加载最短0.2S
    public static var minProgressiveTimeInterval: TimeInterval {
        return 0.2
    }
    
    /// 渐进模糊加载最短0.4S
    public static var minProgressiveBlurTimeInterval: TimeInterval {
        return 0.4
    }

}

public extension CFTimeInterval {
    
    public static var lg_imageFadeAnimationTime: CFTimeInterval {
        return 0.2
    }
    
    public static var lg_imageProgressiveFadeAnimationTime: CFTimeInterval {
        return 0.4
    }
}

/// Returns JPEG SOS (Start Of Scan) Marker
public var JPEGSOSMarker: Data {
    return Data(bytes: [0xFF, 0xDA])
}

public typealias LGWebImageTransformBlock = ((UIImage?, URL?) -> UIImage?)
public typealias LGWebImageCompletionBlock = ((UIImage?, URL?, LGWebImageSourceType, LGWebImageStage, Error?) -> Void)
public typealias LGWebImageProgressBlock = LGProgressHandler



