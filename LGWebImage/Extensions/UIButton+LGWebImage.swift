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
        static var imageSetterKey = "lg_imageSetterKey"
        static var backgroundImageSetterKey = "lg_backgroundImageSetterKey"
    }
    
    private typealias ImageSetterContainer = [UIControl.State.RawValue: LGWebImageOperationSetter]
    
    private var imageSetterContainer: ImageSetterContainer {
        set {
            objc_setAssociatedObject(self,
                                     &AssociatedKeys.imageSetterKey,
                                     newValue,
                                     objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        } get {
            if let temp = objc_getAssociatedObject(self, &AssociatedKeys.imageSetterKey),
                let setters = temp as? ImageSetterContainer
            {
                return setters
            } else {
                let setters = ImageSetterContainer()
                self.imageSetterContainer = setters
                return setters
            }
        }
    }
    
    private var backgroundImageSetterContainer: ImageSetterContainer {
        set {
            objc_setAssociatedObject(self,
                                     &AssociatedKeys.backgroundImageSetterKey,
                                     newValue,
                                     objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        } get {
            if let temp = objc_getAssociatedObject(self, &AssociatedKeys.backgroundImageSetterKey),
                let setters = temp as? ImageSetterContainer
            {
                return setters
            } else {
                let setters = ImageSetterContainer()
                self.imageSetterContainer = setters
                return setters
            }
        }
    }
    
    // MARK: - public functions
    // MARK: - 普通Image
    public func lg_imageURLForState(_ state: UIControl.State) -> LGURLConvertible? {
        return self.imageSetterContainer[state.rawValue]?.imageURL
    }
    
    public func lg_cancelImageRequestForState(_ state: UIControl.State) {
        self.imageSetterContainer[state.rawValue]?.cancel()
    }
    
    public func lg_setImageWithURL(_ imageURL: LGURLConvertible,
                                   forState state: UIControl.State,
                                   placeholder: UIImage? = nil,
                                   options: LGWebImageOptions = LGWebImageOptions.default,
                                   progressBlock: LGWebImageProgressBlock? = nil,
                                   transformBlock: LGWebImageTransformBlock? = nil,
                                   completionBlock: LGWebImageCompletionBlock? = nil)
    {
        var sentinel: LGWebImageOperationSetter.Sentinel
        var setter: LGWebImageOperationSetter
        if let temp = self.imageSetterContainer[state.rawValue] {
            setter = temp
            sentinel = setter.cancel(withNewURL: imageURL)
        } else {
            let temp = LGWebImageOperationSetter()
            self.imageSetterContainer[state.rawValue] = temp
            sentinel = temp.cancel(withNewURL: imageURL)
            setter = temp
        }
        
        do {
            let newURL = try imageURL.asURL()
            if  let image = LGImageCache.default.getImage(forKey: newURL.absoluteString,
                                                          withType: LGImageCacheType.memory)
            {
                self.setImage(image, for: state)
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
                self.setImage(placeholder, for: state)
            } else {
                self.setImage(nil, for: state)
            }
            return 
        }
        
        
        if !options.contains(LGWebImageOptions.ignorePlaceHolder) &&
            placeholder != nil
        {
            self.setImage(placeholder, for: state)
        } else {
            self.setImage(nil, for: state)
        }
        
        let task = DispatchWorkItem {
            var newSentinel: LGWebImageOperationSetter.Sentinel = 0
            newSentinel = setter.setOperation(with: sentinel,
                                              URL: imageURL,
                                              options: options,
                                              manager: LGWebImageManager.default,
                                              progress:
                { (progress) in
                    progressBlock?(progress)
            }, completion: { [weak self] (resultImage, url, sourceType, imageStage, error) in
                guard let strongSelf = self, strongSelf.imageSetterContainer[state.rawValue]?.sentinel == newSentinel else {
                    completionBlock?(resultImage, url, sourceType, imageStage, error)
                    return
                }
                
                if resultImage != nil && error == nil {
                    let avoidSetImage = options.contains(LGWebImageOptions.avoidSetImage)
                    
                    
                    let imageIsValid = (imageStage == .finished || imageStage == .progress)
                    let canSetImage = (!avoidSetImage && imageIsValid)
                    
                    var result = resultImage
                    if let cornerRadiusImage = self?.cornerRadius(resultImage) {
                        result = cornerRadiusImage
                    }
                    
                    if canSetImage {
                        strongSelf.setImage(result, for: state)
                    }
                }
                
                completionBlock?(resultImage, url, sourceType, imageStage, error)
            })
        }
        
        setter.runTask(task)
    }
    
    // MARK: -  backgroundImage
    
    public func lg_backgroundImageURLForState(_ state: UIControl.State) -> LGURLConvertible? {
        return self.backgroundImageSetterContainer[state.rawValue]?.imageURL
    }
    
    public func lg_cancelBackgroundImageRequestForState(_ state: UIControl.State) {
        self.backgroundImageSetterContainer[state.rawValue]?.cancel()
    }
    
    public func lg_setBackgroundImageWithURL(_ imageURL: LGURLConvertible,
                                             forState state: UIControl.State,
                                             placeholder: UIImage? = nil,
                                             options: LGWebImageOptions = LGWebImageOptions.default,
                                             progressBlock: LGWebImageProgressBlock? = nil,
                                             transformBlock: LGWebImageTransformBlock? = nil,
                                             completionBlock: LGWebImageCompletionBlock? = nil)
    {
        var sentinel: LGWebImageOperationSetter.Sentinel
        var setter: LGWebImageOperationSetter
        if let temp = self.backgroundImageSetterContainer[state.rawValue] {
            setter = temp
            sentinel = setter.cancel(withNewURL: imageURL)
        } else {
            let temp = LGWebImageOperationSetter()
            self.backgroundImageSetterContainer[state.rawValue] = temp
            sentinel = temp.cancel(withNewURL: imageURL)
            setter = temp
        }
        
        do {
            let newURL = try imageURL.asURL()
            if  let image = LGImageCache.default.getImage(forKey: newURL.absoluteString,
                                                          withType: LGImageCacheType.memory)
            {
                
                self.setBackgroundImage(image, for: state)
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
                self.setBackgroundImage(placeholder, for: state)
            } else {
                self.setBackgroundImage(nil, for: state)
            }
            return
        }
        
        if !options.contains(LGWebImageOptions.ignorePlaceHolder) &&
            placeholder != nil
        {
            self.setBackgroundImage(placeholder, for: state)
        } else {
            self.setBackgroundImage(nil, for: state)
        }
        
        let task = DispatchWorkItem {
            var newSentinel: LGWebImageOperationSetter.Sentinel = 0
            newSentinel = setter.setOperation(with: sentinel,
                                              URL: imageURL,
                                              options: options,
                                              manager: LGWebImageManager.default,
                                              progress:
                { (progress) in
                    progressBlock?(progress)
            }, completion: { [weak self] (resultImage, url, sourceType, imageStage, error) in
                guard let strongSelf = self, strongSelf.imageSetterContainer[state.rawValue]?.sentinel == newSentinel else {
                    completionBlock?(resultImage, url, sourceType, imageStage, error)
                    return
                }
                
                if resultImage != nil && error == nil {
                    let avoidSetImage = options.contains(LGWebImageOptions.avoidSetImage)
                    
                    
                    let imageIsValid = (imageStage == .finished || imageStage == .progress)
                    let canSetImage = (!avoidSetImage && imageIsValid)
                    
                    var result = resultImage
                    if let cornerRadiusImage = self?.cornerRadius(resultImage) {
                        result = cornerRadiusImage
                    }
                    
                    if canSetImage {
                        strongSelf.setBackgroundImage(result, for: state)
                    }
                }
                
                completionBlock?(resultImage, url, sourceType, imageStage, error)
            })
        }
        
        setter.runTask(task)
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
    
    @objc func lg_setImage(_ image: UIImage?, for state: UIControl.State) {
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
                        weakSelf.lg_setImage(result, for: state)
                    }
                }
            }
        } else {
            self.lg_setImage(image, for: state)
        }
    }
    
    @objc func lg_setBackgroundImage(_ image: UIImage?, for state: UIControl.State) {
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
                        weakSelf.lg_setBackgroundImage(result, for: state)
                    }
                }
            }
        } else {
            self.lg_setBackgroundImage(image, for: state)
        }
    }
}
