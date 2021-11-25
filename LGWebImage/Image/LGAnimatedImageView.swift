//
//  LGAnimatedImageView.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2017/10/9.
//  Copyright © 2017年 龚杰洪. All rights reserved.
//

import UIKit

/// 获取剩余内存大小，用总内存减去已经使用的内存大小，（并不准确）
///
/// - Returns: 可用内存大小
public func LGDeviceMemoryFree() -> UInt64 {
    let hostPort = mach_host_self()
    let dataTypeSize = MemoryLayout.size(ofValue: vm_statistics_data_t())
    let integerTypeSize = MemoryLayout.size(ofValue: integer_t())
    var hostSize: mach_msg_type_number_t = mach_msg_type_number_t(dataTypeSize / integerTypeSize)
    var pageSize: vm_size_t = 0
    var vmStat: vm_statistics_data_t = vm_statistics_data_t()
    var kern: kern_return_t = 0
    
    kern = host_page_size(hostPort, &pageSize)
    if kern != KERN_SUCCESS {
        return 0
    }
    
    let pointer = UnsafeMutablePointer(&vmStat)
    pointer.withMemoryRebound(to: integer_t.self, capacity: 60) {
        kern = host_statistics(hostPort, HOST_VM_INFO, $0, &hostSize)
    }
    if kern != KERN_SUCCESS {
        return 0
    }
    let used = UInt64(vmStat.active_count + vmStat.inactive_count + vmStat.wire_count) * UInt64(pageSize)
    return UIDevice.physicalMemory - used
}


/// 图片数据类型
///
/// - none: 未知
/// - image: 普通image
/// - highlightedImage: 高亮image
/// - images: 普通状态下动画图数组
/// - highlightedImages: 高亮状态下状态图数组
public enum LGAnimatedImageType {
    case none
    case image
    case highlightedImage
    case images
    case highlightedImages
}


/// 请求每一帧图片的线程
fileprivate class LGAnimatedImageViewFetchOperation: Operation {
    weak var imageView: LGAnimatedImageView?
    var nextIndex: Int = 0
    var currentImage: LGAnimatedImage?
    
    override func main() {
        guard let view = imageView else {
            return
        }
        if isCancelled {
            return
        }
        view.incrBufferCount += 1
        if view.incrBufferCount == 0 {
            view.calcMaxBufferCount()
        }
        if view.incrBufferCount > view.maxBufferCount {
            view.incrBufferCount = view.maxBufferCount
        }
        
        var index = nextIndex
        let max = view.incrBufferCount < 1 ? 1 : view.incrBufferCount
        let total = view.totalFrameCount
        
        for _ in 0..<max {
            
            if index >= total {
                index = 0
            }
            
            if isCancelled {
                break
            }
            view.lock.lg_lock()
            let miss = view.buffer[index] == nil
            view.lock.lg_unlock()
            
            if miss {
                var img = currentImage?.animatedImageFrame(atIndex: index)
                img = img?.lg_imageByDecoded
                if isCancelled {
                    break
                }
                view.lock.lg_lock()
                view.buffer[index] = img ?? NSNull()
                view.lock.lg_unlock()
            }
            index += 1
        }
        
    }
}


/// 展示动态图片的imageView
open class LGAnimatedImageView: UIImageView {

    /// 是否自动播放动图，默认true
    public var isAutoPlayAnimatedImage: Bool = true
    
    
    /// 当前播放到的帧角标
    public var currentAnimatedImageIndex: Int = 0 
    
    
    /// runloop，用于例如滑动时停止播放
    public var runLoopMode: RunLoop.Mode = RunLoop.Mode.default {
        willSet {
            if timer != nil {
                timer?.remove(from: RunLoop.main, forMode: runLoopMode)
            }
        }
        didSet {
            if timer != nil {
                timer?.add(to: RunLoop.main, forMode: runLoopMode)
            }
        }
    }
    
    
    public var maxBufferSize: Int = 0
    
    public private(set) var currentIsPlayingAnimation: Bool = false
    
    override open var isAnimating: Bool {
        return currentIsPlayingAnimation
    }
    
    override open var image: UIImage? {
        set {
            setImage(image: newValue, with: LGAnimatedImageType.image)
        }
        get {
            return super.image
        }
    }
    
    override open var highlightedImage: UIImage? {
        set {
            setImage(image: newValue, with: LGAnimatedImageType.highlightedImage)
        }
        get {
            return super.highlightedImage
        }
    }
    
    override open var animationImages: [UIImage]? {
        set {
            setImage(image: newValue, with: LGAnimatedImageType.images)
        }
        get {
            return super.animationImages
        }
    }
    
    override open var highlightedAnimationImages: [UIImage]? {
        set {
            setImage(image: newValue, with: LGAnimatedImageType.highlightedImages)
        }
        get {
            return super.highlightedAnimationImages
        }
    }

    // MARK: - 初始化
    override public init(frame: CGRect) {
        super.init(frame: frame)
    }

    override public init(image: UIImage?) {
        super.init(frame: CGRect.zero)
        if image != nil {
            self.frame = CGRect(x: 0.0, y: 0.0, width: image!.size.width, height: image!.size.height)
        }
        self.image = image
    }
    
    override public init(image: UIImage?, highlightedImage: UIImage?) {
        super.init(frame: CGRect.zero)
        if image != nil {
            self.frame = CGRect(x: 0.0, y: 0.0, width: image!.size.width, height: image!.size.height)
        } else if (highlightedImage != nil) {
            self.frame = CGRect(x: 0.0,
                                y: 0.0,
                                width: highlightedImage!.size.width,
                                height: highlightedImage!.size.height)
        }
        self.image = image
        self.highlightedImage = highlightedImage
    }
    
    // MARK: -  coder
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        if let tempMode = aDecoder.decodeObject(forKey: "runLoopMode") as? RunLoop.Mode {
            runLoopMode = tempMode
        } else {
            runLoopMode = RunLoop.Mode.common
        }
        // decode bool 默认值为false，所以需要判断处理
        if aDecoder.containsValue(forKey: "isAutoPlayAnimatedImage") {
            isAutoPlayAnimatedImage = aDecoder.decodeBool(forKey: "isAutoPlayAnimatedImage")
        } else {
            isAutoPlayAnimatedImage = true
        }
        
        if let image = aDecoder.decodeObject(forKey: "lg_image") as? UIImage {
            self.image = image
            setImage(image: image, with: LGAnimatedImageType.image)
        }
        if let highlightedImage = aDecoder.decodeObject(forKey: "lg_highlightedImage") as? UIImage {
            self.highlightedImage = highlightedImage
            setImage(image: highlightedImage, with: LGAnimatedImageType.highlightedImage)
        }
        
    }
    
    override open func encode(with aCoder: NSCoder) {
        super.encode(with: aCoder)
        aCoder.encode(runLoopMode, forKey: "runLoopMode")
        aCoder.encode(isAutoPlayAnimatedImage, forKey: "isAutoPlayAnimatedImage")

        var ani: Bool = false, multi: Bool = false
        
        ani = self.image?.conforms(to: LGAnimatedImage.self) == true
        if ani {
            if let tempImage = self.image as? LGAnimatedImage {
                if tempImage.animatedImageFrameCount() > 1 {
                    multi = true
                }
            }
        }
        if multi {
            aCoder.encode(self.image, forKey: "lg_image")
        }
        
        ani = self.highlightedImage?.conforms(to: LGAnimatedImage.self) == true
        if ani {
            if let tempImage = self.highlightedImage as? LGAnimatedImage {
                if tempImage.animatedImageFrameCount() > 1 {
                    multi = true
                }
            }
        }
        if multi {
            aCoder.encode(self.image, forKey: "lg_highlightedImage")
        }
    }
    
    // MARK: -  fileprivate
    fileprivate var currentAnimatedImage: LGAnimatedImage?

    fileprivate var lock: DispatchSemaphore = DispatchSemaphore(value: 1)
    fileprivate lazy var requestQueue: OperationQueue =  {
        return OperationQueue()
    }()
    fileprivate var timer: CADisplayLink?
    fileprivate var time: TimeInterval = 0
    
    fileprivate var currentFrame: UIImage?
//    fileprivate var currentIndex: Int = 0
    fileprivate var totalFrameCount: Int = 1
    
    fileprivate var isLoopEnd: Bool = false
    fileprivate var currentLoop: Int = 0
    fileprivate var totalLoop: Int = 0
    
    fileprivate var buffer: [Int: Any] = [Int: Any]()
    fileprivate var isBufferMiss: Bool = false
    fileprivate var maxBufferCount: Int = 0
    fileprivate var incrBufferCount: Int = 0
    fileprivate var currentContentsRect: CGRect = CGRect.zero
    fileprivate var isCurrentImageHasContentsRect: Bool = false
    
    fileprivate func calcMaxBufferCount() {
        guard var bytesCount = currentAnimatedImage?.animatedImageBytesPerFrame() else {
            return
        }
        if bytesCount == 0 {
            bytesCount = 1_024
        }
        
        let total = UIDevice.physicalMemory
        let free = LGDeviceMemoryFree()
        var maxCount = min(Double(total) * 0.2, Double(free) * 0.6)
        maxCount = max(maxCount, 10 * 1_024 * 1_024)
        if maxBufferSize != 0 {
            maxCount = maxCount > Double(maxBufferSize) ? Double(maxBufferSize) : maxCount
        }
        var tempCount = maxCount / Double(bytesCount)
        if tempCount < 1 {
            tempCount = 1
        } else if tempCount > 512 {
            tempCount = 512
        }
        maxBufferCount = Int(tempCount)
    }
    
    // MARK: -  析构
    
    deinit {
        requestQueue.cancelAllOperations()
        timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}

extension LGAnimatedImageView {
    func setImage(image: Any?, with type: LGAnimatedImageType) {
        self.stopAnimating()
        if timer != nil {
            resetAnimated()
        }
        currentFrame = nil
        switch type {
        case LGAnimatedImageType.none:
            break
        case LGAnimatedImageType.image:
            super.image = image as? UIImage
            break
        case LGAnimatedImageType.images:
            super.animationImages = image as? [UIImage]
            break
        case LGAnimatedImageType.highlightedImage:
            super.highlightedImage = image as? UIImage
            break
        case LGAnimatedImageType.highlightedImages:
            super.highlightedAnimationImages = image as? [UIImage]
            break
        }
        imageChanged()
    }
    
    func imageChanged() {
        let newType = currentImageType()
        let newVisibleImage = image(for: newType)
        var newImageFrameCount:Int = 0
        var hasContentsRect: Bool = false
        if let tempImg = newVisibleImage as? LGAnimatedImage {
            newImageFrameCount = tempImg.animatedImageFrameCount()
            if newImageFrameCount > 1 {
                hasContentsRect = tempImg.responds(to: #selector(LGAnimatedImage.animatedImageContentsRect(atIndex:)))
            }
        }
        
        
        
        if !hasContentsRect && isCurrentImageHasContentsRect  {
            if self.layer.contentsRect != CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0) {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.layer.contentsRect = CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0)
                CATransaction.commit()
            }
        }
        isCurrentImageHasContentsRect = hasContentsRect

        if hasContentsRect {
            if let rect = (newVisibleImage as? LGAnimatedImage)?.animatedImageContentsRect!(atIndex: 0) {
                setContentsRect(rect, for: newVisibleImage as? UIImage)
            }
        }

        if newImageFrameCount > 1 {
            self.resetAnimated()
            currentAnimatedImage =  newVisibleImage as? LGAnimatedImage
            currentFrame = newVisibleImage as? UIImage
            totalLoop = currentAnimatedImage?.animatedImageLoopCount() ?? 0
            totalFrameCount = currentAnimatedImage?.animatedImageFrameCount() ?? 1
            calcMaxBufferCount()
        }
        
        setNeedsDisplay()
        didMoved()
    }
    
    func resetAnimated() {
        if timer == nil {
            lock = DispatchSemaphore(value: 1)
            buffer.removeAll()
            requestQueue = OperationQueue()
            requestQueue.maxConcurrentOperationCount = 1
            timer = CADisplayLink(target: LGImageWeakTarget(target: self), selector: #selector(step(_:)))
            timer?.add(to: RunLoop.main, forMode: runLoopMode)
            timer?.isPaused = true
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(didReceiveMemoryWarning(_:)),
                                                   name: UIApplication.didReceiveMemoryWarningNotification,
                                                   object: nil)
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(didEnterBackground(_:)),
                                                   name: UIApplication.didEnterBackgroundNotification,
                                                   object: nil)
        }
        requestQueue.cancelAllOperations()
        
        lock.lg_lock()
        buffer.removeAll()
        lock.lg_unlock()
        timer?.isPaused = true
        time = 0
        
        if currentAnimatedImageIndex != 0 {
            self.currentAnimatedImageIndex = 0
        }
        
        currentAnimatedImage = nil
        currentFrame = nil
        currentLoop = 0
        totalLoop = 0
        totalFrameCount = 1
        isLoopEnd = false
        isBufferMiss = false
        incrBufferCount = 0
    }
    
    func image(for type: LGAnimatedImageType) -> Any? {
        var result: Any? = nil
        switch type {
        case LGAnimatedImageType.none:
            result = nil
            break
        case LGAnimatedImageType.image:
            result = self.image
            break
        case LGAnimatedImageType.images:
            result = self.animationImages
            break
        case LGAnimatedImageType.highlightedImage:
            result = self.highlightedImage
            break
        case LGAnimatedImageType.highlightedImages:
            result = self.highlightedAnimationImages
            break
        }
        return result
    }
    
    func currentImageType() -> LGAnimatedImageType {
        var result: LGAnimatedImageType = LGAnimatedImageType.none
        if self.isHighlighted {
            if highlightedAnimationImages != nil && highlightedAnimationImages?.count != 0 {
                result = LGAnimatedImageType.highlightedImages
            } else if self.highlightedImage != nil {
                result = LGAnimatedImageType.highlightedImage
            }
        }
        
        if result == LGAnimatedImageType.none {
            if animationImages != nil && animationImages?.count != 0 {
                result = LGAnimatedImageType.images
            } else if self.image != nil {
                result = LGAnimatedImageType.image
            }
        }
        
        return result
    }

    
    @objc func step(_ timer: CADisplayLink) {
        guard let image = self.currentAnimatedImage else {
            return
        }
        var buffer = self.buffer
        var bufferedImage: UIImage? = nil
        var nextIndex = (currentAnimatedImageIndex + 1) % totalFrameCount
        var bufferIsFull = false
        
        if isLoopEnd {
            stopAnimating()
            return
        }
        
        var delay: TimeInterval = 0
        if !isBufferMiss {
            time += timer.duration
            delay = image.animatedImageDuration(atIndex: currentAnimatedImageIndex)
            if time < delay {
                return
            }
            time -= delay
            if nextIndex == 0 {
                currentLoop += 1
                if currentLoop >= totalLoop && totalLoop != 0 {
                    isLoopEnd = true
                    stopAnimating()
                    layer.setNeedsDisplay()
                    return
                }
            }
            delay = image.animatedImageDuration(atIndex: nextIndex)
            if time > delay  {
                time = delay
            }
        }
        
        lock.lg_lock()
        bufferedImage = buffer[nextIndex] as? UIImage
        if bufferedImage != nil {
            if incrBufferCount < totalFrameCount {
                buffer.removeValue(forKey: nextIndex)
            }
            currentAnimatedImageIndex = nextIndex
            currentFrame = bufferedImage
            if isCurrentImageHasContentsRect {
                if image.responds(to: #selector(LGAnimatedImage.animatedImageContentsRect(atIndex:))) {
                    currentContentsRect = image.animatedImageContentsRect!(atIndex: nextIndex)
                }
                setContentsRect(currentContentsRect, for: currentFrame)
            }
            nextIndex = (currentAnimatedImageIndex + 1) % totalFrameCount
            isBufferMiss = false
            if buffer.count == totalFrameCount {
                bufferIsFull = true
            }
        } else {
            isBufferMiss = true
        }
        lock.lg_unlock()
        
        if !isBufferMiss {
            layer.setNeedsDisplay()
        }
        
        if !bufferIsFull && requestQueue.operationCount == 0 {
            let operation = LGAnimatedImageViewFetchOperation()
            operation.imageView = self
            operation.nextIndex = nextIndex
            operation.currentImage = image
            requestQueue.addOperation(operation)
        }
    }
    
    @objc func didReceiveMemoryWarning(_ noti: Notification) {
        requestQueue.cancelAllOperations()
        requestQueue.addOperation { [weak self] in
            guard let weakSelf = self else {
                return
            }
            weakSelf.incrBufferCount = -60 - (Int)(arc4random() % 120)
            let next = (weakSelf.currentAnimatedImageIndex + 1) % weakSelf.totalFrameCount
            weakSelf.lock.lg_lock()
            let keys = weakSelf.buffer.keys
            for key in keys {
                if key != next {
                    _ = weakSelf.buffer.removeValue(forKey: key)
                }
            }
            weakSelf.lock.lg_unlock()
        }
    }
    
    @objc func didEnterBackground(_ noti: Notification) {
        requestQueue.cancelAllOperations()
        let next = (currentAnimatedImageIndex + 1) % totalFrameCount
        self.lock.lg_lock()
        let keys = buffer.keys
        for key in keys {
            if key != next {
                _ = buffer.removeValue(forKey: key)
            }
        }
        self.lock.lg_unlock()
    }
    
    override open func didMoveToWindow() {
        super.didMoveToWindow()
        didMoved()
    }
    
    override open func didMoveToSuperview() {
        super.didMoveToSuperview()
        didMoved()
    }
    
    func didMoved() {
        if isAutoPlayAnimatedImage {
            if self.superview != nil && self.window != nil {
                self.startAnimating()
            } else {
                self.stopAnimating()
            }
        }
    }
    
    override open func stopAnimating() {
        super.stopAnimating()
        requestQueue.cancelAllOperations()
        timer?.isPaused = true
        self.currentIsPlayingAnimation = false
    }
    
    override open func startAnimating() {
        let type = currentImageType()
        if type == LGAnimatedImageType.images || type == LGAnimatedImageType.highlightedImages {
            if let images = image(for: type) as? [UIImage] {
                if images.count > 0 {
                    super.startAnimating()
                    self.currentIsPlayingAnimation = true
                }
            }
        } else {
            if currentAnimatedImage != nil && timer?.isPaused == true {
                currentLoop = 0
                isLoopEnd = false
                timer?.isPaused = false
                self.currentIsPlayingAnimation = true
            }
        }
    }
    
    func setContentsRect(_ rect: CGRect, for image: UIImage?) {
        var layerRect = CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0)
        if image != nil {
            let imageSize = image!.size
            if imageSize.width > 0.01 && imageSize.height > 0.01 {
                layerRect.origin.x = rect.origin.x / imageSize.width
                layerRect.origin.y = rect.origin.y / imageSize.height
                layerRect.size.width = rect.size.width / imageSize.width
                layerRect.size.height = rect.size.height / imageSize.height
                layerRect = layerRect.intersection(CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0))
                if layerRect.isNull || layerRect.isEmpty {
                    layerRect = CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0)
                }
            }
        }
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.layer.contentsRect = layerRect
        CATransaction.commit()
    }

    override open func display(_ layer: CALayer) {
        if currentFrame != nil {
            layer.contents = currentFrame?.cgImage
        }
    }
    
    func setCurrentAnimatedImageIndex(_ index: Int) {
        if currentAnimatedImage == nil {
            return
        }
        if index >= currentAnimatedImage!.animatedImageFrameCount() {
            return
        }
        if index == currentAnimatedImageIndex {
            return
        }
        
        func featureFunction() {
            lock.lg_lock()
            requestQueue.cancelAllOperations()
            self.buffer.removeAll()
            currentFrame = currentAnimatedImage?.animatedImageFrame(atIndex: index)
            if isCurrentImageHasContentsRect {
                currentContentsRect = (currentAnimatedImage?.animatedImageContentsRect!(atIndex: index))!
            }
            time = 0
            isLoopEnd = false
            isBufferMiss = false
            layer.setNeedsDisplay()
            lock.lg_unlock()
        }
        
        if Thread.current.isMainThread {
            featureFunction()
        } else {
            DispatchQueue.main.async {
                featureFunction()
            }
        }
    }
}


class LGImageWeakTarget: NSObject {
    public weak var target: NSObjectProtocol?
    public init(target: NSObjectProtocol) {
        super.init()
        self.target = target
    }
    
    public override func responds(to aSelector: Selector!) -> Bool {
        return (target?.responds(to: aSelector) ?? false) || super.responds(to: aSelector)
    }
    
    public override func forwardingTarget(for aSelector: Selector!) -> Any? {
        return target
    }
}







