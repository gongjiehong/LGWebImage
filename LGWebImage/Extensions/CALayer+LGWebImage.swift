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
        static var URLKey = "LGWebImageURLKey"
        static var TokenKey = "LGWebImageTokenKey"
        static var cornerRadiusKey = "lg_cornerRadius"
    }
    
    /// 图片URL
    public private(set) var lg_imageURL: LGURLConvertible? {
        set {
            do {
                if let url = try newValue?.asURL() {
                    objc_setAssociatedObject(self,
                                             &AssociatedKeys.URLKey,
                                             url,
                                             objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                }
            } catch {
                
            }
        } get {
            return objc_getAssociatedObject(self, &AssociatedKeys.URLKey) as? URL
        }
    }
    
    /// 下载回调token
    private var lg_callbackToken: LGWebImageCallbackToken? {
        set {
            objc_setAssociatedObject(self,
                                     &AssociatedKeys.TokenKey,
                                     newValue,
                                     objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        } get {
            return objc_getAssociatedObject(self, &AssociatedKeys.TokenKey) as? LGWebImageCallbackToken
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
        self.lg_imageURL = imageURL
        
        if self.lg_callbackToken != nil {
            self.lg_cancelCurrentImageRequest()
            self.contents = nil
        }
        
        if self.contents == nil && !options.contains(LGWebImageOptions.ignorePlaceHolder) && placeholder != nil {
            LGWebImageManager.default.workQueue.async(flags: DispatchWorkItemFlags.barrier) { [weak self] in
                var placeholderImage: UIImage? = nil
                if let image = placeholder?.lg_imageByDecoded {
                    placeholderImage = image
                    DispatchQueue.main.async { [weak self] in
                        self?.contents = placeholderImage?.cgImage
                    }
                }
            }
        }
        
        self.lg_callbackToken = LGWebImageManager.default.downloadImageWith(url: imageURL,
                                                                                  options: options,
                                                                                  progress:
            { (progress) in
                DispatchQueue.main.async {
                    progressBlock?(progress)
                }
        },
                                                                                  transform: transformBlock,
                                                                                  completion:
            {[weak self] (resultImage, url, sourceType, imageStage, error) in
                if resultImage != nil && error == nil {
                    let needFadeAnimation = options.contains(LGWebImageOptions.setImageWithFadeAnimation)
                    let avoidSetImage = options.contains(LGWebImageOptions.avoidSetImage)
                    if  needFadeAnimation && !avoidSetImage
                    {
                        DispatchQueue.main.async { [weak self] in
                            guard let weakSelf = self else {
                                return
                            }
                            weakSelf.removeAnimation(forKey: kLGWebImageFadeAnimationKey)
                        }
                    }
                    
                    let imageIsValid = (imageStage == .finished || imageStage == .progress)
                    let canSetImage = (!avoidSetImage && imageIsValid)
                    
                    let result = resultImage
                    
                    if canSetImage {
                        DispatchQueue.main.async { [weak self] in
                            guard let weakSelf = self else {
                                return
                            }
                            if needFadeAnimation {
                                let transition = CATransition()
                                var duration: CFTimeInterval
                                if imageStage == LGWebImageStage.finished {
                                    duration = CFTimeInterval.lg_imageFadeAnimationTime
                                } else {
                                    duration = CFTimeInterval.lg_imageProgressiveFadeAnimationTime
                                }
                                transition.duration = duration
                                transition.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)
                                transition.type = kCATransitionFade
                                weakSelf.add(transition, forKey: kLGWebImageFadeAnimationKey)
                            }
                            weakSelf.contents = result?.cgImage
                        }
                    }
                }
                
                DispatchQueue.main.async {
                    completionBlock?(resultImage, url, sourceType, imageStage, error)
                }
        })
    }
    
    /// 取消普通图片请求
    public func lg_cancelCurrentImageRequest() {
        if let token = self.lg_callbackToken {
            LGWebImageManager.default.cancelWith(callbackToken: token)
            self.lg_callbackToken = nil
        }
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
            LGWebImageManager.default.workQueue.async(flags: DispatchWorkItemFlags.barrier)
            { [weak self] in
                var result: UIImage? = nil
                if contentsToSet == nil {
                    return
                }
                let tempCGImage: CGImage = contentsToSet as! CGImage
                let tempImage = UIImage(cgImage: tempCGImage).lg_imageByDecoded
                if let cornerRadiusImage = self?.cornerRadius(tempImage)
                {
                    result = cornerRadiusImage
                } else {
                    result = tempImage
                }
                DispatchQueue.main.async { [weak self] in
                    self?.lg_setContents(result?.cgImage)
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
            let contentMode = LGCALayerContentsGravityToUIViewContentMode(self.contentsGravity)
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

fileprivate func LGCALayerContentsGravityToUIViewContentMode(_ contentsGravity: String) -> UIViewContentMode {
    switch contentsGravity {
    case kCAGravityTop:
        return .top
    case kCAGravityBottom:
        return .bottom
    case kCAGravityLeft:
        return .left
    case kCAGravityRight:
        return .right
    case kCAGravityTopLeft:
        return .topLeft
    case kCAGravityBottomLeft:
        return .bottomLeft
    case kCAGravityTopRight:
        return .topRight
    case kCAGravityBottomRight:
        return .bottomRight
    case kCAGravityCenter:
        return .center
    case kCAGravityResize:
        return .scaleToFill
    case kCAGravityResizeAspect:
        return .scaleAspectFit
    case kCAGravityResizeAspectFill:
        return .scaleAspectFill
    default:
        return .scaleAspectFill
    }
}
