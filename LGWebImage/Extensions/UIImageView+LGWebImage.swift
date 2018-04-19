//
//  UIImageView+LGWebImage.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2018/4/16.
//  Copyright © 2018年 龚杰洪. All rights reserved.
//

import Foundation
import LGHTTPRequest
import MapKit

let kLGWebImageFadeAnimationKey = "LGWebImageFadeAnimation"

fileprivate var LGWebImageNormalURLKey = "LGWebImageNormalURLKey"
fileprivate var LGWebImageHighlightedURLKey = "LGWebImageHighlightedURLKey"

fileprivate var LGWebImageNormalTokenKey = "LGWebImageNormalTokenKey"
fileprivate var LGWebImageHighlightedTokenKey = "LGWebImageHighlightedTokenKey"

public extension UIImageView {
    // MARK: -  普通状态
    
    /// 普通状态图片URL
    public var lg_imageURL: URL? {
        set {
            objc_setAssociatedObject(self,
                                     &LGWebImageNormalURLKey,
                                     newValue,
                                     objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            if let url = newValue {
                self.lg_setImageWithURL(url)
            }
        } get {
            return objc_getAssociatedObject(self, &LGWebImageNormalURLKey) as? URL
        }
    }
    
    /// 普通状态下的下载回调token
    private var lg_normalCallbackToken: LGWebImageCallbackToken? {
        set {
            objc_setAssociatedObject(self,
                                     &LGWebImageNormalTokenKey,
                                     newValue,
                                     objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        } get {
            return objc_getAssociatedObject(self, &LGWebImageNormalTokenKey) as? LGWebImageCallbackToken
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
        if let token = self.lg_normalCallbackToken {
            LGWebImageManager.default.cancelWith(callbackToken: token)
            self.lg_normalCallbackToken = nil
            self.image = nil
        }
        
        if self.image == nil && !options.contains(LGWebImageOptions.ignorePlaceHolder) && placeholder != nil {
            LGWebImageManager.default.workQueue.async(flags: DispatchWorkItemFlags.barrier) { [weak self] in
                var placeholderImage: UIImage? = nil
                if let image = placeholder?.lg_imageByDecoded {
                    if let cornerRadiusImage = self?.cornerRadius(image)
                    {
                        placeholderImage = cornerRadiusImage
                    } else {
                        placeholderImage = image
                    }
                    DispatchQueue.main.async { [weak self] in
                        self?.image = placeholderImage
                    }
                }
            }
        }
        
        self.lg_normalCallbackToken = LGWebImageManager.default.downloadImageWith(url: imageURL,
                                                                                  options: options,
                                                                                  progress:
            { (progress) in
                DispatchQueue.main.async {
                    progressBlock?(progress)
                }
        }, completion: {[weak self] (resultImage, url, sourceType, imageStage, error) in
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
                
                let imageIsValid = (imageStage == LGWebImageStage.finished || imageStage == LGWebImageStage.progress)
                let canSetImage = (!avoidSetImage && imageIsValid)
                
                var result = resultImage
                if let cornerRadiusImage = self?.cornerRadius(resultImage) {
                    result = cornerRadiusImage
                }
                
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
                            transition.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)
                            transition.type = kCATransitionFade
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
    public var lg_highlightedImageURL: URL? {
        set {
            objc_setAssociatedObject(self,
                                     &LGWebImageHighlightedURLKey,
                                     newValue,
                                     objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            if let url = newValue {
                self.lg_setHighlightedImageWithURL(url)
            }
        } get {
            return objc_getAssociatedObject(self, &LGWebImageHighlightedURLKey) as? URL
        }
    }

    /// 高亮状态下的下载回调token
    private var lg_highlightedCallbackToken: LGWebImageCallbackToken? {
        set {
            objc_setAssociatedObject(self,
                                     &LGWebImageHighlightedTokenKey,
                                     newValue,
                                     objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        } get {
            return objc_getAssociatedObject(self, &LGWebImageHighlightedTokenKey) as? LGWebImageCallbackToken
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
                                              completionBlock: LGWebImageCompletionBlock? = nil)
    {
        if let token = self.lg_highlightedCallbackToken {
            LGWebImageManager.default.cancelWith(callbackToken: token)
            self.lg_highlightedCallbackToken = nil
            self.highlightedImage = nil
        }
        
        if self.highlightedImage == nil &&
            !options.contains(LGWebImageOptions.ignorePlaceHolder) &&
            placeholder != nil
        {
            DispatchQueue.userInitiated.async { [weak self] in
                var placeholderImage: UIImage? = nil
                if let image = placeholder?.lg_imageByDecoded {
                    if let cornerRadiusImage = self?.cornerRadius(image)
                    {
                        placeholderImage = cornerRadiusImage
                    } else {
                        placeholderImage = image
                    }
                    DispatchQueue.main.async { [weak self] in
                        self?.highlightedImage = placeholderImage
                    }
                }
            }
        }
        
        self.lg_highlightedCallbackToken = LGWebImageManager.default.downloadImageWith(url: imageURL,
                                                                                       options: options,
                                                                                       progress:
            { (progress) in
                DispatchQueue.main.async {
                    progressBlock?(progress)
                }
        }, completion: {[weak self] (resultImage, url, sourceType, imageStage, error) in
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
                
                let imageIsValid = (imageStage == LGWebImageStage.finished || imageStage == LGWebImageStage.progress)
                let canSetImage = (!avoidSetImage && imageIsValid)
                
                var result = resultImage
                if let cornerRadiusImage = self?.cornerRadius(resultImage) {
                    result = cornerRadiusImage
                }
                
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
                            transition.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)
                            transition.type = kCATransitionFade
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
