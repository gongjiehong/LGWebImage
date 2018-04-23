//
//  LGWebImageRemoteDownloadController.swift
//  LGWebImageDemo
//
//  Created by 龚杰洪 on 2018/4/18.
//  Copyright © 2018年 龚杰洪. All rights reserved.
//

import UIKit
import LGWebImage

class LGRemoteDownloadCell: UITableViewCell {
    var exampleImageView: LGAnimatedImageView!
    var progressView: UIProgressView!
    
    var imageURL: String? {
        didSet {
            if imageURL != nil {
                downloadImageAndShow()
            } else {
                
            }
        }
    }
    
    override init(style: UITableViewCellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        exampleImageView = LGAnimatedImageView(frame: self.contentView.bounds)
        exampleImageView.contentMode = UIViewContentMode.scaleAspectFit
        self.contentView.addSubview(exampleImageView)
        
        progressView = UIProgressView(frame: CGRect(x: 0, y: 0, width: self.contentView.bounds.width, height: 20))
        self.contentView.addSubview(progressView)
//        10.0,
//        corners: UIRectCorner.allCorners,
//        borderWidth: 2.0,
//        borderColor: UIColor.orange,
//        borderLineJoin: CGLineJoin.miter
        exampleImageView.lg_cornerRadius = LGCornerRadiusConfig(cornerRadius: 10.0,
                                                                corners: UIRectCorner.allCorners,
                                                                borderWidth: 2.0,
                                                                borderColor: UIColor.orange,
                                                                borderLineJoin: CGLineJoin.miter)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        
    }
    
    private var exampleImageViewSize: CGSize {
        return DispatchQueue.main.sync {
            return self.exampleImageView.bounds.size
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        progressView.frame = CGRect(x: 0, y: 0, width: self.contentView.bounds.width, height: 20)
        exampleImageView.frame = self.contentView.bounds
    }
    
    func downloadImageAndShow() {
        exampleImageView.lg_setImageWithURL(self.imageURL!,
                                            placeholder: UIImage(named: "avatar_default"),
                                            options: LGWebImageOptions.default,
                                            progressBlock:
            { (progress) in
                self.progressView.progress = Float(progress.fractionCompleted)
        }, transformBlock: {[weak self] (image, url) -> UIImage? in
//            if let tempImage = image as? LGImage {
//                if tempImage.animatedImageFrameCount() > 1 {
//                    return image
//                } else {
//                    guard let weakSelf = self else {
//                        return image
//                    }
//
//                    var result = tempImage.lg_imageByResizeToSize(weakSelf.exampleImageViewSize,
//                                                                  contentMode: UIViewContentMode.scaleAspectFill)
//                    result = result?.lg_imageByRoundCornerRadius(10.0,
//                                                                 corners: UIRectCorner.allCorners,
//                                                                 borderWidth: 2.0,
//                                                                 borderColor: UIColor.orange,
//                                                                 borderLineJoin: CGLineJoin.miter)
//                    return result
//                }
//            } else {
//                guard let weakSelf = self else {
//                    return image
//                }
//
//                var result = image?.lg_imageByResizeToSize(weakSelf.exampleImageViewSize,
//                                                           contentMode: UIViewContentMode.scaleAspectFill)
//                result = result?.lg_imageByRoundCornerRadius(10.0,
//                                                             corners: UIRectCorner.allCorners,
//                                                             borderWidth: 2.0,
//                                                             borderColor: UIColor.orange,
//                                                             borderLineJoin: CGLineJoin.miter)
//                return result
//            }
            return image
        }) { (resultImage, url, sourceType, imageStage, error) in
            
        }
        
    }
}


class LGWebImageRemoteDownloadController: UITableViewController {
    
    var dataArray: [String] = [String]()
    
    private let kLGRemoteDownloadCellReuse = "LGRemoteDownloadCell"
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false
        
        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem
        self.tableView.register(LGRemoteDownloadCell.classForCoder(),
                                forCellReuseIdentifier: kLGRemoteDownloadCellReuse)
        
        dataArray.append("http://staticfile.cxylg.com/%E6%97%A0%E7%A0%81%E5%A4%A7%E5%9B%BE.jpg")
        dataArray.append("https://s3-us-west-2.amazonaws.com/julyforcd/100/1510480450.jp2")
        dataArray.append("https://s3-us-west-2.amazonaws.com/julyforcd/100/1510480481.jpg")
        dataArray.append("https://s3-us-west-2.amazonaws.com/julyforcd/100/1518065289.tiff")
        dataArray.append("https://s3-us-west-2.amazonaws.com/julyforcd/100/5ad6b3c630e69.bmp")
        dataArray.append("https://s3-us-west-2.amazonaws.com/julyforcd/100/AnimatedPortableNetworkGraphics.png")
        dataArray.append("https://s3-us-west-2.amazonaws.com/julyforcd/100/C3ZwL.png")
        dataArray.append("https://s3-us-west-2.amazonaws.com/julyforcd/100/Pikachu.gif")
        dataArray.append("https://s3-us-west-2.amazonaws.com/julyforcd/100/animated.webp")
        dataArray.append("https://s3-us-west-2.amazonaws.com/julyforcd/100/bitbug_favicon.ico")
        dataArray.append("https://s3-us-west-2.amazonaws.com/julyforcd/100/google%402x.webp")
        dataArray.append("https://s3-us-west-2.amazonaws.com/julyforcd/100/lime-cat.JPEG")
        dataArray.append("https://s3-us-west-2.amazonaws.com/julyforcd/100/normal_png.png")
        dataArray.append("https://s3-us-west-2.amazonaws.com/julyforcd/100/static_gif.gif")
        dataArray.append("https://s3-us-west-2.amazonaws.com/julyforcd/100/twitter_fav_icon_300.png")
        
        // Only supports iOS11 and above
        dataArray.append("http://staticfile.cxylg.com/IMG_0392.heic")
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    // MARK: - Table view data source
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return dataArray.count
    }
    
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell: LGRemoteDownloadCell
        if let tempCell = tableView.dequeueReusableCell(withIdentifier: kLGRemoteDownloadCellReuse, for: indexPath) as? LGRemoteDownloadCell
        {
            cell = tempCell
        } else {
            cell = LGRemoteDownloadCell(style: UITableViewCellStyle.default, reuseIdentifier: kLGRemoteDownloadCellReuse)
        }
        cell.imageURL = dataArray[indexPath.row]
        return cell
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 300.0
    }
    
    /*
     // Override to support conditional editing of the table view.
     override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
     // Return false if you do not want the specified item to be editable.
     return true
     }
     */
    
    /*
     // Override to support editing the table view.
     override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
     if editingStyle == .delete {
     // Delete the row from the data source
     tableView.deleteRows(at: [indexPath], with: .fade)
     } else if editingStyle == .insert {
     // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
     }
     }
     */
    
    /*
     // Override to support rearranging the table view.
     override func tableView(_ tableView: UITableView, moveRowAt fromIndexPath: IndexPath, to: IndexPath) {
     
     }
     */
    
    /*
     // Override to support conditional rearranging of the table view.
     override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
     // Return false if you do not want the item to be re-orderable.
     return true
     }
     */
    
    /*
     // MARK: - Navigation
     
     // In a storyboard-based application, you will often want to do a little preparation before navigation
     override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
     // Get the new view controller using segue.destinationViewController.
     // Pass the selected object to the new view controller.
     }
     */
    
}
