//
//  LGImageCoder.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2017/9/18.
//  Copyright © 2017年 龚杰洪. All rights reserved.
//

import Foundation
import WebP
import MobileCoreServices
import ImageIO
import Accelerate
import Photos

/// 图片类型枚举
///
/// - unknow: unknow
/// - jpeg: jpg,jpeg
/// - jpeg2000: jp2
/// - tiff: tiff,tif
/// - bmp: bmp
/// - ico: ico
/// - gif: gif
/// - png: png
/// - webp: webp
/// - heic: heic
/// - other: other image format
public enum LGImageType: Int {
    case unknow = 0
    case jpeg
    case jpeg2000
    case tiff
    case bmp
    case ico
    case gif
    case png
    case webp
    case heic
    case other
}

public enum LGImageDispose: Int {
    case none = 0
    case background
    case previous
}

public enum LGImageBlend: Int {
    case none = 0
    case over
}

public class LGImageFrame {
    public var index: Int = 0
    public var width: Int = 0
    public var height: Int = 0
    public var offsetX: Int = 0
    public var offsetY: Int = 0
    public var duration: TimeInterval = 0.0
    public var dispose: LGImageDispose = .none
    public var blend: LGImageBlend = .none
    public var image: UIImage?
    
    public init(frameWithImage image: UIImage) {
        self.image = image
    }
    
    public init() {
        
    }
    
    public func copy() -> LGImageFrame {
        let newValue = LGImageFrame()
        newValue.index = self.index
        newValue.width = self.width
        newValue.height = self.height
        newValue.offsetX = self.offsetX
        newValue.offsetY = self.offsetY
        newValue.duration = self.duration
        newValue.dispose = self.dispose
        newValue.blend = self.blend
        newValue.image = self.image?.copy() as? UIImage
        return newValue
    }
}

fileprivate class LGImageDecoderFrame: LGImageFrame {
    fileprivate var hasAlpha: Bool = false
    fileprivate var isFullSize: Bool = false
    fileprivate var blendFromIndex: Int = 0
    
    fileprivate override init() {
        super.init()
    }
    
    fileprivate override func copy() -> LGImageDecoderFrame {
        let frame: LGImageDecoderFrame = LGImageDecoderFrame()
        frame.index = self.index
        frame.width = self.width
        frame.height = self.height
        frame.offsetX = self.offsetX
        frame.offsetY = self.offsetY
        frame.duration = self.duration
        frame.dispose = self.dispose
        frame.blend = self.blend
        frame.image = self.image?.copy() as? UIImage
        frame.hasAlpha = self.hasAlpha
        frame.isFullSize = self.isFullSize
        frame.blendFromIndex = self.blendFromIndex
        return frame;
    }
}

/// 图像数据解码器，可以解码完整的图片和下载的时候解码下载中的数据
public class LGImageDecoder {
    
    public private(set) var imageData: Data?
    public private(set) var imageType: LGImageType = LGImageType.unknow
    public private(set) var scale: CGFloat = 0.0
    public private(set) var frameCount: Int = 0
    public private(set) var loopCount: Int = 0
    public private(set) var width: Int = 0
    public private(set) var height: Int = 0
    public private(set) var isFinalized: Bool = false
    
    /// CGContext.draw() 解压缩时会生成位图，导致内存暴增，所以超大的图片没有必要进行解压缩
    /// 此处限制像素点超过1024px * 1024px的图片不做解压缩，也可以修改此参数自定义最大大小
    public static var maxDecompressImageSize: Int = 1_024 * 1_024
    
    
    deinit {
        if _webpSource != nil {
            WebPDemuxDelete(_webpSource)
        }
        pthread_mutex_destroy(&_lock)
    }
    
    public init(withScale scale: CGFloat) {
        if scale <= 0 {
            self.scale = 1
        } else {
            self.scale = scale
        }
        
        var attr: pthread_mutexattr_t = pthread_mutexattr_t()
        pthread_mutexattr_init(&attr)
        pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE)
        pthread_mutex_init(&_lock, &attr)
        pthread_mutexattr_destroy(&attr)
    }
    
    public convenience init(withData data: Data?, scale: CGFloat) throws {
        guard data != nil else {
            throw LGImageCoderError.imageDataIsEmpty
        }
        self.init(withScale: scale)
        _ = self.updateData(data: data!, final: true)
        
        if self.imageType == LGImageType.heic {
            if #available(iOS 11, *) {
                
            } else {
                println("heic only supports iOS11 or above")
                throw LGImageCoderError.imageTypeNotSupport(type: LGImageType.heic)
            }
        }
        
        guard self.frameCount != 0 else {
            throw LGImageCoderError.frameCountInvalid
        }
    }
    
    public func updateData(data: Data, final: Bool) -> Bool {
        var result = false
        pthread_mutex_lock(&_lock)
        result = _updateData(data: data, final: final)
        pthread_mutex_unlock(&_lock)
        return result
    }
    
    public func frameAtIndex(index: Int, decodeForDisplay: Bool) -> LGImageFrame? {
        var result: LGImageFrame? = nil
        pthread_mutex_lock(&_lock)
        result = _frameAtIndex(index: index, decodeForDisplay: decodeForDisplay)
        pthread_mutex_unlock(&_lock)
        return result
    }
    
    public func largePictureCreateThumbnail() -> UIImage? {
        var result: UIImage? = nil
        pthread_mutex_lock(&_lock)
        if self._source != nil {
            let maxPixelSize = UIScreen.main.nativeBounds.width
            let thumbnailOptions = [kCGImageSourceCreateThumbnailWithTransform: true,
                                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                                    kCGImageSourceThumbnailMaxPixelSize: maxPixelSize] as [CFString : Any]
            if CGImageSourceGetCount(self._source!) > 0 {
                if let cgImage = CGImageSourceCreateThumbnailAtIndex(self._source!,
                                                                     0,
                                                                     thumbnailOptions as CFDictionary)
                {
                    result = UIImage(cgImage: cgImage)
                }
            }
        }
        pthread_mutex_unlock(&_lock)
        return result
    }
    
    public func frameDuration(atIndex index: Int) -> TimeInterval {
        var result: TimeInterval = 0.0
        _framesLock.lg_lock()
        if index < _frames.count {
            result = _frames[index].duration
        }
        _framesLock.lg_unlock()
        return result
    }
    
    public func frameProperties(atIndex index: Int) -> [String: Any]? {
        var result: [String: Any]?
        pthread_mutex_lock(&_lock)
        result = _frameProperties(at: index)
        pthread_mutex_unlock(&_lock)
        return result
    }
    
    public func imageProperties() -> [String: Any]? {
        var result: [String: Any]?
        pthread_mutex_lock(&_lock)
        result = _imageProperties()
        pthread_mutex_unlock(&_lock)
        return result
    }
    
    // MARK: -  private
    fileprivate var _lock: pthread_mutex_t = pthread_mutex_t()
    
    fileprivate var _sourceTypeDetected: Bool = false
    
    fileprivate var _source: CGImageSource?
    
    fileprivate var _apngSource: CGImageSource?
    
    fileprivate var _webpSource: OpaquePointer? // WebpDemux struct
    
    fileprivate var _orientation: UIImage.Orientation = UIImage.Orientation.up
    
    fileprivate var _framesLock: DispatchSemaphore = DispatchSemaphore(value: 1)
    
    fileprivate var _frames: [LGImageDecoderFrame] = [LGImageDecoderFrame]()
    
    fileprivate var _needBlend: Bool = false
    
    fileprivate var _blendFrameIndex: Int = Int(Int16.max)
    
    fileprivate var _blendCanvas: CGContext?
}

extension LGImageDecoder {
    fileprivate func _updateData(data: Data, final: Bool) -> Bool {
        if self.isFinalized {
            return false
        }
        if (self.imageData != nil) && data.count < self.imageData!.count {
            return false
        }
        
        self.isFinalized = final
        self.imageData = data
        
        guard let tempData = self.imageData else {
            return false
        }
        
        let type = LGGetImageDetectType(data: tempData as CFData)
        if _sourceTypeDetected {
            if self.imageType != type {
                return false
            } else {
                _updateSource()
            }
        } else {
            if (tempData.count > 16) {
                imageType = type
                _sourceTypeDetected = true
                _updateSource()
            }
        }
        return true
    }
    
    fileprivate func _updateSource() {
        switch imageType {
        case LGImageType.webp:
            _updateSourceWebP()
            break
        default:
            _updateSourceImageIO()
            break
        }
    }
    
    fileprivate func _updateSourceImageIO() {
        width = 0
        height = 0
        _orientation = UIImage.Orientation.up
        loopCount = 0
        _framesLock.lg_lock()
        _frames.removeAll()
        _framesLock.lg_unlock()
        
        if _source != nil {
            CGImageSourceUpdateData(_source!, self.imageData! as CFData, isFinalized)
        } else {
            if (isFinalized) {
                _source = CGImageSourceCreateWithData(self.imageData! as CFData, nil)
            } else {
                _source = CGImageSourceCreateIncremental(nil)
                if _source != nil {
                    CGImageSourceUpdateData(_source!, self.imageData! as CFData, isFinalized)
                }
            }
        }
        
        guard let source = _source else {
            return
        }
        
        frameCount = CGImageSourceGetCount(source)
        
        guard frameCount != 0 else {
            return
        }
        
        if isFinalized {
            if imageType == LGImageType.gif {
                if let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any] {
                    if let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
                        if let loop = gif[kCGImagePropertyGIFLoopCount] as? Int {
                            loopCount = loop
                        }
                    }
                }
            }
        } else {
            frameCount = 1
        }
        
        var frames = [LGImageDecoderFrame]()
        for index in 0..<frameCount {
            let frame = LGImageDecoderFrame()
            frame.index = index
            frame.blendFromIndex = index
            frame.hasAlpha = true
            frame.isFullSize = true
            frames.append(frame)
            
            if let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] {
                var duration: TimeInterval = 0.0
                var width: Int = 0, height: Int = 0
                
                width = (properties[kCGImagePropertyPixelWidth] as? Int) ?? 0
                height = (properties[kCGImagePropertyPixelHeight] as? Int) ?? 0
                
                if self.imageType == LGImageType.gif {
                    if let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
                        if let tempDuration = gif[kCGImagePropertyGIFUnclampedDelayTime] as? TimeInterval {
                            duration = tempDuration
                        } else if let tempDuration = gif[kCGImagePropertyGIFDelayTime] as? TimeInterval {
                            duration = tempDuration
                        }
                        
                    }
                }
                
                frame.width = width
                frame.height = height
                frame.duration = duration
                
                if index == 0 && (self.width + self.height == 0) {
                    self.width = width
                    self.height = height
                    if let orientation = properties[kCGImagePropertyOrientation] as? UInt32 {
                        _orientation = LGUIImageOrientationFromCGImagePropertyOrientationValue(value: orientation)
                    }
                }
            }
        }
        _framesLock.lg_lock()
        _frames += frames
        _framesLock.lg_unlock()
        
    }
    
    fileprivate func _updateSourceWebP() {
        self.width = 0
        self.height = 0
        self.loopCount = 0
        
        if _webpSource != nil {
            WebPDemuxDelete(_webpSource)
        }
        _webpSource = nil
        
        _framesLock.lg_lock()
        _frames.removeAll()
        _framesLock.lg_unlock()
        
        guard let imageData = self.imageData else {
            return
        }
        
        var demuxer: OpaquePointer?
        
        let pointer = imageData.withUnsafeBytes { (bytes) in
            return bytes.baseAddress?.assumingMemoryBound(to: UInt8.self)
        }
        
        var webpData = WebPData(bytes: pointer, size: imageData.count)
        demuxer = WebPDemux(&webpData)
        
        if demuxer == nil {
            return
        }
        
        /*public var ANIMATION_FLAG: WebPFeatureFlags { get }
         public var XMP_FLAG: WebPFeatureFlags { get }
         public var EXIF_FLAG: WebPFeatureFlags { get }
         public var ALPHA_FLAG: WebPFeatureFlags { get }
         public var ICCP_FLAG: WebPFeatureFlags { get }
         public var ALL_VALID_FLAGS: WebPFeatureFlags { get }*/
        let webpFrameCount = WebPDemuxGetI(demuxer, WEBP_FF_FRAME_COUNT)
        let webpLoopCount =  WebPDemuxGetI(demuxer, WEBP_FF_LOOP_COUNT)
        let canvasWidth = WebPDemuxGetI(demuxer, WEBP_FF_CANVAS_WIDTH)
        let canvasHeight = WebPDemuxGetI(demuxer, WEBP_FF_CANVAS_HEIGHT)
        
        if (webpFrameCount == 0 || canvasWidth < 1 || canvasHeight < 1) {
            WebPDemuxDelete(demuxer)
            return
        }
        
        var frames = [LGImageDecoderFrame]()
        
        var needBlend = false
        var iterIndex: Int = 0
        var lastBlendIndex: Int = 0
        
        var iter: WebPIterator = WebPIterator()
        
        if WebPDemuxGetFrame(demuxer, 1, &iter) != 0 {
            repeat {
                let frame = LGImageDecoderFrame()
                frames.append(frame)
                if iter.dispose_method == WEBP_MUX_DISPOSE_BACKGROUND {
                    frame.dispose = LGImageDispose.background
                }
                
                if iter.blend_method == WEBP_MUX_BLEND {
                    frame.blend = LGImageBlend.over
                }
                
                let canvasWidth = WebPDemuxGetI(demuxer, WEBP_FF_CANVAS_WIDTH)
                let canvasHeight = WebPDemuxGetI(demuxer, WEBP_FF_CANVAS_HEIGHT)
                frame.index = iterIndex
                frame.duration = TimeInterval(iter.duration) / 1000.0
                frame.width = Int(iter.width)
                frame.height = Int(iter.height)
                frame.hasAlpha = (iter.has_alpha != 0)
                frame.blend = (iter.blend_method == WEBP_MUX_BLEND) ? LGImageBlend.over : LGImageBlend.none
                frame.offsetX = Int(iter.x_offset)
                frame.offsetY = Int(canvasHeight) - Int(iter.y_offset) - Int(iter.height)
                
                let sizeEqualsToCanvas = (iter.width == canvasWidth && iter.height == canvasHeight)
                let offsetIsZero = (iter.x_offset == 0 && iter.y_offset == 0)
                frame.isFullSize = (sizeEqualsToCanvas && offsetIsZero)
                
                if ((frame.blend == LGImageBlend.none || !frame.hasAlpha) && frame.isFullSize) {
                    lastBlendIndex = iterIndex
                    frame.blendFromIndex = lastBlendIndex
                } else {
                    if (frame.dispose != LGImageDispose.none && frame.isFullSize) {
                        frame.blendFromIndex = lastBlendIndex
                        lastBlendIndex = iterIndex + 1
                    } else {
                        frame.blendFromIndex = lastBlendIndex
                    }
                }
                if (frame.index != frame.blendFromIndex) {
                    needBlend = true
                }
                iterIndex += 1
            } while WebPDemuxNextFrame(&iter) != 0
            WebPDemuxReleaseIterator(&iter)
        }
        if (frames.count != webpFrameCount) {
            WebPDemuxDelete(demuxer)
            return
        }
        
        self.width = Int(canvasWidth)
        self.height = Int(canvasHeight)
        self.frameCount = frames.count
        self.loopCount = Int(webpLoopCount)
        _needBlend = needBlend
        _webpSource = demuxer
        _framesLock.lg_lock()
        _frames += frames
        _framesLock.lg_unlock()
    }
    
    fileprivate func _newBlendedImageWith(frame: LGImageDecoderFrame) -> CGImage? {
        var image: CGImage? = nil
        if frame.dispose == LGImageDispose.previous {
            if frame.blend == LGImageBlend.over {
                let previousImage = _blendCanvas?.makeImage()
                let unblendImage = _newUnblendedImageAtIndex(index: frame.index, extendToCanvas: false)
                if unblendImage != nil {
                    _blendCanvas?.draw(unblendImage!, in: CGRect(x: frame.offsetX,
                                                                 y: frame.offsetY,
                                                                 width: frame.width,
                                                                 height: frame.height))
                }
                image = _blendCanvas?.makeImage()
                _blendCanvas?.clear(CGRect(x: 0, y: 0, width: self.width, height: self.height))
                if previousImage != nil {
                    _blendCanvas?.draw(previousImage!, in: CGRect(x: 0, y: 0, width: self.width, height: self.height))
                }
            } else {
                let previousImage = _blendCanvas?.makeImage()
                let unblendImage = _newUnblendedImageAtIndex(index: frame.index, extendToCanvas: false)
                if unblendImage != nil {
                    _blendCanvas?.clear(CGRect(x: frame.offsetX,
                                               y: frame.offsetY,
                                               width: frame.width,
                                               height: frame.height))
                    _blendCanvas?.draw(unblendImage!, in: CGRect(x: frame.offsetX,
                                                                 y: frame.offsetY,
                                                                 width: frame.width,
                                                                 height: frame.height))
                }
                image = _blendCanvas?.makeImage()
                _blendCanvas?.clear(CGRect(x: 0, y: 0, width: self.width, height: self.height))
                if previousImage != nil {
                    _blendCanvas?.draw(previousImage!, in: CGRect(x: 0, y: 0, width: self.width, height: self.height))
                }
            }
        } else if frame.dispose == LGImageDispose.background {
            if frame.blend == LGImageBlend.over {
                let unblendImage = _newUnblendedImageAtIndex(index: frame.index, extendToCanvas: false)
                if unblendImage != nil {
                    _blendCanvas?.draw(unblendImage!, in: CGRect(x: frame.offsetX,
                                                                 y: frame.offsetY,
                                                                 width: frame.width,
                                                                 height: frame.height))
                }
                image = _blendCanvas?.makeImage()
                
                _blendCanvas?.clear(CGRect(x: frame.offsetX,
                                           y: frame.offsetY,
                                           width: frame.width,
                                           height: frame.height))
            } else {
                let unblendImage = _newUnblendedImageAtIndex(index: frame.index, extendToCanvas: false)
                if unblendImage != nil {
                    _blendCanvas?.clear(CGRect(x: frame.offsetX,
                                               y: frame.offsetY,
                                               width: frame.width,
                                               height: frame.height))
                    _blendCanvas?.draw(unblendImage!, in: CGRect(x: frame.offsetX,
                                                                 y: frame.offsetY,
                                                                 width: frame.width,
                                                                 height: frame.height))
                }
                image = _blendCanvas?.makeImage()
                _blendCanvas?.clear(CGRect(x: frame.offsetX,
                                           y: frame.offsetY,
                                           width: frame.width,
                                           height: frame.height))
            }
        } else {
            if frame.blend == LGImageBlend.over {
                let unblendImage = _newUnblendedImageAtIndex(index: frame.index, extendToCanvas: false)
                if unblendImage != nil {
                    _blendCanvas?.draw(unblendImage!, in: CGRect(x: frame.offsetX,
                                                                 y: frame.offsetY,
                                                                 width: frame.width,
                                                                 height: frame.height))
                }
                image = _blendCanvas?.makeImage()
            } else {
                let unblendImage = _newUnblendedImageAtIndex(index: frame.index, extendToCanvas: false)
                if unblendImage != nil {
                    _blendCanvas?.clear(CGRect(x: frame.offsetX,
                                               y: frame.offsetY,
                                               width: frame.width,
                                               height: frame.height))
                    _blendCanvas?.draw(unblendImage!, in: CGRect(x: frame.offsetX,
                                                                 y: frame.offsetY,
                                                                 width: frame.width,
                                                                 height: frame.height))
                }
                image = _blendCanvas?.makeImage()
            }
        }
        
        return image
    }
    
    
    
    fileprivate func _frameAtIndex(index: Int, decodeForDisplay: Bool) -> LGImageFrame? {
        if index >= _frames.count  {
            return nil
        }
        let frame = _frames[index].copy()
        var decoded: Bool = false
        var extendToCanvas: Bool = false
        
        if imageType != LGImageType.ico && decodeForDisplay {
            extendToCanvas = true
        }
        
        if !_needBlend {
            var image = _newUnblendedImageAtIndex(index: index,
                                                  extendToCanvas: extendToCanvas,
                                                  decoded: &decoded)
            if image == nil {
                return nil
            }
            
            if decodeForDisplay && !decoded {
                if let imageDecoded = LGCGImageCreateDecodedCopy(image: image, decodeForDisplay: true) {
                    image = imageDecoded
                    decoded = true
                }
            }
            
            let uiImage = UIImage(cgImage: image!, scale: self.scale, orientation: _orientation)
            uiImage.lg_isDecodedForDisplay = true
            frame.image = uiImage
            return frame
        }
        
        if !_createBlendContextIfNeeded() {
            return nil
        }
        
        var image: CGImage? = nil
        
        if _blendFrameIndex + 1 == frame.index {
            image = _newBlendedImageWith(frame: frame)
            _blendFrameIndex = index
        } else {
            _blendFrameIndex = 0
            _blendCanvas?.clear(CGRect(x: 0, y: 0, width: self.width, height: self.height))
            
            if frame.blendFromIndex == frame.index {
                if let unblendedImage = _newUnblendedImageAtIndex(index: index, extendToCanvas: false) {
                    _blendCanvas?.draw(unblendedImage, in: CGRect(x: frame.offsetX,
                                                                  y: frame.offsetY,
                                                                  width: frame.width,
                                                                  height: frame.height))
                }
                
                image = _blendCanvas?.makeImage()
                if frame.dispose == LGImageDispose.background {
                    _blendCanvas?.clear(CGRect(x: frame.offsetX,
                                               y: frame.offsetY,
                                               width: frame.width,
                                               height: frame.height))
                }
                _blendFrameIndex = index
            } else {
                for index in frame.blendFromIndex...frame.index {
                    if index == frame.index {
                        if image == nil {
                            image = _newBlendedImageWith(frame: frame)
                        } else {
                            _blendImageWithFrame(frame: frame)
                        }
                    }
                }
            }
        }
        if image == nil {
            return nil
        }
        let uiImage = UIImage(cgImage: image!,
                              scale: self.scale,
                              orientation: _orientation)
        
        
        uiImage.lg_isDecodedForDisplay = true
        frame.image = uiImage
        if extendToCanvas {
            frame.width = self.width
            frame.height = self.height
            frame.offsetX = 0
            frame.offsetY = 0
            frame.dispose = LGImageDispose.none
            frame.blend = LGImageBlend.none
        }
        return frame
    }
    
    fileprivate func _createBlendContextIfNeeded() -> Bool {
        if _blendCanvas == nil {
            _blendFrameIndex = Int(Int16.max)
            let bitmapInfo = LGCGBitmapByteOrder32Host.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
            _blendCanvas = CGContext(data: nil,
                                     width: self.width,
                                     height: self.height,
                                     bitsPerComponent: 8,
                                     bytesPerRow: 0,
                                     space: LGCGColorSpaceDeviceRGB,
                                     bitmapInfo: bitmapInfo)
        }
        return _blendCanvas != nil
    }
    
    fileprivate func _frameProperties(at index: Int) -> [String: Any]? {
        if index >= _frames.count {
            return nil
        }
        if _source == nil {
            return nil
        }
        return CGImageSourceCopyPropertiesAtIndex(_source!, index, nil) as? [String: Any]
    }
    
    fileprivate func _imageProperties() -> [String: Any]? {
        if _source == nil {
            return nil
        }
        return CGImageSourceCopyProperties(_source!, nil) as? [String: Any]
    }
    
    fileprivate func _blendImageWithFrame(frame: LGImageDecoderFrame) {
        if frame.dispose == LGImageDispose.previous {
        } else if frame.dispose == LGImageDispose.background {
            _blendCanvas?.clear(CGRect(x: frame.offsetX,
                                       y: frame.offsetY,
                                       width: frame.width,
                                       height: frame.height))
        } else {
            if frame.blend == LGImageBlend.over {
                let unblendImage = _newUnblendedImageAtIndex(index: frame.index, extendToCanvas: false)
                if unblendImage != nil {
                    _blendCanvas?.draw(unblendImage!, in: CGRect(x: frame.offsetX,
                                                                 y: frame.offsetY,
                                                                 width: frame.width,
                                                                 height: frame.height))
                }
            } else {
                _blendCanvas?.clear(CGRect(x: frame.offsetX,
                                           y: frame.offsetY,
                                           width: frame.width,
                                           height: frame.height))
                let unblendImage = _newUnblendedImageAtIndex(index: frame.index, extendToCanvas: false)
                if unblendImage != nil {
                    _blendCanvas?.draw(unblendImage!, in: CGRect(x: frame.offsetX,
                                                                 y: frame.offsetY,
                                                                 width: frame.width,
                                                                 height: frame.height))
                }
            }
        }
    }
    
    fileprivate func _newUnblendedImageAtIndex(index: Int,
                                               extendToCanvas: Bool) -> CGImage? {
        var boolValue: Bool = false
        return _newUnblendedImageAtIndex(index: index, extendToCanvas: extendToCanvas, decoded: &boolValue)
    }
    
    fileprivate func _newUnblendedImageAtIndex(index: Int,
                                               extendToCanvas: Bool,
                                               decoded: inout Bool) -> CGImage? {
        if !isFinalized && index > 0 {
            return nil
        }
        if _frames.count <= index {
            return nil
        }
        
        if _source != nil {
            let options = [kCGImageSourceShouldCache: true] as CFDictionary
            var image = CGImageSourceCreateImageAtIndex(_source!, index, options)
            if image != nil {
                if extendToCanvas {
                    let width = image!.width
                    let height = image!.height
                    if width == self.width && height == self.height {
                        if let imageExtended = LGCGImageCreateDecodedCopy(image: image!, decodeForDisplay: true) {
                            image = imageExtended
                            decoded = true
                        }
                    } else {
                        let biteOrderValue = LGCGBitmapByteOrder32Host.rawValue
                        let alphaInfoValue = CGImageAlphaInfo.premultipliedFirst.rawValue
                        let bigmapInfo = biteOrderValue | alphaInfoValue
                        if let context = CGContext(data: nil,
                                                   width: width,
                                                   height: height,
                                                   bitsPerComponent: 8,
                                                   bytesPerRow: 0,
                                                   space: LGCGColorSpaceDeviceRGB,
                                                   bitmapInfo: bigmapInfo) {
                            context.draw(image!, in: CGRect(x: 0,
                                                            y: self.height - height,
                                                            width: width,
                                                            height: height))
                            if let imageExtended = context.makeImage() {
                                image = imageExtended;
                                decoded = true
                            }
                            
                        }
                    }
                }
            }
            return image
        }
        
        if _webpSource != nil {
            var iter: WebPIterator = WebPIterator()
            if WebPDemuxGetFrame(_webpSource, Int32(index + 1), &iter) == 0 {
                return nil
            }
            let frameWidth = iter.width
            let frameHeight = iter.height
            if frameWidth < 1 || frameHeight < 1 {
                return nil
            }
            
            let width = extendToCanvas ? self.width : Int(frameWidth)
            let height = extendToCanvas ? self.height : Int(frameHeight)
            
            if width > self.width || height > self.height {
                return nil
            }
            let payload = iter.fragment.bytes
            let payloadSize = iter.fragment.size
            
            var config: WebPDecoderConfig = WebPDecoderConfig()
            
            if WebPInitDecoderConfig(&config) == 0 {
                WebPDemuxReleaseIterator(&iter)
                return nil
            }
            
            if WebPGetFeatures(payload, payloadSize, &config.input) != VP8_STATUS_OK {
                WebPDemuxReleaseIterator(&iter)
                return nil
            }
            
            let bitsPerComponent = 8
            let bitsPerPixel = 32
            let bytesPerRow = LGImageByteAlign(size: bitsPerPixel / 8 * width, alignment: 32)
            let length = bytesPerRow * height
            let bitmapInfo = CGBitmapInfo(rawValue: LGCGBitmapByteOrder32Host.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
            config.output.colorspace = MODE_bgrA
            config.output.is_external_memory = 1 // 使用外部buffer
            var pixels = [UInt8](repeating: 0, count: length) // 数据buffer
            
            // 为什么会有这么丑陋的代码？因为强迫症要解决悬指针警告啊，沁
            @inline(__always) func setConfigsRGBA( _ tempConfig: inout WebPDecoderConfig,
                                                   pointer: UnsafeMutablePointer<UInt8>)
            {
                tempConfig.output.u.RGBA.rgba = pointer
            }
            setConfigsRGBA(&config, pointer: &pixels)
            
            config.output.u.RGBA.stride = Int32(bytesPerRow)
            config.output.u.RGBA.size = length
            
            
            
            let result = WebPDecode(payload, payloadSize, &config)
            if result != VP8_STATUS_OK && result != VP8_STATUS_NOT_ENOUGH_DATA {
                WebPDemuxReleaseIterator(&iter)
                return nil
            }
            WebPDemuxReleaseIterator(&iter)
            
            if extendToCanvas && (iter.x_offset != 0 || iter.y_offset != 0) {
                var temp = [UInt8](repeating: 0, count: length)
                var pixelsAddress: UnsafeMutableRawPointer?
                withUnsafeMutableBytes(of: &pixels) { (pointer) in
                    pixelsAddress = pointer.baseAddress
                }
                
                var tempAddress: UnsafeMutableRawPointer?
                withUnsafeMutableBytes(of: &temp) { (pointer) in
                    tempAddress = pointer.baseAddress
                }
                
                var src: vImage_Buffer = vImage_Buffer(data: pixelsAddress,
                                                       height: vImagePixelCount(height),
                                                       width: vImagePixelCount(width),
                                                       rowBytes: bytesPerRow)
                
                var dest: vImage_Buffer = vImage_Buffer(data: tempAddress,
                                                        height: vImagePixelCount(height),
                                                        width: vImagePixelCount(width),
                                                        rowBytes: bytesPerRow)
                let cgTransform = CGAffineTransform(a: 1,
                                                    b: 0,
                                                    c: 0,
                                                    d: 1,
                                                    tx: CGFloat(iter.x_offset),
                                                    ty: CGFloat(-iter.y_offset))
                var transform: vImage_CGAffineTransform = cgTransform.vImageAffinetransform
                
                
                var backColor: [UInt8] = [UInt8](repeating: 0, count: 4)
                let error = vImageAffineWarpCG_ARGB8888(&src, &dest, nil, &transform, &backColor, vImage_Flags(kvImageBackgroundColorFill))
                if error == kvImageNoError {
                    memcpy(&pixels, &temp, length)
                }
            }
            
            guard let resultData = CFDataCreate(kCFAllocatorDefault, &pixels, length) else {
                return nil
            }
            let provider = CGDataProvider(data: resultData)
            
            if provider == nil {
                return nil
            }
            
            let image = CGImage(width: width,
                                height: height,
                                bitsPerComponent: bitsPerComponent,
                                bitsPerPixel: bitsPerPixel,
                                bytesPerRow: bytesPerRow,
                                space: LGCGColorSpaceDeviceRGB,
                                bitmapInfo: bitmapInfo,
                                provider: provider!,
                                decode: nil,
                                shouldInterpolate: false,
                                intent: CGColorRenderingIntent.defaultIntent)
            decoded = true
            return image
        }
        return nil
    }
}

public class LGImageEncoder {
    // MARK: -  public vaibles
    public private(set) var imageType: LGImageType = LGImageType.unknow
    public private(set) var isLossless: Bool = false
    public var quality: CGFloat = 1.0 {
        didSet {
            if quality < 0.0 {
                quality = 0.0
            } else if quality > 1 {
                quality = 1
            } else {
                // 原样
            }
        }
    }
    public var loopCount: Int = 0
    
    // MARK: -  private varibales 
    fileprivate var _images: [Any] = [Any]()
    fileprivate var _durations: [TimeInterval] = [TimeInterval]()
    
    public init(with type: LGImageType) throws {
        if type == LGImageType.unknow || type == LGImageType.other {
            throw LGImageCoderError.imageTypeInvalid
        }
        
        self.imageType = type
        switch type {
        case LGImageType.jpeg, LGImageType.jpeg2000:
            quality = 0.9
            break
        case LGImageType.webp:
            quality = 0.75
            break
        default:
            quality = 1
            isLossless = true
        }
    }
    
    public func add(image: UIImage, duration: TimeInterval) {
        if image.cgImage == nil {
            return
        }
        _images.append(image)
        _durations.append(duration < 0 ? 0.0 : duration)
    }
    
    public func add(imageWith data: Data, duration: TimeInterval) {
        if data.count == 0 {
            return
        }
        _images.append(data)
        _durations.append(duration < 0 ? 0.0 : duration)
    }
    
    public func add(imageWith filePath: String, duration: TimeInterval) {
        if filePath.lg_length == 0 {
            return
        }
        if let url = URL(string: filePath) {
            _images.append(url)
            _durations.append(duration < 0 ? 0.0 : duration)
        }
    }
    
    public func encode() -> Data? {
        if _images.count == 0 {
            return nil
        }
        if _imageIOAvaliable() {
            return nil
        }
        return nil
    }
}


// MARK: - LGImageEncoder fileprivate methods
extension LGImageEncoder {
    fileprivate func _imageIOAvaliable() -> Bool {
        var result: Bool = false
        switch self.imageType {
        case LGImageType.jpeg2000,
             LGImageType.jpeg,
             LGImageType.tiff,
             LGImageType.bmp,
             LGImageType.ico,
             LGImageType.gif:
            result = _images.count > 0
            break
        case LGImageType.png:
            result = _images.count == 1
            break
        default:
            break
        }
        
        return result
    }
    
    fileprivate func _newCGImage(fromIndex index: Int, decode: Bool) -> CGImage? {
        var uiImage: UIImage? = nil
        let imageSrc = _images[index]
        if let tempImage = imageSrc as? UIImage {
            uiImage = tempImage
        } else if let tempUrl = imageSrc as? URL {
            uiImage = UIImage(contentsOfFile: tempUrl.absoluteString)
        } else if let tempData = imageSrc as? Data {
            uiImage = UIImage(data: tempData)
        }
        
        guard uiImage != nil else {
            return nil
        }
        
        guard let cgImage = uiImage?.cgImage else {
            return nil
        }
        let bitmapInfoValue = LGCGBitmapByteOrder32Host.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        let bitmapInfo = CGBitmapInfo(rawValue: bitmapInfoValue)
        if uiImage!.imageOrientation != UIImage.Orientation.up {
            return LGCGImageCreateCopyWith(image: cgImage,
                                           orientation: uiImage!.imageOrientation,
                                           destBitmapInfo: bitmapInfo)
        }
        
        if decode {
            return LGCGImageCreateDecodedCopy(image: cgImage, decodeForDisplay: true)
        }
        
        return cgImage
    }
}

/// 核心主要是4个连续的字符组成一个整数，方便比较
@inline(__always) func _four_cc(c1: UInt32, c2: UInt32, c3: UInt32, c4: UInt32) -> UInt32 {
    return (c4 << 24) | (c3 << 16) | (c2 << 8) | (c1)
}

/// 同上理
@inline(__always) func _tow_cc(c1: UInt16, c2: UInt16) -> UInt16 {
    return (c2 << 8) | (c1)
}


/// 判定图片的类型
///
/// - Parameter data: 图片数据
/// - Returns: LGImageType
public func LGGetImageDetectType(data: CFData?) -> LGImageType {
    guard let data = data else {
        return LGImageType.unknow
    }
    
    let length = CFDataGetLength(data)
    if length < 16 {
        return LGImageType.unknow
    }
    
    guard let bytes = CFDataGetBytePtr(data) else {
        return LGImageType.unknow
    }
    
    let magicNum4 = bytes.withMemoryRebound(to: UInt32.self, capacity: 1, { $0.pointee })
    switch magicNum4 {
        /*heic 文件头 ftypheic (00 00 00 18 66 74 79 70 68 65 69 63 00 00 00 00)*/
    case _four_cc(c1: 0x00, c2: 0x00, c3: 0x00, c4: 0x18):
        
        let ftyp = _four_cc(c1: 0x66, c2: 0x74, c3: 0x79, c4: 0x70)
        let heic = _four_cc(c1: 0x68, c2: 0x65, c3: 0x69, c4: 0x63)
        
        let temp1 = (bytes + 4).withMemoryRebound(to: UInt32.self,
                                                  capacity: 1,
                                                  { $0.pointee })
        let temp2 = (bytes + 8).withMemoryRebound(to: UInt32.self,
                                                  capacity: 1,
                                                  { $0.pointee })
        if temp1 == ftyp && temp2 == heic {
            return LGImageType.heic
        }
        break
        /*'R' = 0x52,'I' = 0x49,'F' = 0x46,'F' = 0x46 RIFF*/
    case _four_cc(c1: 0x52, c2: 0x49, c3: 0x46, c4: 0x46):
        let temp = (bytes + 8).withMemoryRebound(to: UInt32.self, capacity: 1, { $0.pointee })
        /*'W' = 0x57,'E' = 0x45,'B' = 0x42,'P' = 0x50 WEBP*/
        if temp == _four_cc(c1: 0x57, c2: 0x45, c3: 0x42, c4: 0x50) {
            return LGImageType.webp
        }
        break
        /*big/little tiff*/
    case _four_cc(c1: 0x4D, c2: 0x4D, c3: 0x00, c4: 0x2A), _four_cc(c1: 0x49, c2: 0x49, c3: 0x2A, c4: 0x00):
        return LGImageType.tiff
        /*ico*/
    case _four_cc(c1: 0x00, c2: 0x00, c3: 0x01, c4: 0x00), _four_cc(c1: 0x00, c2: 0x00, c3: 0x02, c4: 0x00):
        return LGImageType.ico
        /*gif*/
    case _four_cc(c1: 0x47, c2: 0x49, c3: 0x46, c4: 0x38):
        return LGImageType.gif
        /*png*/
    case _four_cc(c1: 0x89, c2: 0x50, c3: 0x4E, c4: 0x47):
        let temp = (bytes + 4).withMemoryRebound(to: UInt32.self, capacity: 1, { $0.pointee })
        if temp == _four_cc(c1: 0x0D, c2: 0x0A, c3: 0x1A, c4: 0x0A) {
            return LGImageType.png
        }
        break
    default:
        break
    }
    
    
    let migicNum2 = bytes.withMemoryRebound(to: UInt16.self, capacity: 1, { $0.pointee })
    switch migicNum2 {
        /*bmp*/
    case _tow_cc(c1: 0x42, c2: 0x41), // 'B', 'A'
    _tow_cc(c1: 0x42, c2: 0x4D), // 'B', 'M'
    _tow_cc(c1: 0x49, c2: 0x43), // 'I', 'C'
    _tow_cc(c1: 0x43, c2: 0x49), // 'C', 'I'
    _tow_cc(c1: 0x50, c2: 0x49), // 'P', 'I'
    _tow_cc(c1: 0x43, c2: 0x50): // 'C', 'P'
        return LGImageType.bmp
        /*jpeg2000*/
    case _tow_cc(c1: 0xFF, c2: 0x4F):
        return LGImageType.jpeg2000
    default:
        break
    }
    
    /*jpeg2000 \377\330\377 这些数字为8进制 对应下面的16进制，比对前三个*/
    if bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
        return LGImageType.jpeg
    }
    /*jpeg2000 \152\120\040\040\015 这些数字为8进制 对应下面的16进制，这个比较特殊，从第5个开始比对*/
    if bytes[4] == 0x6A && bytes[5] == 0x50 && bytes[6] == 0x20 && bytes[7] == 0x20 && bytes[8] == 0x0D {
        return LGImageType.jpeg2000
    }
    
    
    
    return LGImageType.unknow
}

let kLGUITypeHeic = "public.heic" as CFString


/// 通过 LGImageType 找到对应的 kUTTypeImage
///
/// - Parameter type: LGImageType
/// - Returns: kUTTypeImage
public func LGImageTypeToUIType(type: LGImageType) -> CFString? {
    var result: CFString?
    switch type {
    case LGImageType.jpeg:
        result = kUTTypeJPEG
        break
    case LGImageType.jpeg2000:
        result = kUTTypeJPEG2000
        break
    case LGImageType.bmp:
        result = kUTTypeBMP
        break
    case LGImageType.ico:
        result = kUTTypeICO
        break
    case LGImageType.tiff:
        result = kUTTypeTIFF
        break
    case LGImageType.gif:
        result = kUTTypeGIF
        break
    case LGImageType.png:
        result = kUTTypePNG
        break
    case LGImageType.heic:
        result = kLGUITypeHeic
        break
    default:
        result = nil
    }
    return result
}


/// 将kUTTypeImage 转换为 LGImageType
///
/// - Parameter uttype: kUTTypeImage 图片的字符类型
/// - Returns: LGImageType
public func LGImageTypeFromUTType(uttype: CFString) -> LGImageType {
    var result = LGImageType.unknow
    switch uttype {
    case kUTTypeJPEG:
        result = LGImageType.jpeg
        break
    case kUTTypeJPEG2000:
        result = LGImageType.jpeg2000
        break
    case kUTTypeBMP:
        result = LGImageType.bmp
        break
    case kUTTypeTIFF:
        result = LGImageType.tiff
        break
    case kUTTypeICO:
        result = LGImageType.ico
        break
    case kUTTypePNG:
        result = LGImageType.png
        break
    case kUTTypeGIF:
        result = LGImageType.gif
        break
    case kLGUITypeHeic:
        result = LGImageType.heic
        break
    default:
        break
    }
    return result
}


/// 获取图片文件后缀名
///
/// - Parameter type: LGImageType
/// - Returns: 文件后缀
public func LGImageTypeGetExtension(type: LGImageType) -> String? {
    var result: String?
    switch type {
    case LGImageType.bmp:
        result = "bmp"
        break
    case LGImageType.tiff:
        result = "tiff"
        break
    case LGImageType.ico:
        result = "ico"
        break
    case LGImageType.jpeg:
        result = "jpg"
        break
    case LGImageType.jpeg2000:
        result = "jp2"
        break
    case LGImageType.gif:
        result = "gif"
        break
    case LGImageType.png:
        result = "png"
        break
    case LGImageType.heic:
        result = "heic"
        break
    default:
        break
    }
    return result
}


/// 将CGImagePropertyOrientation转换为UIImage.Orientation，两者的rawValue并不一致且无对应关系，所以需要转换，而不能直接赋值
///
/// - Parameter value: CGImagePropertyOrientation.*.rawValue
/// - Returns: UIImage.Orientation
public func LGUIImageOrientationFromCGImagePropertyOrientationValue(value: UInt32) -> UIImage.Orientation {
    if let type = CGImagePropertyOrientation(rawValue: value) {
        var result = UIImage.Orientation.up
        switch type {
        case CGImagePropertyOrientation.up:
            result = UIImage.Orientation.up
            break
        case CGImagePropertyOrientation.down:
            result = UIImage.Orientation.down
            break
        case CGImagePropertyOrientation.downMirrored:
            result = UIImage.Orientation.downMirrored
            break
        case CGImagePropertyOrientation.upMirrored:
            result = UIImage.Orientation.upMirrored
            break
        case CGImagePropertyOrientation.left:
            result = UIImage.Orientation.left
            break
        case CGImagePropertyOrientation.leftMirrored:
            result = UIImage.Orientation.leftMirrored
            break
        case CGImagePropertyOrientation.right:
            result = UIImage.Orientation.right
            break
        case CGImagePropertyOrientation.rightMirrored:
            result = UIImage.Orientation.rightMirrored
            break
        }
        return result
    } else {
        return UIImage.Orientation.up
    }
}


/// 解压缩图片，主要是将原有的格式转换为位图
///
/// - Parameters:
///   - image: 需要解压的CGImage
///   - decodeForDisplay: 是否级压缩为显示格式，主要区别在ColorSpace
/// - Returns: 解压缩后的CGImage
public func LGCGImageCreateDecodedCopy(image: CGImage?, decodeForDisplay: Bool) -> CGImage? {
    guard let image = image else {
        return nil
    }
    let width = image.width
    let height = image.height
    if width == 0 || height == 0 {
        return nil
    }
    
    if decodeForDisplay {
        if width * height > LGImageDecoder.maxDecompressImageSize {
            return image
        }
        
        let alphaInfo = image.alphaInfo
        var hasAlpha = false
        // CGImageAlphaInfo.alphaOnly 为只有alpha，没有颜色数据
        if (alphaInfo == CGImageAlphaInfo.premultipliedLast ||
            alphaInfo == CGImageAlphaInfo.premultipliedFirst ||
            alphaInfo == CGImageAlphaInfo.last ||
            alphaInfo == CGImageAlphaInfo.first) {
            hasAlpha = true
        }
        
        var bitmapInfo = LGCGBitmapByteOrder32Host.rawValue
        
        bitmapInfo |= hasAlpha ? CGImageAlphaInfo.premultipliedFirst.rawValue : CGImageAlphaInfo.noneSkipFirst.rawValue
        
        if let context = CGContext(data: nil,
                                   width: width,
                                   height: height,
                                   bitsPerComponent: 8,
                                   bytesPerRow: 0,
                                   space: LGCGColorSpaceDeviceRGB,
                                   bitmapInfo: bitmapInfo) {
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let newImage = context.makeImage()
            return newImage
        } else {
            return nil
        }
    } else {
        if let colorSpace = image.colorSpace {
            let bitsPerComponent = image.bitsPerComponent
            let bitsPerPixel = image.bitsPerPixel
            let bytesPerRow = image.bytesPerRow
            
            let bitmapInfo = image.bitmapInfo
            if bytesPerRow == 0 || width == 0 || height == 0 {
                return nil
            }
            
            if let dataProvider = image.dataProvider {
                if let data = dataProvider.data {
                    if let newProvider = CGDataProvider(data: data) {
                        let newImage = CGImage(width: width,
                                               height: height,
                                               bitsPerComponent: bitsPerComponent,
                                               bitsPerPixel: bitsPerPixel,
                                               bytesPerRow: bytesPerRow,
                                               space: colorSpace,
                                               bitmapInfo: bitmapInfo,
                                               provider: newProvider,
                                               decode: nil,
                                               shouldInterpolate: false,
                                               intent: CGColorRenderingIntent.defaultIntent)
                        return newImage
                    } else {
                        return nil
                    }
                } else {
                    return nil
                }
            } else {
                return nil
            }
        } else {
            return nil
        }
    }
}
/// 判断大小端，然后正确取用CGBitmapInfo 32
public var LGCGBitmapByteOrder32Host: CGBitmapInfo = _LGCGBitmapByteOrder32Host()

private func _LGCGBitmapByteOrder32Host() -> CGBitmapInfo {
    if CFByteOrderGetCurrent() == CFByteOrderBigEndian.rawValue {
        return CGBitmapInfo.byteOrder32Big
    } else {
        return CGBitmapInfo.byteOrder32Little
    }
}


/// 判断大小端，然后正确取用CGBitmapInfo 16
public var LGCGBitmapByteOrder16Host: CGBitmapInfo = _LGCGBitmapByteOrder16Host()

private func _LGCGBitmapByteOrder16Host() -> CGBitmapInfo {
    if CFByteOrderGetCurrent() == CFByteOrderBigEndian.rawValue {
        return CGBitmapInfo.byteOrder16Big
    } else {
        return CGBitmapInfo.byteOrder16Little
    }
}


/// 本机的RGB Color Space
public var LGCGColorSpaceDeviceRGB: CGColorSpace = CGColorSpaceCreateDeviceRGB()

@inline(__always) func LGImageByteAlign(size: Int, alignment: Int) -> Int {
    return ((size + (alignment - 1)) / alignment) * alignment
}

public func LGCGImageCreateEncodedData(image: CGImage?, imageType: LGImageType, quality: CGFloat) -> CFData? {
    if image == nil {
        return nil
    }
    let safeQuality = (quality < 0) ? 0 : (quality > 1 ? 1 : quality)
    if imageType == LGImageType.webp {
        return LGCGImageCreateEncodedWebPData(image: image,
                                              isLossless: safeQuality == 1,
                                              quality: quality,
                                              compressLevel: 4,
                                              preset: LGImagePreset.default)
    }
    
    guard let uti = LGImageTypeToUIType(type: imageType) else {
        return nil
    }
    
    guard let data = CFDataCreateMutable(kCFAllocatorDefault, 0) else {
        return nil
    }
    
    guard let dest = CGImageDestinationCreateWithData(data, uti, 1, nil) else {
        return nil
    }
    
    let options = [kCGImageDestinationLossyCompressionQuality: safeQuality]
    CGImageDestinationAddImage(dest, image!, options as CFDictionary)
    if !CGImageDestinationFinalize(dest) {
        return nil
    }
    
    if CFDataGetLength(data) == 0 {
        return nil
    }
    return data
}

func LGCGImageDecodeToBitmapBufferWithAnyFormat(srcImage: CGImage?,
                                                dest: vImage_Buffer?,
                                                destFormat: vImage_CGImageFormat?) -> Bool {
    guard let safeImage = srcImage, var safeDest = dest, var safeDestFormat = destFormat else {
        return false
    }
    let width = safeImage.width
    let height = safeImage.height
    if width == 0 || height == 0 {
        return false
    }
    
    var error: vImage_Error = kvImageNoError
    var srcData: CFData? = nil
    var convertor: vImageConverter? = nil
    var srcFormat: vImage_CGImageFormat = vImage_CGImageFormat()
    srcFormat.bitsPerComponent = UInt32(safeImage.bitsPerComponent)
    srcFormat.bitsPerPixel = UInt32( safeImage.bitsPerPixel)
    srcFormat.colorSpace = Unmanaged.passUnretained(safeImage.colorSpace ?? LGCGColorSpaceDeviceRGB)
    srcFormat.bitmapInfo = safeImage.bitmapInfo
    
    
    convertor = vImageConverter_CreateWithCGImageFormat(&srcFormat,
                                                        &safeDestFormat,
                                                        nil,
                                                        vImage_Flags(kvImageNoFlags),
                                                        nil).takeUnretainedValue()
    if convertor == nil {
        return false
    }
    
    let srcProvider = safeImage.dataProvider
    srcData = srcProvider?.data
    let srcLength = srcData != nil ? CFDataGetLength(srcData!) : 0
    var srcBytes = srcData != nil ? CFDataGetBytePtr(srcData!) : nil
    
    if srcLength == 0 || srcBytes == nil {
        return false
    }
    
    var src = vImage_Buffer()
    withUnsafeMutableBytes(of: &srcBytes) { (pointer) in
        src.data = pointer.baseAddress
    }
    src.width = vImagePixelCount(width)
    src.height = vImagePixelCount(height)
    src.rowBytes = safeImage.bytesPerRow
    
    error = vImageBuffer_Init(&src,
                              vImagePixelCount(height),
                              vImagePixelCount(width),
                              32,
                              vImage_Flags(kvImageNoFlags))
    if error != kvImageNoError {
        return false
    }
    
    error = vImageConvert_AnyToAny(convertor!, &src, &safeDest, nil, vImage_Flags(kvImageNoFlags))
    if error != kvImageNoError {
        return false
    }
    
    return true
}

public func LGCGImageDecodeToBitmapBufferWith32BitFormat(scrImage: CGImage?,
                                                         dest: vImage_Buffer?,
                                                         bitmapInfo: CGBitmapInfo) -> Bool {
    guard let safeImage = scrImage, var safeDest = dest else {
        return false
    }
    let width = safeImage.width
    let height = safeImage.height
    if width == 0 || height == 0 {
        return false
    }
    
    var hasAlpha = false
    var alphaFirst = false
    var alphaPremultiplied = false
    var byteOrderNormal = false
    
    let alphaInfo = bitmapInfo.rawValue & CGBitmapInfo.alphaInfoMask.rawValue
    switch alphaInfo {
    case CGImageAlphaInfo.premultipliedLast.rawValue:
        hasAlpha = true
        alphaPremultiplied = true
        break
    case CGImageAlphaInfo.premultipliedFirst.rawValue:
        hasAlpha = true
        alphaPremultiplied = true
        alphaFirst = true
        break
    case CGImageAlphaInfo.last.rawValue:
        hasAlpha = true
        break
    case CGImageAlphaInfo.first.rawValue:
        hasAlpha = true
        alphaFirst = true
        break
    case CGImageAlphaInfo.noneSkipLast.rawValue:
        break
    case CGImageAlphaInfo.noneSkipFirst.rawValue:
        alphaFirst = true
        break
    default:
        return false
    }
    
    let orderInfo = bitmapInfo.rawValue & CGBitmapInfo.byteOrderMask.rawValue
    switch orderInfo {
    case 0:
        byteOrderNormal = true
        break
    case CGBitmapInfo.byteOrder32Little.rawValue:
        break
    case CGBitmapInfo.byteOrder32Big.rawValue:
        byteOrderNormal = true
        break
    default:
        return false
    }
    
    var destFormat = vImage_CGImageFormat()
    destFormat.bitsPerComponent = 8
    destFormat.bitsPerPixel = 32
    destFormat.colorSpace = Unmanaged.passUnretained(LGCGColorSpaceDeviceRGB)
    destFormat.bitmapInfo = bitmapInfo
    
    if LGCGImageDecodeToBitmapBufferWithAnyFormat(srcImage: safeImage,
                                                  dest: safeDest,
                                                  destFormat: destFormat) {
        return true
        
    }
    
    var contextBitmapInfo = bitmapInfo.rawValue & CGBitmapInfo.byteOrderMask.rawValue
    if !hasAlpha || alphaPremultiplied {
        contextBitmapInfo |= bitmapInfo.rawValue & CGBitmapInfo.alphaInfoMask.rawValue
    } else {
        if alphaFirst {
            contextBitmapInfo |= CGImageAlphaInfo.premultipliedFirst.rawValue
        } else {
            contextBitmapInfo |= CGImageAlphaInfo.premultipliedLast.rawValue
        }
    }
    
    let context = CGContext(data: nil,
                            width: width,
                            height: height,
                            bitsPerComponent: 8,
                            bytesPerRow: 0,
                            space: LGCGColorSpaceDeviceRGB,
                            bitmapInfo: contextBitmapInfo)
    if context == nil {
        return false
    }
    
    context?.draw(safeImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    let bytesPerRow = context!.bytesPerRow
    let length = height * bytesPerRow
    let data = context!.data
    
    if length == 0 || data == nil {
        return false
    }
    
    guard let tempDataPointer = UnsafeMutableRawPointer(bitPattern: length) else {
        return false
    }
    safeDest.data = tempDataPointer
    safeDest.width = vImagePixelCount(width)
    safeDest.height = vImagePixelCount(height)
    safeDest.rowBytes = bytesPerRow
    
    if hasAlpha && !alphaPremultiplied {
        var tempSrc = vImage_Buffer()
        tempSrc.data = data!
        tempSrc.width = vImagePixelCount(width)
        tempSrc.height = vImagePixelCount(height)
        tempSrc.rowBytes = bytesPerRow
        var error: vImage_Error = kvImageNoError
        
        if alphaFirst && byteOrderNormal {
            error = vImageUnpremultiplyData_ARGB8888(&tempSrc, &safeDest, vImage_Flags(kvImageNoFlags))
        } else {
            error = vImageUnpremultiplyData_RGBA8888(&tempSrc, &safeDest, vImage_Flags(kvImageNoFlags))
        }
        if error != kvImageNoError {
            return false
        }
    } else {
        memcpy(safeDest.data, data!, length)
    }
    
    return true
}



/// 对应wep的枚举
///
/// - `default`: default preset.
/// - picture: digital picture, like portrait, inner shot
/// - photo: outdoor photograph, with natural lighting
/// - drawing: hand or line drawing, with high-contrast details
/// - icon: small-sized colorful images
/// - text: text-like
/// public var WEBP_PRESET_DEFAULT: WebPPreset { get } // default preset.
/// public var WEBP_PRESET_PICTURE: WebPPreset { get } // digital picture, like portrait, inner shot
/// public var WEBP_PRESET_PHOTO: WebPPreset { get } // outdoor photograph, with natural lighting
/// public var WEBP_PRESET_DRAWING: WebPPreset { get } // hand or line drawing, with high-contrast details
/// public var WEBP_PRESET_ICON: WebPPreset { get } // small-sized colorful images
/// public var WEBP_PRESET_TEXT: WebPPreset { get } // text-like
public enum LGImagePreset: Int {
    case `default` = 0
    case picture
    case photo
    case drawing
    case icon
    case text
}

public func LGCGImageCreateEncodedWebPData(image: CGImage?,
                                           isLossless: Bool,
                                           quality: CGFloat,
                                           compressLevel: Int,
                                           preset: LGImagePreset) -> CFData? {
    guard let safeImage = image else {
        return nil
    }
    
    let width = safeImage.width
    let height = safeImage.height
    if width == 0 || width > WEBP_MAX_DIMENSION {
        return nil
    }
    if height == 0 || height > WEBP_MAX_DIMENSION {
        return nil
    }
    let buffer = vImage_Buffer()
    let bitmpinfoValue = CGImageAlphaInfo.last.rawValue | 0
    let bitmapInfo = CGBitmapInfo(rawValue: bitmpinfoValue)
    if !LGCGImageDecodeToBitmapBufferWith32BitFormat(scrImage: safeImage, dest: buffer, bitmapInfo: bitmapInfo) {
        return nil
    }
    
    var config = WebPConfig()
    var picture = WebPPicture()
    var writter = WebPMemoryWriter()
    var webpData: CFData? = nil
    
    let safeQuality = (quality < 0) ? 0 : ((quality > 1) ? 1 : quality)
    let safePreset = preset.rawValue > LGImagePreset.text.rawValue ? LGImagePreset.default : preset
    let safeLevel = (compressLevel < 0) ? 0 : ((compressLevel > 6) ? 6 : compressLevel)
    
    if WebPConfigPreset(&config, WebPPreset(UInt32(safePreset.rawValue)), Float(safeQuality)) == 0 {
        return nil
    }
    
    config.quality = roundf(Float(safeQuality) * 100.0)
    config.lossless = isLossless ? 1 : 0
    config.method = Int32(safeLevel)
    
    switch WebPPreset(UInt32(safePreset.rawValue)) {
    case WEBP_PRESET_DEFAULT:
        config.image_hint = WEBP_HINT_DEFAULT
        break
    case WEBP_PRESET_PICTURE:
        config.image_hint = WEBP_HINT_PICTURE
        break
    case WEBP_PRESET_PHOTO:
        config.image_hint = WEBP_HINT_PHOTO
        break
    case WEBP_PRESET_DRAWING, WEBP_PRESET_ICON, WEBP_PRESET_TEXT:
        config.image_hint = WEBP_HINT_GRAPH
        break
    default:
        break
    }
    
    if WebPValidateConfig(&config) == 0 {
        return nil
    }
    
    if WebPPictureInit(&picture) == 0 {
        return nil
    }
    
    picture.width = Int32(buffer.width)
    picture.height = Int32(buffer.height)
    picture.use_argb = isLossless ? 1 : 0
    if WebPPictureImportRGBA(&picture, buffer.data.load(as: UnsafePointer<UInt8>.self), Int32(buffer.rowBytes)) == 0 {
        WebPPictureFree(&picture)
        return nil
    }
    
    WebPMemoryWriterInit(&writter)
    picture.writer = WebPMemoryWrite
    withUnsafeMutableBytes(of: &writter) { (pointer) in
        picture.custom_ptr = pointer.baseAddress
    }
    
    if WebPEncode(&config, &picture) == 0 {
        WebPPictureFree(&picture)
        return nil
    }
    
    webpData = CFDataCreate(kCFAllocatorDefault, writter.mem, writter.size)
    WebPPictureFree(&picture)
    return webpData
}

public func LGCGImageCreateCopyWith(image: CGImage?,
                                    orientation: UIImage.Orientation,
                                    destBitmapInfo: CGBitmapInfo) -> CGImage? {
    func LGDegreesToRadians(degrees : CGFloat) -> CGFloat {
        return degrees * CGFloat.pi / 180.0
    }
    
    if image == nil {
        return nil
    }
    
    if orientation == UIImage.Orientation.up {
        return image
    }
    
    let width = CGFloat(image!.width)
    let height = CGFloat(image!.height)
    
    var transform = CGAffineTransform.identity
    var swapWidthAndHeight = false
    switch orientation {
    case UIImage.Orientation.left:
        transform = transform.rotated(by: LGDegreesToRadians(degrees: 90.0))
        transform = transform.translatedBy(x: -width, y: -height)
        swapWidthAndHeight = true
        break
    case UIImage.Orientation.right:
        transform = transform.rotated(by: LGDegreesToRadians(degrees: -90.0))
        transform = transform.translatedBy(x: -width, y: 0)
        swapWidthAndHeight = true
        break
    case UIImage.Orientation.down:
        transform = transform.rotated(by: LGDegreesToRadians(degrees: 180.0))
        transform = transform.translatedBy(x: 0, y: -height)
        break
    case UIImage.Orientation.upMirrored:
        transform = transform.translatedBy(x: width, y: 0)
        transform = transform.scaledBy(x: -1, y: 1)
        break
    case UIImage.Orientation.downMirrored:
        transform = transform.translatedBy(x: 0, y: height)
        transform = transform.scaledBy(x: 1, y: -1)
        break
    case UIImage.Orientation.leftMirrored:
        transform = transform.rotated(by: LGDegreesToRadians(degrees: -90.0))
        transform = transform.scaledBy(x: 1, y: -1)
        transform = transform.translatedBy(x: -width, y: -height)
        swapWidthAndHeight = true
        break
    case UIImage.Orientation.rightMirrored:
        transform = transform.rotated(by: LGDegreesToRadians(degrees: 90.0))
        transform = transform.scaledBy(x: 1, y: -1)
        swapWidthAndHeight = true
        break
    default:
        break
    }
    
    if transform.isIdentity {
        return image
    }
    
    var destSize = CGSize(width: width, height: height)
    
    if (swapWidthAndHeight) {
        destSize.width = height
        destSize.height = width
    }
    
    return LGCGImageCreate(withImage: image!,
                           transform: transform,
                           destSize: destSize,
                           destBitmapInfo: destBitmapInfo)
}

public func LGCGImageCreate(withImage image: CGImage,
                            transform: CGAffineTransform,
                            destSize: CGSize,
                            destBitmapInfo: CGBitmapInfo) -> CGImage?
{
    let srcWidth: Int = image.width
    let srcHeight: Int = image.height
    let destWidth: Int = Int(destSize.width)
    let destHeight: Int = Int(destSize.height)
    if (srcWidth == 0 || srcHeight == 0 || destWidth == 0 || destHeight == 0) {
        return nil
    }
    var tmpProvider: CGDataProvider? = nil, destProvider: CGDataProvider? = nil
    var tempImage: CGImage? = nil, destImage: CGImage? = nil
    var srcBuffer: vImage_Buffer = vImage_Buffer()
    var tempBuffer: vImage_Buffer = vImage_Buffer()
    let destBuffer: vImage_Buffer = vImage_Buffer()
    
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.first.rawValue | 0)
    if !LGCGImageDecodeToBitmapBufferWith32BitFormat(scrImage: image,
                                                     dest: srcBuffer,
                                                     bitmapInfo: bitmapInfo) {
        return nil
    }
    
    let destBytesPerRow = LGImageByteAlign(size: destWidth * 4, alignment: 32)
    guard let tempPointer = UnsafeMutableRawPointer(bitPattern: destHeight * destBytesPerRow) else {
        return nil
    }
    tempBuffer.data = tempPointer
    tempBuffer.width = vImagePixelCount(destWidth)
    tempBuffer.height = vImagePixelCount(destHeight)
    tempBuffer.rowBytes = destBytesPerRow
    
    
    var vTransform = transform.vImageAffinetransform
    var backColor: [UInt8] = [UInt8](repeating: 0, count: 4)
    
    let error: vImage_Error = vImageAffineWarpCG_ARGB8888(&srcBuffer,
                                                          &tempBuffer,
                                                          nil,
                                                          &vTransform,
                                                          &backColor,
                                                          vImage_Flags(kvImageBackgroundColorFill))
    if error != kvImageNoError {
        return nil
    }
    
    tmpProvider = CGDataProvider(dataInfo: tempBuffer.data,
                                 data: tempBuffer.data, size: destHeight * destBytesPerRow,
                                 releaseData: { (rawPointer, pointer, size) in
                                    // arc, do nothing
                                    return
    })
    
    if tmpProvider == nil {
        return nil
    }
    tempImage = CGImage(width: destWidth,
                        height: destHeight,
                        bitsPerComponent: 8,
                        bitsPerPixel: 32,
                        bytesPerRow: destBytesPerRow,
                        space: LGCGColorSpaceDeviceRGB,
                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.first.rawValue | 0),
                        provider: tmpProvider!,
                        decode: nil,
                        shouldInterpolate: false,
                        intent: CGColorRenderingIntent.defaultIntent)
    if tempImage == nil {
        return nil
    }
    
    tmpProvider = nil
    
    if destBitmapInfo.rawValue & CGBitmapInfo.alphaInfoMask.rawValue == CGImageAlphaInfo.first.rawValue &&
        destBitmapInfo.rawValue & CGBitmapInfo.byteOrderMask.rawValue != CGBitmapInfo.byteOrder32Little.rawValue {
        return tempImage
    }
    
    if !LGCGImageDecodeToBitmapBufferWith32BitFormat(scrImage: tempImage,
                                                     dest: destBuffer,
                                                     bitmapInfo: destBitmapInfo)
    {
        return nil
    }
    
    tempImage = nil
    destProvider = CGDataProvider(dataInfo: destBuffer.data,
                                  data: destBuffer.data,
                                  size: destHeight * destBytesPerRow,
                                  releaseData: { (rawPointer, pointer, size) in
                                    // arc, do nothing
                                    return
    })
    
    if destProvider == nil {
        return nil
    }
    
    destImage = CGImage(width: destWidth,
                        height: destHeight,
                        bitsPerComponent: 8,
                        bitsPerPixel: 32,
                        bytesPerRow: destBytesPerRow,
                        space: LGCGColorSpaceDeviceRGB,
                        bitmapInfo: destBitmapInfo,
                        provider: destProvider!,
                        decode: nil,
                        shouldInterpolate: false,
                        intent: CGColorRenderingIntent.defaultIntent)
    
    if destImage == nil {
        return nil
    }
    
    return destImage
    
}

extension CGAffineTransform {
    
    fileprivate var vImageAffinetransform: vImage_CGAffineTransform {
        #if arch(arm) || arch(i386)
        return vImage_CGAffineTransform(a: self.a.floatValue,
                                        b: self.b.floatValue,
                                        c: self.c.floatValue,
                                        d: self.d.floatValue,
                                        tx: self.tx.floatValue,
                                        ty: self.ty.floatValue)
        #else
        return vImage_CGAffineTransform(a: self.a.doubleValue,
                                        b: self.b.doubleValue,
                                        c: self.c.doubleValue,
                                        d: self.d.doubleValue,
                                        tx: self.tx.doubleValue,
                                        ty: self.ty.doubleValue)
        #endif
    }
}

extension CGFloat {
    fileprivate var doubleValue: Double {
        return Double(self)
    }
    
    fileprivate var floatValue: Float {
        return Float(self)
    }
}

// MARK: - 增加一些个属性
public extension UIImage {
    var lg_imageByDecoded: UIImage {
        if self.lg_isDecodedForDisplay {
            return self
        }
        guard let cgImage = self.cgImage else {
            return self
        }
        
        guard let newCGImage = LGCGImageCreateDecodedCopy(image: cgImage, decodeForDisplay: true) else {
            return self
        }
        let newImage = UIImage(cgImage: newCGImage, scale: self.scale, orientation: self.imageOrientation)
        newImage.lg_isDecodedForDisplay = true
        return newImage
    }
    
    private struct AssociatedKeys {
        static var isDecodedForDisplay: String = "lg_isDecodedForDisplay"
    }
    
    var lg_isDecodedForDisplay: Bool {
        set {
            objc_setAssociatedObject(self,
                                     &AssociatedKeys.isDecodedForDisplay,
                                     NSNumber(booleanLiteral: newValue),
                                     objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        get {
            if (self.images != nil && self.images!.count > 1) || self.isKind(of: LGSpriteSheetImage.classForCoder()) {
                return true
            }
            guard let number = objc_getAssociatedObject(self, &AssociatedKeys.isDecodedForDisplay) as? NSNumber else {
                return false
            }
            
            return number.boolValue
        }
    }
    
    var lg_imageDataRepresentation: Data? {
        return lg_dataRepresentation(forSystem: false)
    }
    
    fileprivate func lg_dataRepresentation(forSystem: Bool) -> Data? {
        var result: Data? = nil
        if self.isKind(of: LGImage.classForCoder()) {
            let image: LGImage = self as! LGImage
            if image.animatedImageData != nil {
                if forSystem {
                    if image.animatedImageType == LGImageType.gif || image.animatedImageType == LGImageType.png {
                        result = image.animatedImageData
                    }
                } else {
                    result = image.animatedImageData
                }
            }
        }
        
        if result == nil {
            if var cgImage = self.cgImage {
                let bitmapInfo = cgImage.bitmapInfo
                let alphaInfo = cgImage.alphaInfo.rawValue & CGBitmapInfo.alphaInfoMask.rawValue
                var hasAlpha = false
                if alphaInfo == CGImageAlphaInfo.premultipliedLast.rawValue ||
                    alphaInfo == CGImageAlphaInfo.premultipliedFirst.rawValue ||
                    alphaInfo == CGImageAlphaInfo.last.rawValue ||
                    alphaInfo == CGImageAlphaInfo.first.rawValue {
                    hasAlpha = true
                }
                
                if self.imageOrientation != UIImage.Orientation.up {
                    let tempBitmapInfo = CGBitmapInfo(rawValue: bitmapInfo.rawValue | alphaInfo)
                    if let rotated = LGCGImageCreateCopyWith(image: cgImage,
                                                             orientation: self.imageOrientation,
                                                             destBitmapInfo: tempBitmapInfo) {
                        cgImage = rotated
                    }
                }
                let newImage = UIImage(cgImage: cgImage)
                if hasAlpha {
                    result = newImage.pngData()
                } else {
                    result = newImage.jpegData(compressionQuality: 1.0)
                }
                
            }
        }
        
        if result == nil {
            result = self.pngData()
        }
        return result
    }
    
    func lg_savetoAlbumWith(completionBlock: @escaping (Bool, PHAsset?, Error?) -> Void) {
        var localId: String?
        PHPhotoLibrary.shared().performChanges({
            let result = PHAssetChangeRequest.creationRequestForAsset(from: self)
            localId = result.placeholderForCreatedAsset?.localIdentifier
        }) { (isSucceed, error) in
            if isSucceed {
                if localId != nil {
                    let result = PHAsset.fetchAssets(withLocalIdentifiers: [localId ?? ""], options: nil)
                    if result.count > 0 {
                        let asset = result[0]
                        if Thread.current.isMainThread {
                            completionBlock(true, asset, nil)
                        } else {
                            DispatchQueue.main.async {
                                completionBlock(true, asset, nil)
                            }
                        }
                        return
                    }
                }
            }
            if Thread.current.isMainThread {
                completionBlock(false, nil, error)
            } else {
                DispatchQueue.main.async {
                    completionBlock(false, nil, error)
                }
            }
        }
    }
    
}
