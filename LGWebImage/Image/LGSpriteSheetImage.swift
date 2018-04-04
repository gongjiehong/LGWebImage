//
//  LGSpriteSheetImage.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2017/9/26.
//  Copyright © 2017年 龚杰洪. All rights reserved.
//

import UIKit

public class LGSpriteSheetImage: UIImage {
    public private(set) var contentRects: [CGRect] = [CGRect]()
    public private(set) var frameDurations: [TimeInterval] = [TimeInterval]()
    public private(set) var loopCount: Int = 0
    
    
    static func imageWith(spriteSheetImage image: UIImage,
                          contentRects: [CGRect],
                          frameDurations: [TimeInterval],
                          loopCount: Int) throws -> LGSpriteSheetImage
    {
        guard let cgImage = image.cgImage else {
            throw LGImageCoderError.errorWith(code: LGImageCoderError.ErrorCode.imageSourceInvalid,
                                              description: "图片数据无法读取")
        }
        
        if contentRects.count < 1 || frameDurations.count < 1 || contentRects.count != frameDurations.count {
            throw LGImageCoderError.errorWith(code: LGImageCoderError.ErrorCode.imageSourceInvalid,
                                              description: "数组数据不合法")
        }
        
        let result = LGSpriteSheetImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
        result.contentRects = contentRects
        result.frameDurations = frameDurations
        result.loopCount = loopCount
        return result
    }
    
    public func contentsRectForCALayer(atIndex index: Int) -> CGRect {
        let defaultRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        var layerRect = defaultRect
        if index >= contentRects.count {
            return layerRect
        }
        let imageSize = self.size
        let rect = self.animatedImageContentsRect(atIndex: index)
        if imageSize.width > 0.01 && imageSize.height > 0.01 {
            layerRect.origin.x = rect.origin.x / imageSize.width
            layerRect.origin.y = rect.origin.y / imageSize.height
            layerRect.size.width = rect.size.width / imageSize.width
            layerRect.size.height = rect.size.height / imageSize.height
            layerRect = layerRect.intersection(defaultRect)
            if layerRect.isEmpty || layerRect.isNull {
                layerRect = defaultRect
            }
        }
        return layerRect
    }
    
}

extension LGSpriteSheetImage: LGAnimatedImage {
    public func animatedImageFrameCount() -> Int {
        return contentRects.count
    }
    
    public func animatedImageLoopCount() -> Int {
        return self.loopCount
    }
    
    public func animatedImageBytesPerFrame() -> Int {
        return 0
    }
    
    public func animatedImageFrame(atIndex index: Int) -> UIImage? {
        return self
    }
    
    public func animatedImageDuration(atIndex index: Int) -> TimeInterval {
        if index >= frameDurations.count {
            return 0
        }
        return frameDurations[index]
    }
    
    public func animatedImageContentsRect(atIndex index: Int) -> CGRect {
        if index >= frameDurations.count {
            return CGRect.zero
        }
        return contentRects[index]
    }
}
