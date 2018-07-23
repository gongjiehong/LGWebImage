//
//  LGFrameImage.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2017/10/11.
//  Copyright © 2017年 龚杰洪. All rights reserved.
//

import UIKit


extension String {
    
    /// 读取图片的Scale值
    /// path            scale
    /// example.png     1
    /// example@2x.png  2
    /// example@3x.png  3
    var lg_pathScale: CGFloat {
        if self.count == 0 || self.hasSuffix("/") {
            return 1.0
        }
        let name = NSString(string: self).deletingPathExtension
        do {
            let pattern = try NSRegularExpression(pattern: "@[0-9]+\\.?[0-9]*x$",
                                                  options: NSRegularExpression.Options.anchorsMatchLines)
            var scale: CGFloat = 1.0
            pattern.enumerateMatches(in: name,
                                     options: NSRegularExpression.MatchingOptions.reportProgress,
                                     range: NSMakeRange(0, name.count),
                                     using: { (result, flags, stopPointer) in
                    if result != nil && result!.range.location >= 3 {
                        let range = NSMakeRange(result!.range.location + 1, result!.range.length - 2)
                        let number = NumberFormatter().number(from: NSString(string: self).substring(with: range))
                        scale = CGFloat(number?.doubleValue ?? 1.0)
                    }
            })
            return scale
        } catch {
            return 1.0
        }
        
    }
}


public class LGFrameImage: UIImage {
    
    fileprivate var loopCount: Int = 0
    fileprivate var oneFrameBytes: Int = 0
    fileprivate var imagePaths: [String] = [String]()
    fileprivate var imageDatas: [Data] = [Data]()
    fileprivate var frameDurations: [TimeInterval] = [TimeInterval]()
    
    public static func imageWith(imagePaths: [String],
                                 oneFrameDuration: TimeInterval,
                                 loopCount: Int) throws -> LGFrameImage
    {
        var durations = [TimeInterval]()
        for _ in 0..<imagePaths.count {
            durations.append(oneFrameDuration)
        }
        return try self.imageWith(imagePaths: imagePaths, frameDurations: durations, loopCount: loopCount)
    }
    
    public static func imageWith(imagePaths: [String],
                                 frameDurations: [TimeInterval],
                                 loopCount: Int) throws -> LGFrameImage
    {
        if imagePaths.count == 0 || imagePaths.count != frameDurations.count {
            throw LGImageCoderError.frameImageInputInvalid
        }
        let firstPath = imagePaths[0]
        let firstPathUrl = URL(fileURLWithPath: firstPath)
        let firstData = try Data(contentsOf: firstPathUrl)
        let scale = firstPath.lg_pathScale
        if let firstCG = UIImage(data: firstData, scale: scale)?.lg_imageByDecoded.cgImage {
            let result = LGFrameImage(cgImage: firstCG, scale: scale, orientation: UIImage.Orientation.up)
            let frameBytes = firstCG.bytesPerRow
            result.oneFrameBytes = frameBytes
            result.imagePaths += imagePaths
            result.frameDurations += frameDurations
            result.loopCount = loopCount
            return result
        } else {
            throw LGImageCoderError.frameDataInvalid
        }
    }
    
    public static func imageWith(imageDataArray: [Data],
                                 oneFrameDuration: TimeInterval,
                                 loopCount: Int) throws -> LGFrameImage
    {
        var durations = [TimeInterval]()
        for _ in 0..<imageDataArray.count {
            durations.append(oneFrameDuration)
        }
        return try self.imageWith(imageDataArray: imageDataArray, frameDurations: durations, loopCount: loopCount)
    }
    

    public static func imageWith(imageDataArray: [Data],
                                 frameDurations: [TimeInterval],
                                 loopCount: Int) throws -> LGFrameImage
    {
        if imageDataArray.count == 0 || imageDataArray.count != frameDurations.count {
            throw LGImageCoderError.frameImageInputInvalid
        }
        let firstData = imageDataArray[0]
        let scale = UIScreen.main.scale
        if let firstCG = UIImage(data: firstData, scale: scale)?.lg_imageByDecoded.cgImage {
            let result = LGFrameImage(cgImage: firstCG, scale: scale, orientation: UIImage.Orientation.up)
            let frameBytes = firstCG.bytesPerRow
            result.oneFrameBytes = frameBytes
            result.imageDatas += imageDataArray
            result.frameDurations += frameDurations
            result.loopCount = loopCount
            return result
        } else {
            throw LGImageCoderError.frameDataInvalid
        }
    }
}

extension LGFrameImage: LGAnimatedImage {
    public func animatedImageFrameCount() -> Int {
        if imagePaths.count >= 1  {
            return imagePaths.count
        } else if imageDatas.count >= 1 {
            return imageDatas.count
        } else {
            return 1
        }
    }
    
    public func animatedImageLoopCount() -> Int {
        return self.loopCount
    }
    
    public func animatedImageBytesPerFrame() -> Int {
        return self.oneFrameBytes
    }
    
    public func animatedImageFrame(atIndex index: Int) -> UIImage? {
        if imagePaths.count >= 1 {
            if index >= imagePaths.count {
                return nil
            }
            let path = imagePaths[index]
            let scale = path.lg_pathScale
            do {
                let url = URL(fileURLWithPath: path)
                let data = try Data(contentsOf: url)
                return UIImage(data: data, scale: scale)?.lg_imageByDecoded
            } catch {
                return nil
            }
        } else if imageDatas.count >= 1 {
            if index >= imageDatas.count {
                return nil
            }
            let data = imageDatas[index]
            return UIImage(data: data, scale: scale)?.lg_imageByDecoded
        } else {
            return index == 0 ? self : nil
        }
    }
    
    public func animatedImageDuration(atIndex index: Int) -> TimeInterval {
        if index >= frameDurations.count {
            return 0
        }
        return frameDurations[index]
    }
}
