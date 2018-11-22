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
        static var normalURLKey = "LGWebImageNormalURLKey"
        static var highlightedURLKey = "LGWebImageHighlightedURLKey"
        static var normalTokenKey = "LGWebImageNormalTokenKey"
        static var highlightedTokenKey = "LGWebImageHighlightedTokenKey"
    }
    
    // MARK: -  普通状态
    /// 普通状态图片URL
    public private(set) var lg_imageURL: LGURLConvertible? {
        set {
            do {
                if let url = try newValue?.asURL() {
                    objc_setAssociatedObject(self,
                                             &AssociatedKeys.normalURLKey,
                                             url,
                                             objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                }
            } catch {
                
            }
        } get {
            return objc_getAssociatedObject(self, &AssociatedKeys.normalURLKey) as? URL
        }
    }
    
    /// 普通状态下的下载回调token
    private var lg_normalCallbackToken: LGWebImageCallbackToken? {
        set {
            objc_setAssociatedObject(self,
                                     &AssociatedKeys.normalTokenKey,
                                     newValue,
                                     objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        } get {
            return objc_getAssociatedObject(self, &AssociatedKeys.normalTokenKey) as? LGWebImageCallbackToken
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
        self.lg_cancelCurrentNormalImageRequest()
        self.image = nil
        
        do {
            let newURL = try imageURL.asURL()
            self.lg_imageURL = imageURL
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
            self.lg_imageURL = nil
            println(error)
        }
        
        if self.image == nil && !options.contains(LGWebImageOptions.ignorePlaceHolder) && placeholder != nil {
            self.image = placeholder
        }
        
        if self.lg_imageURL == nil {
            return
        }
        
        self.lg_normalCallbackToken = LGWebImageManager.default.downloadImageWith(url: imageURL,
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
                            if !weakSelf.isHighlighted {
                                weakSelf.layer.removeAnimation(forKey: kLGWebImageFadeAnimationKey)
                            }
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
                            if needFadeAnimation && !weakSelf.isHighlighted {
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
                                weakSelf.layer.add(transition, forKey: kLGWebImageFadeAnimationKey)
                            }
                            weakSelf.image = result
                        }
                    }
                }
                
                DispatchQueue.main.async {
                    completionBlock?(resultImage, url, sourceType, imageStage, error)
                }
        })
    }
    
    /// 取消普通图片请求
    public func lg_cancelCurrentNormalImageRequest() {
        if let token = self.lg_normalCallbackToken {
            LGWebImageManager.default.cancelWith(callbackToken: token)
            self.lg_normalCallbackToken = nil
        }
    }
    
    // MARK: -  高亮状态
    
    /// 高亮状态图片URL
    public private(set) var lg_highlightedImageURL: LGURLConvertible? {
        set {
            do {
                if let url = try newValue?.asURL() {
                    objc_setAssociatedObject(self,
                                             &AssociatedKeys.highlightedURLKey,
                                             url,
                                             objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                }
            } catch {
            }
        }
        get {
            return objc_getAssociatedObject(self, &AssociatedKeys.highlightedURLKey) as? URL
        }
    }
    
    /// 高亮状态下的下载回调token
    private var lg_highlightedCallbackToken: LGWebImageCallbackToken? {
        set {
            objc_setAssociatedObject(self,
                                     &AssociatedKeys.highlightedTokenKey,
                                     newValue,
                                     objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        } get {
            return objc_getAssociatedObject(self, &AssociatedKeys.highlightedTokenKey) as? LGWebImageCallbackToken
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
        self.lg_cancelCurrentHighlightedImageRequest()
        self.highlightedImage = nil
        
        do {
            let newURL = try imageURL.asURL()
            self.lg_highlightedImageURL = imageURL
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
            self.lg_highlightedImageURL = nil
            println(error)
        }
        
        if self.highlightedImage == nil &&
            !options.contains(LGWebImageOptions.ignorePlaceHolder) &&
            placeholder != nil
        {
            LGWebImageManager.default.workQueue.async(flags: DispatchWorkItemFlags.barrier) { [weak self] in
                self?.highlightedImage = placeholder
            }
        }
        
        if self.lg_highlightedImageURL == nil {
            return
        }
        
        self.lg_highlightedCallbackToken = LGWebImageManager.default.downloadImageWith(url: imageURL,
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
                            if weakSelf.isHighlighted {
                                weakSelf.layer.removeAnimation(forKey: kLGWebImageFadeAnimationKey)
                            }
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
                            if needFadeAnimation && !weakSelf.isHighlighted {
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
                                weakSelf.layer.add(transition, forKey: kLGWebImageFadeAnimationKey)
                            }
                            weakSelf.highlightedImage = result
                        }
                    }
                }
                
                DispatchQueue.main.async {
                    completionBlock?(resultImage, url, sourceType, imageStage, error)
                }
        })
    }
    
    /// 取消高亮图片请求
    public func lg_cancelCurrentHighlightedImageRequest() {
        if let token = self.lg_highlightedCallbackToken {
            LGWebImageManager.default.cancelWith(callbackToken: token)
            self.lg_highlightedCallbackToken = nil
        }
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
            LGWebImageManager.default.workQueue.async(flags: DispatchWorkItemFlags.barrier)
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
            LGWebImageManager.default.workQueue.async(flags: DispatchWorkItemFlags.barrier) { [weak self] in
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
