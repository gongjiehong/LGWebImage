//
//  LGAnimatedImage.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2017/10/9.
//  Copyright © 2017年 龚杰洪. All rights reserved.
//

import Foundation

@objc public protocol LGAnimatedImage: NSObjectProtocol {
    func animatedImageFrameCount() -> Int
    func animatedImageLoopCount() -> Int
    func animatedImageBytesPerFrame() -> Int
    func animatedImageFrame(atIndex index: Int) -> UIImage?
    func animatedImageDuration(atIndex index: Int) -> TimeInterval
    
    @objc optional
    func animatedImageContentsRect(atIndex index: Int) -> CGRect
}
