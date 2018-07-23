//
//  UIImage+Extensions.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2017/10/17.
//  Copyright © 2017年 龚杰洪. All rights reserved.
//

import Foundation
import ImageIO
import Accelerate


extension CGRect {
    func fitWithContentMode(_ mode: UIView.ContentMode, size: CGSize) -> CGRect {
        var result = self.standardized
        var toCalcSize = size
        toCalcSize.width = toCalcSize.width < 0 ? -toCalcSize.width : toCalcSize.width
        toCalcSize.height = toCalcSize.height < 0 ? -toCalcSize.height : toCalcSize.height
        let center = CGPoint(x: result.midX, y: result.midY)
        switch mode {
        case UIView.ContentMode.scaleAspectFit, UIView.ContentMode.scaleAspectFill:
            if  result.size.width < 0.01 || result.size.height < 0.01 ||
                toCalcSize.width < 0.01 || toCalcSize.height < 0.01 {
                result.origin = center
                result.size = CGSize.zero
            } else {
                var scale: CGFloat = 0.0
                if mode == UIView.ContentMode.scaleAspectFit {
                    if toCalcSize.width / toCalcSize.height < result.size.width / result.size.height {
                        scale = result.size.height / toCalcSize.height
                    } else {
                        scale = result.size.width / toCalcSize.width
                    }
                } else {
                    if toCalcSize.width / toCalcSize.height < result.size.width / result.size.height {
                        scale = result.size.width / toCalcSize.width;
                    } else {
                        scale = result.size.height / toCalcSize.height;
                    }
                }
                toCalcSize.width *= scale
                toCalcSize.height *= scale
                result.size = toCalcSize
                result.origin = CGPoint(x: center.x - toCalcSize.width * 0.5, y: center.y - toCalcSize.height * 0.5)
            }
            break
            
        case UIView.ContentMode.center:
            result.size = toCalcSize
            result.origin = CGPoint(x: center.x - toCalcSize.width * 0.5, y: center.y - toCalcSize.height * 0.5)
            break
        case UIView.ContentMode.top:
            result.origin.x = center.x - toCalcSize.width * 0.5
            result.size = toCalcSize
            break
        case UIView.ContentMode.bottom:
            result.origin.x = center.x - toCalcSize.width * 0.5
            result.origin.y += result.size.height - toCalcSize.height
            result.size = toCalcSize
            break
        case UIView.ContentMode.left:
            result.origin.y = center.y - toCalcSize.height * 0.5
            result.size = toCalcSize
            break
        case UIView.ContentMode.right:
            result.origin.y = center.y - toCalcSize.height * 0.5
            result.origin.x += result.size.width - toCalcSize.width
            result.size = toCalcSize
            break
        case UIView.ContentMode.topLeft:
            result.size = toCalcSize
            break
        case UIView.ContentMode.topRight:
            result.origin.x += result.size.width - toCalcSize.width
            result.size = toCalcSize
            break
        case UIView.ContentMode.bottomLeft:
            result.origin.y += result.size.height - toCalcSize.height
            result.size = toCalcSize
            break
        case UIView.ContentMode.bottomRight:
            result.origin.x += result.size.width - toCalcSize.width
            result.origin.y += result.size.height - toCalcSize.height
            result.size = toCalcSize
            break
        default:
            break
        }
        return result
    }
    
}


extension CGImageSource {
    
    /// 获取GIF&APNG某一帧的延时时间
    ///
    /// - Parameter index: 帧下标
    /// - Returns: TimeInterval
    public func lg_gifFrameDelayAtIndex(_ index: Int) -> TimeInterval {
        var delay: TimeInterval = 0
        if let dic = CGImageSourceCopyMetadataAtIndex(self, index, nil) as? [CFString: Any] {
            if let gifDic = dic[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
                if var num = gifDic[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber {
                    if num.doubleValue <= Double.ulpOfOne {
                        if let tempNum = gifDic[kCGImagePropertyGIFDelayTime] as? NSNumber {
                            num = tempNum
                        }
                    }
                    delay = num.doubleValue
                }
            }
        }
        if delay <= 0.02  {
            delay = 0.1
        }
        return delay
    }
}

extension UIImage {
    
    // MARK: -  通过数据初始化
    public class func imageWith(smallGIFData data: Data, scale: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let count = CGImageSourceGetCount(source)
        if count <= 1 {
            return UIImage(data: data, scale: scale)
        }
        
        var frames: [Int] = [Int](repeating: 0, count: count)
        let oneFrameTime: TimeInterval = 1 / 50.0
        var totalTime: TimeInterval = 0
        var gcdFrame: Int = 0
        
        for index in 0..<count {
            let delay = source.lg_gifFrameDelayAtIndex(index)
            totalTime += delay
            var frame = lrint(delay / oneFrameTime)
            if frame < 1 { frame = 1 }
            frames[index] = frame
            if index == 0 {
                gcdFrame = frames[index]
            } else {
                var tempFrame = frames[index]
                var temp: Int
                if tempFrame < gcdFrame {
                    temp = tempFrame
                    tempFrame = gcdFrame
                    gcdFrame = temp
                }
                while true {
                    temp = tempFrame % gcdFrame
                    if temp == 0 {
                        break
                    }
                    tempFrame = gcdFrame
                    gcdFrame = temp
                }
            }
        }
        var resultArray = [UIImage]()
        for index in 0..<count {
            let options = [kCGImageSourceShouldCache: true] as CFDictionary
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, options) else {
                return nil
            }
            
            let width = cgImage.width
            let height = cgImage.height
            if width == 0 || height == 0 {
                return nil
            }
            
            let alphaInfoValue = cgImage.alphaInfo.rawValue & CGBitmapInfo.alphaInfoMask.rawValue
            let alphaInfo = CGImageAlphaInfo(rawValue: alphaInfoValue)
            var hasAlpha = false
            if alphaInfo == CGImageAlphaInfo.premultipliedLast ||
                alphaInfo == CGImageAlphaInfo.first ||
                alphaInfo == CGImageAlphaInfo.premultipliedFirst ||
                alphaInfo == CGImageAlphaInfo.last {
                hasAlpha = true
            }
            
            var bitmapInfo = LGCGBitmapByteOrder32Host.rawValue
            var toOrValue: UInt32 = 0
            if hasAlpha {
                toOrValue = CGImageAlphaInfo.premultipliedFirst.rawValue
            } else {
                toOrValue = CGImageAlphaInfo.noneSkipFirst.rawValue
            }
            bitmapInfo |= toOrValue
            let colorSpace = LGCGColorSpaceDeviceRGB
            guard let context = CGContext(data: nil,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: 0,
                                          space: colorSpace,
                                          bitmapInfo: bitmapInfo) else {
                                            return nil
            }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let decoded = context.makeImage() else {
                return nil
            }
            let image = UIImage(cgImage: decoded, scale: scale, orientation: UIImage.Orientation.up)
            for _ in 0..<(frames[index] / gcdFrame) {
                resultArray.append(image)
            }
        }
        return UIImage.animatedImage(with: resultArray, duration: totalTime)
    }
    
    public convenience init?(color: UIColor, size: CGSize = CGSize(width: 1, height: 1)) {
        if size.width <= 0 || size.height <= 0 {
            return nil
        }
        let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        UIGraphicsBeginImageContextWithOptions(size, false, UIScreen.main.scale)
        let context = UIGraphicsGetCurrentContext()
        context?.setFillColor(color.cgColor)
        context?.fill(rect)
        let image = context?.makeImage()
        UIGraphicsEndImageContext()
        if image != nil {
            self.init(cgImage: image!)
        } else {
            return nil
        }
    }
    
    public convenience init?(withSize size: CGSize, drawBlock block: (inout CGContext) -> Void) {
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        guard var context = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return nil
        }
        block(&context)
        guard let image = context.makeImage() else {
            UIGraphicsEndImageContext()
            return nil
        }
        UIGraphicsEndImageContext()
        self.init(cgImage: image)
    }
    
    // MARK: - alpha 通道属性
    public var lg_hasAlphaChannel: Bool {
        guard let cgImage = self.cgImage else {
            return false
        }
        let alpha = cgImage.alphaInfo
        if alpha == CGImageAlphaInfo.first ||
            alpha == CGImageAlphaInfo.last ||
            alpha == CGImageAlphaInfo.premultipliedLast ||
            alpha == CGImageAlphaInfo.premultipliedFirst {
            return true
        } else {
            return false
        }
    }
    
    // MARK: -  效果叠加
    public func lg_imageByTintColor(_ color: UIColor) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(self.size, false, self.scale)
        let rect = CGRect(x: 0, y: 0, width: self.size.width, height: self.size.height)
        color.set()
        UIRectFill(rect)
        self.draw(at: CGPoint.zero, blendMode: CGBlendMode.destinationIn, alpha: 1)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage
    }
    
    public func lg_imageByGrayscale() -> UIImage? {
        return self.lg_imageByBlurRadius(0,
                                         tintColor: nil,
                                         tintBlendMode: CGBlendMode.normal,
                                         saturation: 0,
                                         maskImage: nil)
    }
    
    public func lg_imageByBlurSoft() -> UIImage? {
        return self.lg_imageByBlurRadius(60,
                                         tintColor: UIColor(white: 0.84, alpha: 0.36),
                                         tintBlendMode: CGBlendMode.normal,
                                         saturation: 1.8,
                                         maskImage: nil)
    }
    
    public func lg_imageByBlurLight() -> UIImage? {
        return self.lg_imageByBlurRadius(60,
                                         tintColor: UIColor(white: 1.0, alpha: 0.3),
                                         tintBlendMode: CGBlendMode.normal,
                                         saturation: 1.8,
                                         maskImage: nil)
    }
    
    public func lg_imageByBlurExtraLight() -> UIImage? {
        return self.lg_imageByBlurRadius(40,
                                         tintColor: UIColor(white: 0.96, alpha: 0.82),
                                         tintBlendMode: CGBlendMode.normal,
                                         saturation: 1.8,
                                         maskImage: nil)
    }
    
    public func lg_imageByBlurDark() -> UIImage? {
        return self.lg_imageByBlurRadius(40,
                                         tintColor: UIColor(white: 0.11, alpha: 0.73),
                                         tintBlendMode: CGBlendMode.normal,
                                         saturation: 1.8,
                                         maskImage: nil)
    }
    
    public func lg_imageByBlurWithTint(_ tintColor: UIColor) -> UIImage? {
        let effectColorAlpha: CGFloat = 0.6
        var effectColor = tintColor
        let componentCount = tintColor.cgColor.numberOfComponents
        if componentCount == 2 {
            var b: CGFloat = 0.0
            if tintColor.getWhite(&b, alpha: nil) {
                effectColor = UIColor(white: b, alpha: effectColorAlpha)
            }
        } else {
            var r: CGFloat = 0.0, g: CGFloat = 0.0, b: CGFloat = 0.0
            if tintColor.getRed(&r, green: &g, blue: &b, alpha: nil) {
                effectColor = UIColor(red: r, green: g, blue: b, alpha: effectColorAlpha)
            }
        }
        return self.lg_imageByBlurRadius(20.0,
                                         tintColor: effectColor,
                                         tintBlendMode: CGBlendMode.normal,
                                         saturation: -1.0,
                                         maskImage: nil)
    }
    
    /// 设置图片的一些效果，使用硬件加速
    /// 参考苹果官方代码：https://developer.apple.com/library/content/samplecode/UIImageEffects
    ///
    /// - Parameters:
    ///   - blurRadius: 模糊半径
    ///   - tintColor: 色调色
    ///   - tintBlendMode: 色调混合模式
    ///   - saturation: 差量饱和因子
    ///   - maskImage: 蒙版图
    /// - Returns: 处理后的图片
    public func lg_imageByBlurRadius(_ blurRadius: CGFloat,
                                     tintColor: UIColor?,
                                     tintBlendMode: CGBlendMode,
                                     saturation: CGFloat,
                                     maskImage: UIImage?) -> UIImage? {
        if self.size.width < 1 || self.size.height < 1 {
            //            println("*** error: invalid size: (\(self.size.width) x \(self.size.height)). " +
            //                "Both dimensions must be >= 1: \(self)")
            return nil
        }
        
        guard let cgImage = self.cgImage else {
            //            println("*** error: self must be backed by a CGImage: \(self)")
            return nil
        }
        
        if maskImage != nil && maskImage?.cgImage == nil {
            //            println("*** error: effectMaskImage must be backed by a CGImage: \(maskImage)")
            return nil
        }
        
        
        let hasBlur = blurRadius > CGFloat.ulpOfOne
        let hasSaturation = abs(saturation - 1.0) > CGFloat.ulpOfOne
        
        let scale = self.scale
        
        if (!hasBlur && !hasSaturation) {
            return self.lg_mergeCGImage(cgImage,
                                        tintColor: tintColor,
                                        tintBlendMode: tintBlendMode,
                                        maskImage: maskImage,
                                        opaque: false)
        }
        
        var effect: vImage_Buffer? = vImage_Buffer()
        var scratch: vImage_Buffer? = vImage_Buffer()
        let bitmapValue = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        let bitmapInfo = CGBitmapInfo(rawValue: bitmapValue)
        let colorSpace = Unmanaged.passRetained(LGCGColorSpaceDeviceRGB)
        defer {
            colorSpace.release()
        }
        var format: vImage_CGImageFormat = vImage_CGImageFormat(bitsPerComponent: 8,
                                                                bitsPerPixel: 32,
                                                                colorSpace: colorSpace,
                                                                bitmapInfo: bitmapInfo,
                                                                version: 0,
                                                                decode: nil,
                                                                renderingIntent: CGColorRenderingIntent.defaultIntent)
        
        
        var error = vImageBuffer_InitWithCGImage(&effect!,
                                                 &format,
                                                 nil,
                                                 cgImage,
                                                 vImage_Flags(kvImagePrintDiagnosticsToConsole))
        if error != kvImageNoError {
//            println("*** error: vImageBuffer_InitWithCGImage returned error code \(error) for inputImage: \(self)")
            return nil
        }
        
        error = vImageBuffer_Init(&scratch!,
                                  effect!.height,
                                  effect!.width,
                                  format.bitsPerPixel,
                                  vImage_Flags(kvImageNoFlags))
        
        
        if error != kvImageNoError {
            return nil
        }
        
        var inputBuffer = withUnsafePointer(to: &effect!) { $0 }
        var outputBuffer = withUnsafePointer(to: &scratch!) { $0 }
        
        if (hasBlur) {
            var inputRadius = blurRadius * scale
            if inputRadius - 2.0 < CGFloat.ulpOfOne {
                inputRadius = 2.0
            }
            let temp1: CGFloat = sqrt(2.0 * CGFloat.pi)
            let temp2: CGFloat = inputRadius * 3.0
            var radius: Int = Int(floor((temp2 *  temp1 / 4 + 0.5) / 2))
            radius |= 1
            
            let tempBufferSize = vImageBoxConvolve_ARGB8888(inputBuffer,
                                                            outputBuffer,
                                                            nil,
                                                            0,
                                                            0,
                                                            UInt32(radius),
                                                            UInt32(radius),
                                                            nil,
                                                            vImage_Flags(kvImageGetTempBufferSize | kvImageEdgeExtend))
            
            let tempBuffer = malloc(tempBufferSize)
            vImageBoxConvolve_ARGB8888(inputBuffer,
                                       outputBuffer,
                                       tempBuffer,
                                       0,
                                       0,
                                       UInt32(radius),
                                       UInt32(radius),
                                       nil,
                                       vImage_Flags(kvImageEdgeExtend))
            vImageBoxConvolve_ARGB8888(outputBuffer,
                                       inputBuffer,
                                       tempBuffer,
                                       0,
                                       0,
                                       UInt32(radius),
                                       UInt32(radius),
                                       nil,
                                       vImage_Flags(kvImageEdgeExtend))
            vImageBoxConvolve_ARGB8888(inputBuffer,
                                       outputBuffer,
                                       tempBuffer,
                                       0,
                                       0,
                                       UInt32(radius),
                                       UInt32(radius),
                                       nil,
                                       vImage_Flags(kvImageEdgeExtend))
            // swap
            let temp = inputBuffer
            inputBuffer = outputBuffer
            outputBuffer = temp
            free(tempBuffer)
        }
        
        if (hasSaturation) {
            
            let s = saturation
            // These values appear in the W3C Filter Effects spec:
            // https://dvcs.w3.org/hg/FXTF/raw-file/default/filters/index.html#grayscaleEquivalent
            //
            let matrixFloat: [CGFloat] = [
                0.0722 + 0.9278 * s,  0.0722 - 0.0722 * s,  0.0722 - 0.0722 * s,  0,
                0.7152 - 0.7152 * s,  0.7152 + 0.2848 * s,  0.7152 - 0.7152 * s,  0,
                0.2126 - 0.2126 * s,  0.2126 - 0.2126 * s,  0.2126 + 0.7873 * s,  0,
                0,                    0,                    0,                    1,
                ]
            
            let divisor: Int = 256
            let matrixSize: Int = MemoryLayout.size(ofValue: matrixFloat) / MemoryLayout.size(ofValue: matrixFloat[0])
            var matrix: [Int16] = [Int16](repeating: 0, count: matrixSize)
            for index in 0..<matrixSize {
                var value = matrixFloat[index] * CGFloat(divisor)
                value = CGFloat(roundf(Float(value)))
                matrix[index] = Int16(value)
            }
            
            vImageMatrixMultiply_ARGB8888(inputBuffer,
                                          outputBuffer,
                                          &matrix,
                                          Int32(divisor),
                                          nil,
                                          nil,
                                          vImage_Flags(kvImageNoFlags))
            // swap
            let temp = inputBuffer
            inputBuffer = outputBuffer
            outputBuffer = temp
            
        }
        
        var outputImage: UIImage? = nil
        var effectCGImage: CGImage? = nil
        effectCGImage = vImageCreateCGImageFromBuffer(inputBuffer,
                                                      &format,
                                                      { (oriPointer, newPointer) in
                                                        free(newPointer)
                                                        return
        },
                                                      nil,
                                                      vImage_Flags(kvImageNoAllocate),
                                                      &error).takeRetainedValue()
        if effectCGImage == nil {
            effectCGImage = vImageCreateCGImageFromBuffer(inputBuffer,
                                                          &format,
                                                          nil,
                                                          nil,
                                                          vImage_Flags(kvImageNoFlags),
                                                          &error).takeRetainedValue()
            free(inputBuffer.pointee.data)
        }
        free(outputBuffer.pointee.data)
        if effectCGImage == nil {
            return nil
        }
        outputImage = self.lg_mergeCGImage(effectCGImage!,
                                           tintColor: tintColor,
                                           tintBlendMode: tintBlendMode,
                                           maskImage: maskImage,
                                           opaque: false)
        return outputImage
    }
    
    
    func lg_mergeCGImage(_ effectCGImage: CGImage,
                         tintColor: UIColor?,
                         tintBlendMode: CGBlendMode,
                         maskImage: UIImage?,
                         opaque: Bool) -> UIImage? {
        let hasTint = (tintColor != nil && tintColor!.cgColor.alpha > CGFloat.ulpOfOne)
        let hasMask = maskImage != nil
        let size = self.size
        let rect = CGRect(origin: CGPoint.zero, size: size)
        let scale = self.scale
        
        if !hasTint && !hasMask {
            return UIImage(cgImage: effectCGImage)
        }
        
        if self.cgImage == nil {
            return UIImage(cgImage: effectCGImage)
        }
        
        UIGraphicsBeginImageContextWithOptions(size, opaque, scale)
        let context = UIGraphicsGetCurrentContext()
        context?.scaleBy(x: 1.0, y: -1.0)
        context?.translateBy(x: 0, y: -size.height)
        if hasMask {
            context?.draw(self.cgImage!, in: rect)
            context?.saveGState()
            context?.clip(to: rect, mask: (maskImage?.cgImage)!)
        }
        context?.draw(effectCGImage, in: rect)
        if hasTint {
            context?.saveGState()
            context?.setBlendMode(tintBlendMode)
            context?.setFillColor(tintColor!.cgColor)
            context?.restoreGState()
        }
        
        if hasMask {
            context?.restoreGState()
        }
        let resultImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return resultImage
    }
    
    // MARK: -  修改图像数据获得新图
    public func lg_draw(in rect: CGRect, withContentMode contentMode: UIView.ContentMode, clipsToBounds clips: Bool) {
        let drawRect = rect.fitWithContentMode(contentMode, size: self.size)
        if drawRect.width == 0 || drawRect.height == 0 {
            return
        }
        if clips {
            if let context = UIGraphicsGetCurrentContext() {
                context.saveGState()
                context.addRect(rect)
                context.clip()
                self.draw(in: drawRect)
                context.restoreGState()
            } else {
                self.draw(in: drawRect)
            }
        } else {
            self.draw(in: drawRect)
        }
    }
    
    public func lg_imageByResizeToSize(_ size: CGSize) -> UIImage? {
        if size.width <= 0 || size.height <= 0 {return nil}
        UIGraphicsBeginImageContextWithOptions(size, false, self.scale)
        self.draw(in: CGRect(origin: CGPoint.zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }
    
    public func lg_imageByResizeToSize(_ size: CGSize, contentMode: UIView.ContentMode) -> UIImage? {
        if size.width <= 0 || size.height <= 0 {return nil}
        UIGraphicsBeginImageContextWithOptions(size, false, self.scale)
        self.lg_draw(in: CGRect(origin: CGPoint.zero, size: size),
                     withContentMode: contentMode,
                     clipsToBounds: false)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }
    
    public func lg_imageByCropToRect(_ rect: CGRect) -> UIImage? {
        let drawRect = CGRect(x: rect.origin.x * self.scale,
                              y: rect.origin.y * self.scale,
                              width: rect.width * self.scale,
                              height: rect.height * self.scale)
        if drawRect.width <= 0 || drawRect.height <= 0 {return nil}
        if let cgImage = self.cgImage?.cropping(to: drawRect) {
            return UIImage(cgImage: cgImage, scale: self.scale, orientation: self.imageOrientation)
        }
        return nil
    }
    
    public func lg_imageByInsetEdge(_ insets: UIEdgeInsets, withColor color: UIColor? = nil) -> UIImage? {
        var size = self.size
        size.width -= insets.left + insets.right
        size.height -= insets.top + insets.bottom
        if size.width <= 0 || size.height <= 0 {return nil}
        let rect = CGRect(x: -insets.left, y: -insets.top, width: self.size.width, height: self.size.height)
        UIGraphicsBeginImageContextWithOptions(size, false, self.scale)
        let context = UIGraphicsGetCurrentContext()
        if color != nil {
            context?.setFillColor(color!.cgColor)
            let path = CGMutablePath()
            path.addRect(CGRect(origin: CGPoint.zero, size: size))
            path.addRect(rect)
            context?.addPath(path)
            context?.fillPath(using: CGPathFillRule.evenOdd)
        }
        self.draw(in: rect)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }
    
    public func lg_imageByRoundCornerRadius(_ radius: CGFloat,
                                            corners: UIRectCorner = UIRectCorner.allCorners,
                                            borderWidth: CGFloat = 0.0,
                                            borderColor: UIColor? = nil,
                                            borderLineJoin: CGLineJoin = CGLineJoin.miter) -> UIImage? {
        var tempCorners = corners
        if corners != UIRectCorner.allCorners {
            if corners.contains(UIRectCorner.topLeft) {
                tempCorners = UIRectCorner.topLeft
            }
            if corners.contains(UIRectCorner.topRight) {
                tempCorners = UIRectCorner.topRight
            }
            if corners.contains(UIRectCorner.bottomLeft) {
                tempCorners = UIRectCorner.bottomLeft
            }
            if corners.contains(UIRectCorner.bottomRight) {
                tempCorners = UIRectCorner.bottomRight
            }
        }
        guard let cgImage = self.cgImage else {
            return nil
        }
        
        UIGraphicsBeginImageContextWithOptions(self.size, false, self.scale)
        let context = UIGraphicsGetCurrentContext()
        let rect = CGRect(origin: CGPoint.zero, size: self.size)
        context?.scaleBy(x: 1, y: -1)
        context?.translateBy(x: 0, y: -rect.height)
        let minSize = min(self.size.width, self.size.height)
        if borderWidth < minSize / 2.0 {
            let path = UIBezierPath(roundedRect: rect.insetBy(dx: borderWidth, dy: borderWidth),
                                    byRoundingCorners: tempCorners,
                                    cornerRadii: CGSize(width: radius, height: borderWidth))
            path.close()
            context?.saveGState()
            path.addClip()
            context?.draw(cgImage, in: rect)
            context?.restoreGState()
        }
        
        if borderColor != nil && borderWidth < minSize / 2 && borderWidth > 0 {
            let strokeInset: CGFloat = (floor(borderWidth * self.scale) + 0.5) / self.scale
            let strokeRect = rect.insetBy(dx: strokeInset, dy: strokeInset)
            let strokeRadius = radius > self.scale / 2 ? radius - self.scale / 2 : 0
            let path = UIBezierPath(roundedRect: strokeRect,
                                    byRoundingCorners: tempCorners,
                                    cornerRadii: CGSize(width: strokeRadius, height: borderWidth))
            path.close()
            path.lineWidth = borderWidth
            path.lineJoinStyle = borderLineJoin
            borderColor?.setStroke()
            path.stroke()
        }
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }
    
    public func lg_imageByRotate(_ radians: CGFloat, fitSize: Bool) -> UIImage? {
        guard let cgImage = self.cgImage else {return nil}
        let width = cgImage.width
        let height = cgImage.height
        let transform = fitSize ? CGAffineTransform(rotationAngle: radians) : CGAffineTransform.identity
        let newRect = CGRect(origin: CGPoint.zero, size: CGSize(width: width, height: height)).applying(transform)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapValue = (0 << 12) | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let context = CGContext(data: nil,
                                      width: Int(newRect.width),
                                      height: Int(newRect.height),
                                      bitsPerComponent: 8,
                                      bytesPerRow: Int(newRect.width) * 4,
                                      space: colorSpace,
                                      bitmapInfo: bitmapValue) else {
                                        return nil
        }
        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)
        context.interpolationQuality = CGInterpolationQuality.high
        context.translateBy(x: +(newRect.width * 0.5), y: +(newRect.height * 0.5))
        context.rotate(by: radians)
        context.draw(cgImage, in: CGRect(x: -(CGFloat(width) * 0.5),
                                         y: -(CGFloat(height) * 0.5),
                                         width: CGFloat(width),
                                         height: CGFloat(height)))
        if let newCGImage = context.makeImage() {
            let image = UIImage(cgImage: newCGImage, scale: self.scale, orientation: self.imageOrientation)
            return image
        }
        return nil
        
    }
    
    public func lg_flipHorizontal(_ horizontal: Bool, vertical: Bool) -> UIImage? {
        guard let cgImage = self.cgImage else {return nil}
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapValue = (0 << 12) | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: bitmapValue) else {
                                        return nil
        }
        context.draw(cgImage, in: CGRect(origin: CGPoint.zero, size: CGSize(width: width, height: height)))
        if context.data == nil {
            return nil
        }
        
        var src = vImage_Buffer(data: context.data,
                                height: vImagePixelCount(height),
                                width: vImagePixelCount(width),
                                rowBytes: bytesPerRow)
        var dest = vImage_Buffer(data: context.data,
                                 height: vImagePixelCount(height),
                                 width: vImagePixelCount(width),
                                 rowBytes: bytesPerRow)
        if vertical {
            vImageVerticalReflect_ARGB8888(&src, &dest, vImage_Flags(kvImageBackgroundColorFill))
        }
        if horizontal {
            vImageHorizontalReflect_ARGB8888(&src, &dest, vImage_Flags(kvImageBackgroundColorFill))
        }
        if let newCGImage = context.makeImage() {
            return UIImage(cgImage: newCGImage, scale: self.scale, orientation: self.imageOrientation)
        }
        return nil
    }
    
    public func lg_imageByRotateLeft90() -> UIImage? {
        return self.lg_imageByRotate(LGDegreesToRadians(degrees: 90), fitSize: true)
    }
    
    public func lg_imageByRotateRight90() -> UIImage? {
        return self.lg_imageByRotate(LGDegreesToRadians(degrees: -90), fitSize: true)
    }
    
    public func lg_imageByRotate180() -> UIImage?  {
        return self.lg_flipHorizontal(true, vertical: true)
    }
    
    public func lg_imageByFlipVertical() -> UIImage?  {
        return self.lg_flipHorizontal(false, vertical: true)
    }
    
    public func lg_imageByFlipHorizontal() -> UIImage?  {
        return self.lg_flipHorizontal(true, vertical: false)
    }
    
    public func lg_fixedOrientation() -> UIImage? {
        
        if imageOrientation == UIImage.Orientation.up {
            return self
        }
        
        var transform: CGAffineTransform = CGAffineTransform.identity
        
        switch imageOrientation {
        case UIImage.Orientation.down, UIImage.Orientation.downMirrored:
            transform = transform.translatedBy(x: size.width, y: size.height)
            transform = transform.rotated(by: CGFloat.pi)
            break
        case UIImage.Orientation.left, UIImage.Orientation.leftMirrored:
            transform = transform.translatedBy(x: size.width, y: 0)
            transform = transform.rotated(by: CGFloat.pi / 2.0)
            break
        case UIImage.Orientation.right, UIImage.Orientation.rightMirrored:
            transform = transform.translatedBy(x: 0, y: size.height)
            transform = transform.rotated(by: CGFloat.pi / -2.0)
            break
        case UIImage.Orientation.up, UIImage.Orientation.upMirrored:
            break
        }
        switch imageOrientation {
        case UIImage.Orientation.upMirrored, UIImage.Orientation.downMirrored:
            transform.translatedBy(x: size.width, y: 0)
            transform.scaledBy(x: -1, y: 1)
            break
        case UIImage.Orientation.leftMirrored, UIImage.Orientation.rightMirrored:
            transform.translatedBy(x: size.height, y: 0)
            transform.scaledBy(x: -1, y: 1)
        case UIImage.Orientation.up, UIImage.Orientation.down, UIImage.Orientation.left, UIImage.Orientation.right:
            break
        }
        guard let cgImage = self.cgImage,
            let colorSpace = cgImage.colorSpace,
            let ctx: CGContext = CGContext(data: nil,
                                           width: Int(size.width),
                                           height: Int(size.height),
                                           bitsPerComponent: self.cgImage!.bitsPerComponent,
                                           bytesPerRow: 0,
                                           space: colorSpace,
                                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
        
        ctx.concatenate(transform)
        
        switch imageOrientation {
        case UIImage.Orientation.left,
             UIImage.Orientation.leftMirrored,
             UIImage.Orientation.right,
             UIImage.Orientation.rightMirrored:
            ctx.draw(cgImage, in: CGRect(origin: CGPoint.zero, size: size))
        default:
            ctx.draw(cgImage, in: CGRect(origin: CGPoint.zero, size: size))
            break
        }
        
        if let cgImage: CGImage = ctx.makeImage() {
            return UIImage(cgImage: cgImage)
        }
        
        return nil
    }
    
}

fileprivate func LGDegreesToRadians(degrees : CGFloat) -> CGFloat {
    return degrees * CGFloat.pi / 180.0
}
