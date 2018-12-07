//
//  CALayer+LGWebImage.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2018/4/23.
//  Copyright © 2018年 龚杰洪. All rights reserved.
//

import Foundation
import LGHTTPRequest

public extension CALayer {
    private struct AssociatedKeys {
        static var cornerRadiusKey = "lg_cornerRadius"
        static var imageSetterKey = "LGWebImageOperationImageSetterKey"
    }
    
    /// 图片URL
    public var lg_imageURL: LGURLConvertible? {
        return lg_imageSetter.imageURL
    }
    
    private var lg_imageSetter: LGWebImageOperationSetter {
        set {
            objc_setAssociatedObject(self,
                                     &AssociatedKeys.imageSetterKey,
                                     newValue,
                                     objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        } get {
            if let temp = objc_getAssociatedObject(self, &AssociatedKeys.imageSetterKey),
                let setter = temp as? LGWebImageOperationSetter
            {
                return setter
            } else {
                let setter = LGWebImageOperationSetter()
                self.lg_imageSetter = setter
                return setter
            }
        }
    }
    
    /// 通过URL和占位图，参数设置等设置普通状态图片
    ///
    /// - Parameters:
    ///   - imageURL: 普通状态图片地址
    ///   - placeholder: 占位图
    ///   - options: 属性配置，默认LGWebImageOptions.default
    ///   - progress: 进度回调
    ///   - completion: 请求完成回调
    public func lg_setImageWithURL(_ imageURL: LGURLConvertible,
                                   placeholder: UIImage? = nil,
                                   options: LGWebImageOptions = LGWebImageOptions.default,
                                   progressBlock: LGWebImageProgressBlock? = nil,
                                   transformBlock: LGWebImageTransformBlock? = nil,
                                   completionBlock: LGWebImageCompletionBlock? = nil)
    {
        let sentinel = lg_imageSetter.cancel(withNewURL: imageURL)
        self.contents = nil
        
        
        do {
            let newURL = try imageURL.asURL()
            if let image = LGImageCache.default.getImage(forKey: newURL.absoluteString,
                                                         withType: LGImageCacheType.memory)
            {
                self.contents = image.cgImage
                completionBlock?(image,
                                 newURL,
                                 LGWebImageSourceType.memoryCache,
                                 LGWebImageStage.finished,
                                 nil)
                return
            }
        } catch {
            println(error)
            return
        }
        
        if self.contents == nil && !options.contains(LGWebImageOptions.ignorePlaceHolder) && placeholder != nil {
            self.contents = placeholder?.cgImage
        }
        
        var newSentinel: LGWebImageOperationSetter.Sentinel = 0
        newSentinel = lg_imageSetter.setOperation(with: sentinel,
                                                  URL: imageURL,
                                                  options: options,
                                                  manager: LGWebImageManager.default,
                                                  progress:
            { (progress) in
                progressBlock?(progress)
        }, completion: { [weak self] (resultImage, url, sourceType, imageStage, error) in
            guard let strongSelf = self, strongSelf.lg_imageSetter.sentinel == newSentinel else {
                completionBlock?(resultImage, url, sourceType, imageStage, error)
                return
            }
            
            if resultImage != nil && error == nil {
                let needFadeAnimation = options.contains(LGWebImageOptions.setImageWithFadeAnimation)
                let avoidSetImage = options.contains(LGWebImageOptions.avoidSetImage)
                if  needFadeAnimation && !avoidSetImage
                {
                    strongSelf.removeAnimation(forKey: kLGWebImageFadeAnimationKey)
                }
                
                let imageIsValid = (imageStage == .finished || imageStage == .progress)
                let canSetImage = (!avoidSetImage && imageIsValid)
                
                let result = resultImage
                
                if canSetImage {
                    
                    if needFadeAnimation {
                        let transition = CATransition()
                        var duration: CFTimeInterval
                        if imageStage == LGWebImageStage.finished {
                            duration = CFTimeInterval.lg_imageFadeAnimationTime
                        } else {
                            duration = CFTimeInterval.lg_imageProgressiveFadeAnimationTime
                        }
                        transition.duration = duration
                        let functionName = CAMediaTimingFunctionName.easeInEaseOut
                        transition.timingFunction = CAMediaTimingFunction(name: functionName)
                        transition.type = CATransitionType.fade
                        strongSelf.add(transition, forKey: kLGWebImageFadeAnimationKey)
                    }
                    strongSelf.contents = result?.cgImage
                }
            }
            
            completionBlock?(resultImage, url, sourceType, imageStage, error)
        })
    }
    
    /// 取消普通图片请求
    public func lg_cancelCurrentImageRequest() {
        lg_imageSetter.cancel()
    }
}

extension CALayer {
    static func swizzleImplementations() {
        CALayer.swizzleSetContentsImplementation()
    }
    
    private static func swizzleSetContentsImplementation() {
        let aClass: AnyClass = self.classForCoder()
        let originalMethod = class_getInstanceMethod(aClass, #selector(setter: CALayer.contents))
        let swizzledMethod = class_getInstanceMethod(aClass, #selector(CALayer.lg_setContents(_:)))
        if let originalMethod = originalMethod, let swizzledMethod = swizzledMethod {
            // switch implementation..
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }
    
    @objc func lg_setContents(_ contentsToSet: Any?) {
        if self.lg_needSetCornerRadius == true {
            lg_setImageQueue.async(flags: DispatchWorkItemFlags.barrier)
            { [weak self] in
                guard let weakSelf = self else {return}
                var result: UIImage? = nil
                if contentsToSet == nil {
                    return
                }
                let tempCGImage: CGImage = contentsToSet as! CGImage
                let tempImage = UIImage(cgImage: tempCGImage).lg_imageByDecoded
                if let cornerRadiusImage = weakSelf.cornerRadius(tempImage)
                {
                    result = cornerRadiusImage
                } else {
                    result = tempImage
                }
                DispatchQueue.main.async { [weak self] in
                    guard let weakSelf = self else {return}
                    weakSelf.lg_setContents(result?.cgImage)
                }
            }
        } else {
            self.lg_setContents(contentsToSet)
        }
    }
}

public extension CALayer {
    
    public var lg_needSetCornerRadius: Bool {
        return self.lg_cornerRadius?.needSetCornerRadius == true
    }
    
    /// 在不设置layer圆角的情况下设置图片圆角
    public var lg_cornerRadius: LGCornerRadiusConfig? {
        set {
            objc_setAssociatedObject(self,
                                     &AssociatedKeys.cornerRadiusKey,
                                     newValue,
                                     objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        } get {
            return objc_getAssociatedObject(self, &AssociatedKeys.cornerRadiusKey) as? LGCornerRadiusConfig
        }
    }
    
    internal func cornerRadius(_ image: UIImage?) -> UIImage? {
        if image == nil {
            return nil
        }
        if let corner = self.lg_cornerRadius, corner.needSetCornerRadius == true {
            let size = self.bounds.size
            let contentMode = self.contentsGravity.asUIViewContentMode()
            var result = image?.lg_imageByResizeToSize(size, contentMode: contentMode)
            result = result?.lg_imageByRoundCornerRadius(corner.cornerRadius,
                                                         corners: corner.corners,
                                                         borderWidth: corner.borderWidth,
                                                         borderColor: corner.borderColor,
                                                         borderLineJoin: corner.borderLineJoin)
            return result
        }
        return nil
    }
}

extension CALayerContentsGravity {
    public func asUIViewContentMode() -> UIView.ContentMode {
        switch self {
        case CALayerContentsGravity.top:
            return .top
        case CALayerContentsGravity.bottom:
            return .bottom
        case CALayerContentsGravity.left:
            return .left
        case CALayerContentsGravity.right:
            return .right
        case CALayerContentsGravity.topLeft:
            return .topLeft
        case CALayerContentsGravity.bottomLeft:
            return .bottomLeft
        case CALayerContentsGravity.topRight:
            return .topRight
        case CALayerContentsGravity.bottomRight:
            return .bottomRight
        case CALayerContentsGravity.center:
            return .center
        case CALayerContentsGravity.resize:
            return .scaleToFill
        case CALayerContentsGravity.resizeAspect:
            return .scaleAspectFit
        case CALayerContentsGravity.resizeAspectFill:
            return .scaleAspectFill
        default:
            return .scaleAspectFill
        }
    }
}
