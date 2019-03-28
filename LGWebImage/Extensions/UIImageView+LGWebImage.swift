//
//  UIImageView+LGWebImage.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2018/4/16.
//  Copyright © 2018年 龚杰洪. All rights reserved.
//

import Foundation
import LGHTTPRequest

let kLGWebImageFadeAnimationKey = "LGWebImageFadeAnimation"

public extension UIImageView {
    private struct AssociatedKeys {
        static var imageSetterKey = "LGWebImageOperationImageSetterKey"
        static var highlightedImageSetterKey = "LGWebImageOperationHighlightedImageSetterKey"
    }
    
    // MARK: -  普通状态
    /// 普通状态图片URL
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
                                   completionBlock: LGWebImageCompletionBlock? = nil)
    {
        let sentinel: LGWebImageOperationSetter.Sentinel = self.lg_imageSetter.cancel(withNewURL: imageURL)
        
        do {
            let newURL = try imageURL.asURL()
            if  let image = LGImageCache.default.getImage(forKey: newURL.absoluteString,
                                                          withType: LGImageCacheType.memory)
            {
                self.image = image
                completionBlock?(image,
                                 newURL,
                                 LGWebImageSourceType.memoryCache,
                                 LGWebImageStage.finished,
                                 nil)
                return
            }
        } catch {
            println(error)
            if !options.contains(LGWebImageOptions.ignorePlaceHolder) && placeholder != nil {
                self.image = placeholder
            } else {
                self.image = nil
            }
            return
        }
        
        if !options.contains(LGWebImageOptions.ignorePlaceHolder) && placeholder != nil {
            self.image = placeholder
        } else {
            self.image = nil
        }
        
        let task = DispatchWorkItem { [weak self] in
            guard let strongSelf = self else {
                return
            }
            
            var newSentinel: LGWebImageOperationSetter.Sentinel = sentinel
            
            newSentinel = strongSelf.lg_imageSetter.setOperation(with: sentinel,
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
                    if  needFadeAnimation && !avoidSetImage {
                        if strongSelf.isHighlighted {
                            strongSelf.layer.removeAnimation(forKey: kLGWebImageFadeAnimationKey)
                        }
                    }
                    
                    let imageIsValid = (imageStage == .finished || imageStage == .progress)
                    let canSetImage = (!avoidSetImage && imageIsValid)
                    
                    let result = resultImage
                    
                    if canSetImage {
                        if needFadeAnimation && !strongSelf.isHighlighted {
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
                            strongSelf.layer.add(transition, forKey: kLGWebImageFadeAnimationKey)
                        }
                        strongSelf.image = result
                    }
                }
                completionBlock?(resultImage, url, sourceType, imageStage, error)
            })
        }
        
        lg_imageSetter.runTask(task)
    }
    
    /// 取消普通图片请求
    public func lg_cancelCurrentNormalImageRequest() {
        lg_imageSetter.cancel()
    }
    
    // MARK: -  高亮状态
    
    /// 高亮状态图片URL
    public var lg_highlightedImageURL: LGURLConvertible? {
        return lg_highlightedImageSetter.imageURL
    }
    
    private var lg_highlightedImageSetter: LGWebImageOperationSetter {
        set {
            objc_setAssociatedObject(self,
                                     &AssociatedKeys.highlightedImageSetterKey,
                                     newValue,
                                     objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        } get {
            if let temp = objc_getAssociatedObject(self, &AssociatedKeys.highlightedImageSetterKey),
                let setter = temp as? LGWebImageOperationSetter
            {
                return setter
            } else {
                let setter = LGWebImageOperationSetter()
                self.lg_highlightedImageSetter = setter
                return setter
            }
        }
    }
    
    /// 通过URL和占位图，参数设置等设置高亮状态图片
    ///
    /// - Parameters:
    ///   - imageURL: 高亮状态图片地址
    ///   - placeholder: 占位图
    ///   - options: 属性配置，默认LGWebImageOptions.default
    ///   - progress: 进度回调
    ///   - completion: 请求完成回调
    public func lg_setHighlightedImageWithURL(_ imageURL: LGURLConvertible,
                                              placeholder: UIImage? = nil,
                                              options: LGWebImageOptions = LGWebImageOptions.default,
                                              progressBlock: LGWebImageProgressBlock? = nil,
                                              transformBlock: LGWebImageTransformBlock? = nil,
                                              completionBlock: LGWebImageCompletionBlock? = nil)
    {
        let sentinel = self.lg_highlightedImageSetter.cancel(withNewURL: imageURL)
        
        do {
            let newURL = try imageURL.asURL()
            if let image = LGImageCache.default.getImage(forKey: newURL.absoluteString,
                                                         withType: LGImageCacheType.memory)
            {
                
                self.highlightedImage = image
                completionBlock?(image,
                                 newURL,
                                 LGWebImageSourceType.memoryCache,
                                 LGWebImageStage.finished,
                                 nil)
                return
            }
        } catch {
            println(error)
            if !options.contains(LGWebImageOptions.ignorePlaceHolder) &&
                placeholder != nil
            {
                self.highlightedImage = placeholder
            } else {
                self.highlightedImage = nil
            }
            return
        }
        
        if !options.contains(LGWebImageOptions.ignorePlaceHolder) &&
            placeholder != nil
        {
            self.highlightedImage = placeholder
        } else {
            self.highlightedImage = nil
        }
        
        let task = DispatchWorkItem { [weak self] in
            guard let strongSelf = self else {
                return
            }
            
            var newSentinel: LGWebImageOperationSetter.Sentinel = 0
            newSentinel = strongSelf.lg_highlightedImageSetter.setOperation(with: sentinel,
                                                                      URL: imageURL,
                                                                      options: options,
                                                                      manager: LGWebImageManager.default,
                                                                      progress:
                { (progress) in
                    progressBlock?(progress)
            }, completion: { [weak self] (resultImage, url, sourceType, imageStage, error) in
                guard let strongSelf = self, strongSelf.lg_highlightedImageSetter.sentinel == newSentinel else {
                    completionBlock?(resultImage, url, sourceType, imageStage, error)
                    return
                }
                if resultImage != nil && error == nil {
                    let needFadeAnimation = options.contains(LGWebImageOptions.setImageWithFadeAnimation)
                    let avoidSetImage = options.contains(LGWebImageOptions.avoidSetImage)
                    if  needFadeAnimation && !avoidSetImage
                    {
                        if strongSelf.isHighlighted {
                            strongSelf.layer.removeAnimation(forKey: kLGWebImageFadeAnimationKey)
                        }
                    }
                    
                    let imageIsValid = (imageStage == .finished || imageStage == .progress)
                    let canSetImage = (!avoidSetImage && imageIsValid)
                    
                    let result = resultImage
                    
                    if canSetImage {
                        
                        if needFadeAnimation && !strongSelf.isHighlighted {
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
                            strongSelf.layer.add(transition, forKey: kLGWebImageFadeAnimationKey)
                        }
                        strongSelf.highlightedImage = result
                    }
                }
                completionBlock?(resultImage, url, sourceType, imageStage, error)
            })
        }
        
        lg_highlightedImageSetter.runTask(task)
    }
    
    /// 取消普通图片请求
    public func lg_cancelCurrentHilightedImageRequest() {
        lg_highlightedImageSetter.cancel()
    }
}

extension UIImageView {
    static func swizzleImplementations() {
        UIImageView.swizzleSetImageImplementation()
        UIImageView.swizzleSetHighlightedImageImplementation()
    }
    
    private static func swizzleSetImageImplementation() {
        let aClass: AnyClass = self.classForCoder()
        let originalMethod = class_getInstanceMethod(aClass, #selector(setter: UIImageView.image))
        let swizzledMethod = class_getInstanceMethod(aClass, #selector(UIImageView.lg_setImage(_:)))
        if let originalMethod = originalMethod, let swizzledMethod = swizzledMethod {
            // switch implementation..
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }
    
    private static func swizzleSetHighlightedImageImplementation() {
        let aClass: AnyClass = self.classForCoder()
        let originalMethod = class_getInstanceMethod(aClass, #selector(setter: UIImageView.highlightedImage))
        let swizzledMethod = class_getInstanceMethod(aClass, #selector(UIImageView.lg_setHighlightedImage(_:)))
        if let originalMethod = originalMethod, let swizzledMethod = swizzledMethod {
            // switch implementation..
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }
    
    @objc func lg_setImage(_ image: UIImage?) {
        if self.lg_needSetCornerRadius == true {
            lg_setImageQueue.async(flags: DispatchWorkItemFlags.barrier)
            { [weak self] in
                guard let weakSelf = self else {return}
                var result: UIImage? = nil
                if let tempImage = image?.lg_imageByDecoded {
                    if let cornerRadiusImage = weakSelf.cornerRadius(tempImage)
                    {
                        result = cornerRadiusImage
                    } else {
                        result = tempImage
                    }
                    DispatchQueue.main.async { [weak self] in
                        guard let weakSelf = self else {return}
                        weakSelf.lg_setImage(result)
                    }
                }
            }
        } else {
            self.lg_setImage(image)
        }
    }
    
    @objc func lg_setHighlightedImage(_ image: UIImage?) {
        if self.lg_needSetCornerRadius == true {
            lg_setImageQueue.async(flags: DispatchWorkItemFlags.barrier) { [weak self] in
                guard let weakSelf = self else {return}
                var result: UIImage? = nil
                if let tempImage = image?.lg_imageByDecoded {
                    if let cornerRadiusImage = weakSelf.cornerRadius(tempImage)
                    {
                        result = cornerRadiusImage
                    } else {
                        result = tempImage
                    }
                    DispatchQueue.main.async { [weak self] in
                        guard let weakSelf = self else {return}
                        weakSelf.lg_setHighlightedImage(result)
                    }
                }
            }
        } else {
            self.lg_setHighlightedImage(image)
        }
    }
}
