//
//  MKAnnotationView+LGWebImage.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2018/4/23.
//  Copyright © 2018年 龚杰洪. All rights reserved.
//

import Foundation
import MapKit
import LGHTTPRequest

public extension MKAnnotationView {
    private struct AssociatedKeys {
        static var URLKey = "LGWebImageURLKey"
        static var TokenKey = "LGWebImageTokenKey"
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
        self.lg_cancelCurrentImageRequest()
        self.image = nil
        
        do {
            let newURL = try imageURL.asURL()
            self.lg_imageURL = imageURL
            if let image = LGImageCache.default.getImage(forKey: newURL.absoluteString,
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
            LGWebImageManager.default.workQueue.async(flags: DispatchWorkItemFlags.barrier) { [weak self] in
                var placeholderImage: UIImage? = nil
                if let image = placeholder?.lg_imageByDecoded {
                    placeholderImage = image
                    DispatchQueue.main.async { [weak self] in
                        self?.image = placeholderImage
                    }
                }
            }
        }
        
        if self.lg_imageURL == nil {
            return
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
                            weakSelf.layer.removeAnimation(forKey: kLGWebImageFadeAnimationKey)
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
    public func lg_cancelCurrentImageRequest() {
        if let token = self.lg_callbackToken {
            LGWebImageManager.default.cancelWith(callbackToken: token)
            self.lg_callbackToken = nil
        }
    }
}

extension MKAnnotationView {
    static func swizzleImplementations() {
        MKAnnotationView.swizzleSetImageImplementation()
    }
    
    private static func swizzleSetImageImplementation() {
        let aClass: AnyClass = self.classForCoder()
        let originalMethod = class_getInstanceMethod(aClass, #selector(setter: MKAnnotationView.image))
        let swizzledMethod = class_getInstanceMethod(aClass, #selector(MKAnnotationView.lg_setImage(_:)))
        if let originalMethod = originalMethod, let swizzledMethod = swizzledMethod {
            // switch implementation..
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }
    
    @objc func lg_setImage(_ image: UIImage?) {
        if self.lg_needSetCornerRadius == true {
            LGWebImageManager.default.workQueue.async(flags: DispatchWorkItemFlags.barrier)
            { [weak self] in
                var result: UIImage? = nil
                if let tempImage = image?.lg_imageByDecoded {
                    if let cornerRadiusImage = self?.cornerRadius(tempImage)
                    {
                        result = cornerRadiusImage
                    } else {
                        result = tempImage
                    }
                    DispatchQueue.main.async { [weak self] in
                        self?.lg_setImage(result)
                    }
                }
            }
        } else {
            self.lg_setImage(image)
        }
    }
}
