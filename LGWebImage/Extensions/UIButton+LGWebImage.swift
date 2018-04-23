//
//  UIButton+LGWebImage.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2018/4/20.
//  Copyright © 2018年 龚杰洪. All rights reserved.
//

import Foundation
import LGHTTPRequest

public extension UIButton {
    // MARK: -  private containers
    private struct AssociatedKeys {
        static var imageURLKey = "lg_imageURLKey"
        static var backgroundImageURLKey = "lg_backgroundImageURLKey"
        static var imageTokenKey = "lg_imageTokenKey"
        static var backgroundImageTokenKey = "lg_backgroundImageTokenKey"
    }
    
    private typealias CallbackTokenContainer = [UIControlState.RawValue: LGWebImageCallbackToken]
    private typealias URLContainer = [UIControlState.RawValue: LGURLConvertible]
    
    private var imageTokenContainer: CallbackTokenContainer {
        set {
            objc_setAssociatedObject(self,
                                     &AssociatedKeys.imageTokenKey,
                                     newValue,
                                     objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            
        } get {
            let temp = objc_getAssociatedObject(self, &AssociatedKeys.imageTokenKey)
            if let container = temp as? CallbackTokenContainer {
                return container
            } else {
                let container = CallbackTokenContainer()
                self.imageTokenContainer = container
                return container
            }
        }
    }
    
    private var imageUrlContainer: URLContainer {
        set {
            objc_setAssociatedObject(self,
                                     &AssociatedKeys.imageURLKey,
                                     newValue,
                                     objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            
        } get {
            let temp = objc_getAssociatedObject(self, &AssociatedKeys.imageURLKey)
            if let container = temp as? URLContainer {
                return container
            } else {
                let container = URLContainer()
                self.imageUrlContainer = container
                return container
            }
        }
    }
    
    private var backgroundImageTokenContainer: CallbackTokenContainer {
        set {
            objc_setAssociatedObject(self,
                                     &AssociatedKeys.backgroundImageTokenKey,
                                     newValue,
                                     objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            
        } get {
            let temp = objc_getAssociatedObject(self, &AssociatedKeys.backgroundImageTokenKey)
            if let container = temp as? CallbackTokenContainer {
                return container
            } else {
                let container = CallbackTokenContainer()
                self.backgroundImageTokenContainer = container
                return container
            }
        }
    }
    
    private var backgroundImageUrlContainer: URLContainer {
        set {
            objc_setAssociatedObject(self,
                                     &AssociatedKeys.backgroundImageURLKey,
                                     newValue,
                                     objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            
        } get {
            let temp = objc_getAssociatedObject(self, &AssociatedKeys.backgroundImageURLKey)
            if let container = temp as? URLContainer {
                return container
            } else {
                let container = URLContainer()
                self.imageUrlContainer = container
                return container
            }
        }
    }
    
    // MARK: - public functions
    // MARK: - 普通Image
    public func lg_imageURLForState(_ state: UIControlState) -> LGURLConvertible? {
        return self.imageUrlContainer[state.rawValue]
    }
    
    public func lg_cancelImageRequestForState(_ state: UIControlState) {
        if let token = self.imageTokenContainer[state.rawValue] {
            LGWebImageManager.default.cancelWith(callbackToken: token)
        }
    }
    
    public func lg_setImageWithURL(_ imageURL: LGURLConvertible,
                                   forState state: UIControlState,
                                   placeholder: UIImage? = nil,
                                   options: LGWebImageOptions = LGWebImageOptions.default,
                                   progressBlock: LGWebImageProgressBlock? = nil,
                                   transformBlock: LGWebImageTransformBlock? = nil,
                                   completionBlock: LGWebImageCompletionBlock? = nil)
    {
        self.imageUrlContainer[state.rawValue] = imageURL
        
        if let token = self.imageTokenContainer[state.rawValue] {
            LGWebImageManager.default.cancelWith(callbackToken: token)
            self.imageTokenContainer[state.rawValue] = nil
            self.setImage(nil, for: state)
        }
        
        if self.image(for: state) == nil &&
            !options.contains(LGWebImageOptions.ignorePlaceHolder) &&
            placeholder != nil
        {
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
                        self?.setImage(placeholderImage, for: state)
                    }
                }
            }
        }
        
        let token = LGWebImageManager.default.downloadImageWith(url: imageURL,
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
                    let avoidSetImage = options.contains(LGWebImageOptions.avoidSetImage)
                    
                    
                    let imageIsValid = (imageStage == .finished || imageStage == .progress)
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
                            weakSelf.setImage(result, for: state)
                        }
                    }
                }
                
                DispatchQueue.main.async {
                    completionBlock?(resultImage, url, sourceType, imageStage, error)
                }
        })
        self.imageTokenContainer[state.rawValue] = token
    }
    
    // MARK: -  backgroundImage
    
    public func lg_backgroundImageURLForState(_ state: UIControlState) -> LGURLConvertible? {
        return self.backgroundImageUrlContainer[state.rawValue]
    }
    
    public func lg_cancelBackgroundImageRequestForState(_ state: UIControlState) {
        if let token = self.backgroundImageTokenContainer[state.rawValue] {
            LGWebImageManager.default.cancelWith(callbackToken: token)
        }
    }
    
    public func lg_setBackgroundImageWithURL(_ imageURL: LGURLConvertible,
                                             forState state: UIControlState,
                                             placeholder: UIImage? = nil,
                                             options: LGWebImageOptions = LGWebImageOptions.default,
                                             progressBlock: LGWebImageProgressBlock? = nil,
                                             transformBlock: LGWebImageTransformBlock? = nil,
                                             completionBlock: LGWebImageCompletionBlock? = nil)
    {
        self.backgroundImageUrlContainer[state.rawValue] = imageURL
        
        if let token = self.backgroundImageTokenContainer[state.rawValue] {
            LGWebImageManager.default.cancelWith(callbackToken: token)
            self.backgroundImageTokenContainer[state.rawValue] = nil
            self.setBackgroundImage(nil, for: state)
        }
        
        if self.image(for: state) == nil &&
            !options.contains(LGWebImageOptions.ignorePlaceHolder) &&
            placeholder != nil
        {
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
                        self?.setBackgroundImage(placeholderImage, for: state)
                    }
                }
            }
        }
        
        let token = LGWebImageManager.default.downloadImageWith(url: imageURL,
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
                    let avoidSetImage = options.contains(LGWebImageOptions.avoidSetImage)
                    
                    
                    let imageIsValid = (imageStage == .finished || imageStage == .progress)
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
                            weakSelf.setBackgroundImage(result, for: state)
                        }
                    }
                }
                
                DispatchQueue.main.async {
                    completionBlock?(resultImage, url, sourceType, imageStage, error)
                }
        })
        self.backgroundImageTokenContainer[state.rawValue] = token
    }
}

extension UIButton {
    static func swizzleImplementations() {
        UIButton.swizzleSetImageImplementation()
        UIButton.swizzleSetBackgroundImageImplementation()
    }
    
    private static func swizzleSetImageImplementation() {
        let aClass: AnyClass = self.classForCoder()
        let originalMethod = class_getInstanceMethod(aClass, #selector(UIButton.setImage(_:for:)))
        let swizzledMethod = class_getInstanceMethod(aClass, #selector(UIButton.lg_setImage(_:for:)))
        if let originalMethod = originalMethod, let swizzledMethod = swizzledMethod {
            // switch implementation..
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }
    
    private static func swizzleSetBackgroundImageImplementation() {
        let aClass: AnyClass = self.classForCoder()
        let originalMethod = class_getInstanceMethod(aClass, #selector(UIButton.setBackgroundImage(_:for:)))
        let swizzledMethod = class_getInstanceMethod(aClass, #selector(UIButton.lg_setBackgroundImage(_:for:)))
        if let originalMethod = originalMethod, let swizzledMethod = swizzledMethod {
            // switch implementation..
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }
    
    @objc func lg_setImage(_ image: UIImage?, for state: UIControlState) {
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
                        self?.lg_setImage(result, for: state)
                    }
                }
            }
        } else {
            self.lg_setImage(image, for: state)
        }
    }
    
    @objc func lg_setBackgroundImage(_ image: UIImage?, for state: UIControlState) {
        if self.lg_needSetCornerRadius == true {
            LGWebImageManager.default.workQueue.async(flags: DispatchWorkItemFlags.barrier) { [weak self] in
                var result: UIImage? = nil
                if let tempImage = image?.lg_imageByDecoded {
                    if let cornerRadiusImage = self?.cornerRadius(tempImage)
                    {
                        result = cornerRadiusImage
                    } else {
                        result = tempImage
                    }
                    DispatchQueue.main.async { [weak self] in
                        self?.lg_setBackgroundImage(result, for: state)
                    }
                }
            }
        } else {
            self.lg_setBackgroundImage(image, for: state)
        }
    }
}
