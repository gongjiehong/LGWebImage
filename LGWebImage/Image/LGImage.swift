//
//  LGImage.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2017/10/11.
//  Copyright © 2017年 龚杰洪. All rights reserved.
//

import UIKit

private var BundlePreferredScales: [CGFloat] {
    var scales: [CGFloat]
    let screenScale = UIScreen.main.scale
    if screenScale <= 1 {
        // 基本没用了, @1x
        scales = [1, 2, 3]
    } else if screenScale <= 2 {
        // @2x 优先
        scales = [2, 3, 1]
    } else {
        // @3x 优先
        scales = [3, 2, 1]
    }
    return scales
}

extension String {
    func lg_stringByAppendingNameScale(_ scale: CGFloat) -> String {
        if abs(scale - 1) <= CGFloat.ulpOfOne || self.count == 0 || self.hasSuffix("/") {
            return self
        }
        return self.appendingFormat("@%dx", Int(scale))
    }
    
    var lg_stringByDeletingPathExtension: String {
        return NSString(string: self).deletingPathExtension
    }
    
    var lg_pathExtension: String {
        return NSString(string: self).pathExtension
    }
}


/// 本框架支持的文件后缀，不区分大小写
///
/// - Returns: 支持的后缀数组
fileprivate func LGImageSupportExtensions() -> [String] {
    return ["", "png", "jpeg", "jpg", "gif", "webp", "apng", "jp2", "bmp", "ico", "heic", "tiff"]
}

public final class LGImage: UIImage {
    
    fileprivate var decoder: LGImageDecoder?
    fileprivate var preloadedFrames: [Any] = [Any]()
    fileprivate var preloadedLock: DispatchSemaphore = DispatchSemaphore(value: 1)
    fileprivate var bytesPerFrame: Int = 0
    
    public private(set) var animatedImageType: LGImageType = LGImageType.unknow
    public private(set) var animatedImageMemorySize: Int = 0
    public var animatedImageData: Data? {
        return self.decoder?.imageData
    }
    
    public var preloadAllAnimatedImageFrames: Bool = false {
        didSet {
            preloadAllAnimatedImageFramesChanged()
        }
    }
    
    public static func image(named name: String) -> LGImage? {
        if name.lg_length == 0 {
            return nil
        }
        if name.hasSuffix("/") {
            return nil
        }
        
        let res = name.lg_stringByDeletingPathExtension
        let ext = name.lg_pathExtension
        var path: String? = nil
        var scale: CGFloat = 1.0
        
        let exts = ext.lg_length > 0 ? [ext] : LGImageSupportExtensions()
        let scales = BundlePreferredScales
        
        for scaleIndex in 0..<scales.count {
            scale = scales[scaleIndex]
            let scaledName = res.lg_stringByAppendingNameScale(scale)
            for tempExt in exts {
                path = Bundle.main.path(forResource: scaledName, ofType: tempExt.lowercased())
                if path != nil {
                    break
                } else {
                    path = Bundle.main.path(forResource: scaledName, ofType: tempExt.uppercased())
                }
                if path != nil {
                    break
                }
            }
            if path != nil {
                break
            }
        }
        
        if path == nil || path?.lg_length == 0 {
            guard let image = UIImage(named: name), let cgImage = UIImage(named: name)?.cgImage else {
                return nil
            }
            let result = LGImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
            return result
        } else {
            do {
                let url = URL(fileURLWithPath: path!)
                let data = try Data(contentsOf: url)
                if data.count == 0 {
                    return nil
                }
                return self.imageWith(data: data)
            } catch {
                return nil
            }
        }
    }

    public static func imageWith(contentsOfFile path: String) -> LGImage? {
        do {
            let fileUrl = URL(fileURLWithPath: path)
            let fileData = try Data(contentsOf: fileUrl)
            return self.imageWith(data: fileData, scale: path.lg_pathScale)
        } catch  {
            return nil
        }
    }
    
    public static func imageWith(data: Data, scale: CGFloat = 1.0) -> LGImage? {
        if data.count == 0 {
            return nil
        }
        var safeScale: CGFloat = scale
        if scale <= 0 {
            safeScale = UIScreen.main.scale
        }
        do {
            let decoder = try LGImageDecoder(withData: data, scale: safeScale)
            let frame = decoder.frameAtIndex(index: 0, decodeForDisplay: true)
            guard let image = frame?.image else {
                return nil
            }
            guard let cgImage = image.cgImage else {
                return nil
            }
            let result = LGImage(cgImage: cgImage, scale: decoder.scale, orientation: image.imageOrientation)
            result.animatedImageType = decoder.imageType
            if decoder.frameCount > 1 {
                result.decoder = decoder
                result.bytesPerFrame = cgImage.bytesPerRow * cgImage.height
                result.animatedImageMemorySize = result.bytesPerFrame * decoder.frameCount
            } else {
                result.bytesPerFrame = cgImage.bytesPerRow * cgImage.height
                result.animatedImageMemorySize = result.bytesPerFrame
            }
            result.lg_isDecodedForDisplay = true
            return result
        } catch {
            return nil
        }
    }

    override public func encode(with aCoder: NSCoder) {
        if self.decoder?.imageData != nil && self.decoder?.imageData?.count != 0 {
            // 动态图读取图片源data进行encode
            aCoder.encode(self.scale, forKey: "LGImageScale")
            aCoder.encode(self.decoder?.imageData, forKey: "LGImageData")
        } else {
            // 不是动态图直接读取原UIImage的data用于encode，跟Apple的处理方式类似
            aCoder.encode(self.scale, forKey: "LGImageScale")
            aCoder.encode(self.lg_imageDataRepresentation, forKey: "LGImageData")
        }
    }

    public required convenience init?(coder aDecoder: NSCoder) {
        let scale = (aDecoder.decodeObject(forKey: "LGImageScale") as? CGFloat) ?? UIScreen.main.scale
        guard let data = aDecoder.decodeObject(forKey: "LGImageData") as? Data else {
            return nil
        }
        self.init(data: data, scale: scale)
    }
    
    func preloadAllAnimatedImageFramesChanged() {
        if self.decoder != nil {
            if preloadAllAnimatedImageFrames && self.decoder!.frameCount > 0 {
                var frames = [Any]()
                for index in 0..<decoder!.frameCount {
                    if let image = self.animatedImageFrame(atIndex: index) {
                        frames.append(image)
                    } else {
                        frames.append(NSNull())
                    }
                }
                preloadedLock.lg_lock()
                self.preloadedFrames.removeAll()
                self.preloadedFrames += frames
                preloadedLock.lg_unlock()
            } else {
                preloadedLock.lg_lock()
                self.preloadedFrames.removeAll()
                preloadedLock.lg_unlock()
            }
        }
    }
}

extension LGImage: LGAnimatedImage {
    public func animatedImageFrameCount() -> Int {
        return self.decoder?.frameCount ?? 0
    }
    
    public func animatedImageLoopCount() -> Int {
        return self.decoder?.loopCount ?? 0
    }
    
    public func animatedImageBytesPerFrame() -> Int {
        return self.bytesPerFrame
    }
    
    public func animatedImageFrame(atIndex index: Int) -> UIImage? {
        guard let decoder = self.decoder else {
            return nil
        }
        
        if index >= decoder.frameCount {
            return nil
        }
        
        if index >= preloadedFrames.count {
            return decoder.frameAtIndex(index: index, decodeForDisplay: true)?.image
        }
        
        preloadedLock.lg_lock()
        let image = preloadedFrames[index] as? UIImage
        preloadedLock.lg_unlock()
        if image != nil {
            return image
        } else {
            return decoder.frameAtIndex(index: index, decodeForDisplay: true)?.image
        }
    }
    
    public func animatedImageDuration(atIndex index: Int) -> TimeInterval {
        guard let decoder = self.decoder else {
            return 0
        }
        let duration = decoder.frameDuration(atIndex: index)

        if duration < 0.011 {
            return 0.1
        }
        return duration
    }
}

