//
//  LGWebImageDisplayController.swift
//  LGWebImageDemo
//
//  Created by 龚杰洪 on 2018/4/18.
//  Copyright © 2018年 龚杰洪. All rights reserved.
//

import UIKit
import LGWebImage

class LGWebImageDisplayController: UIViewController {

    @IBOutlet weak var contentView: UIScrollView!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        
        DispatchQueue.utility.async(flags: DispatchWorkItemFlags.barrier) {
            self.addImage(with: "lime-cat", text: "JPEG格式显示")
            self.addImage(with: "1510480481", text: "JPG格式显示")
            self.addImage(with: "1510480450", text: "JPG2000格式显示")
            
            self.addImage(with: "static_gif", text: "静态GIF显示")
            self.addImage(with: "Pikachu", text: "动态GIF显示")
            
            self.addImage(with: "normal_png", text: "静态PNG显示")
            self.addImage(with: "AnimatedPortableNetworkGraphics", text: "动态APNG显示")
            
            self.addImage(with: "5ad6b3c630e69", text: "BMP格式显示")
            self.addImage(with: "bitbug_favicon", text: "ICO格式显示")
            self.addImage(with: "1518065289", text: "TIFF格式显示")
            
            self.addImage(with: "google", text: "静态WEBP显示")
            self.addImage(with: "animated", text: "动态WEBP显示")
            
            self.addImage(with: "IMG_0392", text: "静态HEIC显示")
            
            self.addSpriteSheetImage(withText: "精灵动画骷髅",
                                     imageName: "C3ZwL",
                                     verticalCount: 4,
                                     horizontallyCount: 9)
            self.addSpriteSheetImage(withText: "精灵动画点赞",
                                     imageName: "twitter_fav_icon_300",
                                     verticalCount: 4,
                                     horizontallyCount: 8)
            
            self.addFrameImags(withText: "拼接帧动画")
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    func addFrameImags(withText text: String) {
        var imagePaths: [String] = [String]()
        for index in 1...12 {
            let path = Bundle.main.bundlePath + "/running_\(index).jpg"
            imagePaths.append(path)
        }
        do {
            let frameImage = try LGFrameImage.imageWith(imagePaths: imagePaths, oneFrameDuration: 1 / 30.0, loopCount: 0)
            DispatchQueue.main.async {
                self.add(image: frameImage, text: text)
            }
        } catch {
            print(error)
        }
    }
    
    func addSpriteSheetImage(withText text: String, imageName: String, verticalCount: Int, horizontallyCount: Int) {
        guard let sheetImage = UIImage(named: imageName) else {
            return
        }
        
        var contentRects: [CGRect] = [CGRect]()
        var durations: [TimeInterval] = [TimeInterval]()
        
        let itemSize = CGSize(width: sheetImage.size.width / CGFloat(horizontallyCount),
                              height: sheetImage.size.height / CGFloat(verticalCount))
        for verticalIndex in 0..<verticalCount {
            for horizontallyIndex in 0..<horizontallyCount {
                var rect = CGRect.zero
                rect.size = itemSize
                rect.origin.x = sheetImage.size.width / CGFloat(horizontallyCount) * CGFloat(horizontallyIndex)
                rect.origin.y = sheetImage.size.height / CGFloat(verticalCount) * CGFloat(verticalIndex)
                contentRects.append(rect)
                durations.append(1.0 / 60.0)
            }
        }
        
        do {
            let sprite = try LGSpriteSheetImage.imageWith(spriteSheetImage: sheetImage,
                                                          contentRects: contentRects,
                                                          frameDurations: durations,
                                                          loopCount: 0)
            DispatchQueue.main.async {
                self.add(image: sprite, text: text, size: itemSize)
            }
        } catch {
            print(error)
        }
        
    }

    func addImage(with imageName: String, text: String) {
        let image = LGImage.imageWith(named: imageName)
        if image != nil {
            DispatchQueue.main.async {
                self.add(image: image!, text: text)
            }
        } else {
            print("Load image from imagename failed: \(text)")
        }
    }
    
    func add(image: UIImage, text: String, size: CGSize = CGSize.zero) {
        var newSize = (size == CGSize.zero ? image.size : size)
        if newSize.width > self.view.bounds.size.width {
            newSize.width = self.view.bounds.size.width
            newSize.height = newSize.height / (image.size.width / self.view.bounds.size.width)
        } else {
            
        }
        print("正常显示: \(text)")
        
        let originX = (self.view.bounds.size.width - newSize.width) / 2
        var originY: CGFloat = 20.0
        if self.contentView.subviews.count > 0 {
            originY = contentView.subviews.last!.frame.origin.y + contentView.subviews.last!.frame.height
        }
        
        let label = UILabel(frame: CGRect(x: 0, y: originY, width: self.view.bounds.width, height: 30.0))
        label.text = text
        label.textAlignment = NSTextAlignment.center
        contentView.addSubview(label)
        
        let imageView = LGAnimatedImageView(image: image)
        imageView.contentMode = UIView.ContentMode.scaleAspectFit
        imageView.frame = CGRect(x: originX, y: originY + 30.0, width: newSize.width, height: newSize.height)
        contentView.addSubview(imageView)
        
        contentView.contentSize = CGSize(width: self.view.bounds.width, height: originY + 30.0 + newSize.height)
    }

}
