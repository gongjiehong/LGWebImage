//
//  UIImageView+LGWebImage.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2018/4/16.
//  Copyright © 2018年 龚杰洪. All rights reserved.
//

import Foundation

fileprivate var LGWebImageNormalKey: Int = 0
fileprivate var LGWebImageHighlightedKey: Int = 1

public extension UIImageView {
    public var lg_imageURL: URL? {
        set {
            objc_setAssociatedObject(self,
                                     &LGWebImageNormalKey,
                                     newValue,
                                     objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        } get {
            return objc_getAssociatedObject(self, &LGWebImageNormalKey) as? URL
        }
    }
}
