//
//  UIView+LGWebImage.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2018/4/17.
//  Copyright © 2018年 龚杰洪. All rights reserved.
//

import Foundation

public struct LGCornerRadiusConfig {
    public var cornerRadius: CGFloat = 0.0
    public var corners: UIRectCorner = UIRectCorner.allCorners
    public var borderWidth: CGFloat = 0.0
    public var borderColor: UIColor? = nil
    public var borderLineJoin: CGLineJoin = CGLineJoin.miter
    
    public init(cornerRadius: CGFloat,
                corners: UIRectCorner = UIRectCorner.allCorners,
                borderWidth: CGFloat = 0.0,
                borderColor: UIColor? = nil,
                borderLineJoin: CGLineJoin = CGLineJoin.miter)
    {
        self.cornerRadius = cornerRadius
        self.corners = corners
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.borderLineJoin = borderLineJoin
    }
    
    public var needSetCornerRadius: Bool {
        return self.cornerRadius != 0.0 || self.borderWidth != 0
    }
}

public extension UIView {
    private struct AssociatedKeys {
        static var cornerRadiusKey = "lg_cornerRadius"
    }
    
    public var needSetCornerRadius: Bool {
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
            var result = image?.lg_imageByResizeToSize(size, contentMode: self.contentMode)
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
