//
//  ViewController.swift
//  MagPadV3
//
//  Created by Ding Xu on 3/4/15.
//  Copyright (c) 2015 Ding Xu. All rights reserved.
//

import UIKit
import CoreMotion

class ViewController: UIViewController, F53OSCClientDelegate, F53OSCPacketDestination {
    
    @IBOutlet var locLabel: UILabel!
    @IBOutlet var loadingIndicator: UIActivityIndicatorView!
    @IBOutlet var translateTxt: UILabel!
    @IBOutlet var translateBtn: UIButton!
    
    // OSC
    var oscClient:F53OSCClient = F53OSCClient()
    var oscServer:F53OSCServer = F53OSCServer()
    var reminderView: UIImageView!
    var reminderViewTimer: NSTimer!
    var reminderViewLabel: UILabel!
    
    // average filter
    let NumColumns = 6
    let NumMinAvgCols = 2
    let NumRows = 2
    var smoothBuf = Array<Array<Double>>()
    //var smoothBuf = [Double](count: 10, repeatedValue: 0.0)
    var smoothIdx: Int = 0
    var smoothCnt: Int = 0
    var smoothAvgRow:Double = 0.0
    var smoothAvgCol:Double = 0.0
    var smoothAvgRowPrev:Double = 0.0
    var smoothAvgColPrev:Double = 0.0
    //let smoothCntTotal:Int = 5
    //var smoothFlag:Bool = false
    var beginUpdate:Bool = true
    
    // Buffer
    var magBuf:DualArrayBuffer = DualArrayBuffer(bufSize: BUFFERSIZE)
    
    // megnetometer
    var motionManager: CMMotionManager = CMMotionManager()
    var magnetoTimer: NSTimer!
    
    // accerometer
    var acceCnt:UInt = 0
    var accePrev: Double = 0.0
    var acceCurr: Double = 0.0
    
    // webview
    var showToolBar:Bool = true
    
    // scroll view
    var imageView: UIImageView!
    var scrollView: UIScrollView!
    var croppedImgView: UIImageView!
    var labelBlockView: UIImageView!
    
    // translation
    var translator: Polyglot!
    var transRectStartX: CGFloat = 0.0
    var transRectStartY: CGFloat = 0.0
    var transRectSelectView: UIImageView!
    var transRectSelectLabel: UILabel!
    var transScreenTopLeftX: CGFloat! = 0
    var transScreenTopLeftY: CGFloat! = 0
    
    var debugCnt:UInt = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        stopLoadingIndicator()
        
        // init scrollView
        initScrollView()
        
        // init translator
        translator = Polyglot(clientId: "davidcroft_OCR", clientSecret: "6lF5EaKBjX/ZXkEZ5IE+imjbh5slYXSqiTErclaaec8=")
        translator.fromLanguage = Language.English
        translator.toLanguage = Language.ChineseSimplified
        
        // GUI
        labelBlockView = drawBackgroundBlock(translateTxt)
        labelBlockView.alpha = 0
        self.translateTxt.text = ""
        self.translateTxt.lineBreakMode = NSLineBreakMode.ByWordWrapping
        self.translateTxt.numberOfLines = 5
        self.translateTxt.textColor = UIColor.whiteColor()
        self.translateTxt.alpha = 0.0
        view.bringSubviewToFront(self.translateTxt)
        //fadeInLabel(self.translateTxt)
        
        translateBtn.backgroundColor = pinkColor
        translateBtn.setTitleColor(UIColor.whiteColor(), forState: UIControlState.Normal)
        view.bringSubviewToFront(self.translateBtn)
        
        // debug
        //let img = cropImageFromPoint(imageView.image!, topLeftX: 0.7, topLeftY: 0.8)
        //self.performOCR(img)
        //croppedImgView = UIImageView(image: img)
        //croppedImgView.bounds.size = view.bounds.size
        //view.addSubview(croppedImgView)
        //setScrollViewOffset(6, colVal: 0.2)
    }
    
    override func viewDidAppear(animated: Bool) {
        // set up a ip addr for OSC host
        let ipAddrAlert:UIAlertController = UIAlertController(title: nil, message: "Set up IP address for OSC", preferredStyle: .Alert)
        let cancelAction = UIAlertAction(title: "Cancel", style: .Cancel, handler: {
            action in
            exit(0)
        })
        let doneAction = UIAlertAction(title: "Done", style: .Default, handler: {
            action in
            // get user input first to update total page number
            let userText:UITextField = ipAddrAlert.textFields?.first as! UITextField
            sendHost = userText.text
            println("set IP addr for send host to \(userText.text)")
        })
        ipAddrAlert.addAction(cancelAction)
        ipAddrAlert.addAction(doneAction)
        ipAddrAlert.addTextFieldWithConfigurationHandler { (textField) -> Void in
            textField.placeholder = "type in IP address here"
        }
        self.presentViewController(ipAddrAlert, animated: true, completion: nil)
        
        // init magnetometer
        self.motionManager.startMagnetometerUpdates()
        self.motionManager.startGyroUpdates()
        self.magnetoTimer = NSTimer.scheduledTimerWithTimeInterval(0.01,
            target:self,
            selector:"updateMegneto:",
            userInfo:nil,
            repeats:true)
        println("Launched magnetometer")
        
        // osc init
        self.oscServer.delegate = self
        self.oscServer.port = recvPort
        self.oscServer.startListening()
        
        // label init
        self.locLabel.text = "Current Location: 0"
        
        // buffer init
        for column in 0...NumRows {
            smoothBuf.append(Array(count:NumColumns, repeatedValue:Double()))
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    
    // timer
    func updateMegneto(timer: NSTimer) -> Void {
        // TODO
        //println(self.magnetoTimer.timeInterval)
        if self.motionManager.magnetometerData != nil {
            let dataX = self.motionManager.magnetometerData.magneticField.x
            let dataY = self.motionManager.magnetometerData.magneticField.y
            let dataZ = self.motionManager.magnetometerData.magneticField.z
            
            // add to buffer
            if (magBuf.addDatatoBuffer(dataX, valY: dataY, valZ: dataZ)) {
                // buffer is full, send OSC data to laptop
                self.sendOSCData()
            }
            
            // accerometer
            if (acceCnt >= 50) {
                acceCnt = 0;
                let dataAccX = self.motionManager.gyroData.rotationRate.x
                let dataAccY = self.motionManager.gyroData.rotationRate.y
                let dataAccZ = self.motionManager.gyroData.rotationRate.z
                accePrev = acceCurr
                acceCurr = sqrt(dataAccX*dataAccX + dataAccY*dataAccY + dataAccZ*dataAccZ)
                let delta:Double = abs(acceCurr-accePrev)
                if (delta > 0.2) {
                    smoothCnt = NumColumns
                } else if (delta > 0.02) {
                    let temp = (Double)(NumColumns-NumMinAvgCols)*(delta-0.02)/(0.2-0.02)
                    smoothCnt = Int(temp) + NumMinAvgCols
                } else {
                    smoothCnt = NumMinAvgCols
                }
                //println("UPDATE: delta: \(acceCurr-accePrev), smoothCnt = \(smoothCnt)")
            } else {
                acceCnt += 1
            }
        }
    }
    
    func sendOSCData() -> Void {
        // create a new thread to send buffer data
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), { () -> Void in
            // send osc message
            var str:String = self.magBuf.generateStringForOSC()
            let message:F53OSCMessage = F53OSCMessage(string: "/magneto \(str)")
            self.oscClient.sendPacket(message, toHost: sendHost, onPort: sendPort)
            //println("send OSC message")
        })
    }
    
    
    // OSC
    func takeMessage(message: F53OSCMessage) -> Void {
        // make sure to stop updating if user is trying to select an area for translation
        if (!self.beginUpdate) {
            return
        }
        
        // create a new thread to get URL from parse and set webview
        //println("receive OSC message")
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), { () -> Void in
            var locRow:Double = message.arguments.first as! Double
            var locCol:Double = message.arguments.last as! Double
            
            // offset
            //locRow = locRow + 1
            locCol = locCol + 0.75
            
            self.getSmoothResult(locRow, valCol: locCol)

            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                self.locLabel.text = "Current Location: \(locRow), \(locCol)"
            })
            //println("new location: \(locRow), \(locCol)")
            
            // setScrollViewOffset
            let deltaRow = (self.smoothAvgRow - self.smoothAvgRowPrev) * (self.smoothAvgRow - self.smoothAvgRowPrev)
            let deltaCol = (self.smoothAvgCol - self.smoothAvgColPrev) * (self.smoothAvgCol - self.smoothAvgColPrev)
            if (sqrt(deltaRow + deltaCol) > 0.1) {
                self.setScrollViewOffset(self.smoothAvgRow, colVal: self.smoothAvgCol)
                println("move to offset: \(self.smoothAvgRow), \(self.smoothAvgCol)")
                //self.setScrollViewOffset(locRow, colVal: locCol)
            }
        })
    }
    
    /////////////////////////////
    func getSmoothResult(valRow:Double, valCol:Double) -> Void {
        /*smoothAvgRow = (smoothAvgRow * Double(smoothCnt) + valRow) / Double(smoothCnt+1)
        smoothAvgCol = (smoothAvgCol * Double(smoothCnt) + valCol) / Double(smoothCnt+1)
        if (smoothCnt < smoothCntTotal) {
            smoothCnt = smoothCnt+1
        }
        //println("smoothAvgRow = \(smoothAvgRow), smoothAvgCol = \(smoothAvgCol)")*/
        
        // push to buf first
        smoothBuf[0][smoothIdx] = valRow
        smoothBuf[1][smoothIdx++] = valCol
        if (smoothIdx >= NumColumns) {
            smoothIdx = 0
        }
        
        // compute smoothAveRow and smoothAveCol based on smoothCnt (decided by accerometer data)
        smoothAvgRowPrev = smoothAvgRow
        smoothAvgColPrev = smoothAvgCol
        smoothAvgRow = 0
        smoothAvgCol = 0
        var tempIdx = smoothIdx-1
        var count = smoothCnt
        for var i = 0; i < count; i++ {
            if (tempIdx < 0) {
                tempIdx += NumColumns
            }
            smoothAvgRow += smoothBuf[0][tempIdx]
            smoothAvgCol += smoothBuf[1][tempIdx--]
        }
        smoothAvgRow = smoothAvgRow/Double(count)
        smoothAvgCol = smoothAvgCol/Double(count)
        //println("smoothAvgRow = \(smoothAvgRow), smoothAvgCol = \(smoothAvgCol), SmoothWindow = \(count)")
    }
    /////////////////////////////
    
    func startLoadingIndicator() {
        // start loading indicator
        dispatch_async(dispatch_get_main_queue(), { () -> Void in
            self.loadingIndicator.hidden = false
            self.loadingIndicator.color = UIColor.whiteColor()
            self.view.bringSubviewToFront(self.loadingIndicator)
            self.loadingIndicator.startAnimating()
        })
    }
    
    func stopLoadingIndicator() {
        // hide loading indicator
        dispatch_async(dispatch_get_main_queue(), { () -> Void in
            self.loadingIndicator.stopAnimating()
            self.loadingIndicator.hidden = true
        })
    }
    
    // init scrollview
    func initScrollView() {
        // add scrollView
        //imageView = UIImageView(image: UIImage(named: "file.jpg"))
        imageView = UIImageView(image: scaleImage(UIImage(named: "file.jpg")!, maxDimension: 1650))
        scrollView = UIScrollView(frame: view.bounds)
        scrollView.backgroundColor = UIColor.blackColor()
        //scrollView.contentSize = imageView.bounds.size
        scrollView.contentSize = view.bounds.size
        scrollView.addSubview(imageView)
        view.addSubview(scrollView)
        
        // enable tap gesture
        var tapRecognizer = UITapGestureRecognizer(target: self, action: "scrollViewTapped:")
        tapRecognizer.numberOfTapsRequired = 1
        //tapRecognizer.numberOfTouchesRequired = 1
        scrollView.addGestureRecognizer(tapRecognizer)
        
        var doubleTapRecognizer = UITapGestureRecognizer(target: self, action: "scrollViewDoubleTapped:")
        doubleTapRecognizer.numberOfTapsRequired = 2
        //doubleTapRecognizer.numberOfTouchesRequired = 2
        scrollView.addGestureRecognizer(doubleTapRecognizer)
        
        tapRecognizer.requireGestureRecognizerToFail(doubleTapRecognizer)
        
        var panRecognizer = UIPanGestureRecognizer(target: self, action: "scrollViewPanned:")
        scrollView.addGestureRecognizer(panRecognizer)
    }
    
    func setScrollViewOffset(rowVal:Double, colVal:Double) {
        let height = Double(imageView.bounds.height)
        let width = Double(imageView.bounds.width)
        let xVal:Double = (colVal / pdfWidth) * width
        let yVal:Double = (rowVal / pdfHeight) * height
        if (xVal > 0 && xVal < width && yVal > 0 && yVal < height) {
            
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                UIView.animateWithDuration(1.2, delay: 0, options: UIViewAnimationOptions.AllowUserInteraction, animations: { () -> Void in
                    self.scrollView.contentOffset = CGPointMake(CGFloat(xVal), CGFloat(yVal))
                    }, completion: nil)
                /*UIView.animateWithDuration(1.2, animations: { () -> Void in
                self.scrollView.contentOffset = CGPointMake(CGFloat(xVal), CGFloat(yVal))
                })*/
            })
        }
        
        // storage offset
        self.transScreenTopLeftX = CGFloat(xVal)
        self.transScreenTopLeftY = CGFloat(yVal)
    }
    
    func scrollViewTapped(recognizer: UITapGestureRecognizer) {
        
        println("single tapped")
        
        // clear selection rect if there exists one
        clearTransSelection()
        
        if (self.translateTxt.alpha == 1) {
            fadeOutLabel(self.translateTxt)
        } else {
            fadeInLabel(self.translateTxt)
        }
        
        /*if (self.beginUpdate) {
            self.beginUpdate = false
        } else {
            self.beginUpdate = true
        }*/
    }
    
    func scrollViewDoubleTapped(recognizer: UITapGestureRecognizer) {
        
        println("double tapped")
        
        clearTransSelection()
        
        if (self.beginUpdate) {
            // disable updating
            self.beginUpdate = false
            
            let size = UIScreen.mainScreen().bounds.height/2
            let startX = UIScreen.mainScreen().bounds.width/2-size/2
            let startY = UIScreen.mainScreen().bounds.height/2-size/2
            let labelRect = CGRectMake(startX, startY, size, size)
            let labelCenter = CGPointMake(UIScreen.mainScreen().bounds.width/2, UIScreen.mainScreen().bounds.height/2)
            drawCustomizedLabel(labelRect, center: labelCenter, str: "Stop Updating", bkColor: transparentGrayColor, duration: NSTimeInterval(0.5))
        } else {
            // continue updating
            self.beginUpdate = true
            
            let size = UIScreen.mainScreen().bounds.height/2
            let startX = UIScreen.mainScreen().bounds.width/2-size/2
            let startY = UIScreen.mainScreen().bounds.height/2-size/2
            let labelRect = CGRectMake(startX, startY, size, size)
            let labelCenter = CGPointMake(UIScreen.mainScreen().bounds.width/2, UIScreen.mainScreen().bounds.height/2)
            drawCustomizedLabel(labelRect, center: labelCenter, str: "Start Updating", bkColor: transparentPinkColor, duration: NSTimeInterval(0.5))
        }
    }
    
    func dismissReminderViewTimer(timer:NSTimer) {
        if (self.transRectSelectLabel != nil && self.transRectSelectLabel.isDescendantOfView(self.view)) {
            self.transRectSelectLabel.removeFromSuperview()
        }
    }
    
    ////////////////////////////
    // word selection
    func scrollViewPanned(recognizer: UIPanGestureRecognizer) {
        let x = recognizer.locationInView(imageView).x
        let y = recognizer.locationInView(imageView).y
        
        let width = abs(x-transRectStartX)
        let height = abs(y-transRectStartY)
        
        var startX = min(x, transRectStartX)
        var startY = min(y, transRectStartY)
        if (recognizer.state == UIGestureRecognizerState.Began) {
            
            println("STATE BEGIN: (\(x), \(y))")
            // stop offset updating
            self.beginUpdate = false
            println("set beginUpdate to false")
            
            //self.oscServer.stopListening()
            // storage start position
            transRectStartX = x;
            transRectStartY = y;
            // clear translate label if there exists one
            if (self.transRectSelectLabel != nil && self.transRectSelectLabel.isDescendantOfView(self.view)) {
                self.transRectSelectLabel.removeFromSuperview()
            }
            
        } else if (recognizer.state == UIGestureRecognizerState.Changed) {
            
            // draw rectangle from start position
            let transRectEndX = x;
            let transRectEndY = y;
            println("startX = \(startX), startY = \(startY)")
            drawPanSelectionRect(startX-self.scrollView.contentOffset.x, startY: startY-self.scrollView.contentOffset.y, width: width, height: height)
            
        } else if (recognizer.state == UIGestureRecognizerState.Ended) {
            
            println("STATE END: (\(x), \(y))")
            let transRectEndX = x;
            let transRectEndY = y;
            drawPanSelectionRect(startX-self.scrollView.contentOffset.x, startY: startY-self.scrollView.contentOffset.y, width: width, height: height)
            
            /////////////////////////////////////
            // OCR + translation
            if (width > 40 && height > 20) {
                // crop image for translation
                let img = cropImageRect(imageView.image!, topLeftX: startX, topLeftY: startY, width: width, height: height)
                
                // draw translate label
                // notice crop and display rect is not from the same postion, since there is an offset for scrollview, so update startX and startY here
                startX = startX - self.scrollView.contentOffset.x
                startY = startY - self.scrollView.contentOffset.y
                let labelRect = CGRectMake(startX, startY, width, height)
                
                // compare to transScreenTopLeftX and transScreenTopLeftY to decide the position of rect
                let screenHeight = UIScreen.mainScreen().bounds.height
                if (height < screenHeight/3) {
                    if (startY + height/2 < transScreenTopLeftY + screenHeight/2) {
                        let labelCenter = CGPointMake(startX+width/2, startY+height+height/2+5)
                        drawTranslateLabel(labelRect, center: labelCenter, str: "Translating ...")
                        self.performOCR(img, disLabel: self.transRectSelectLabel)
                    } else if (startY + height/2 >= transScreenTopLeftY + screenHeight/2) {
                        let labelCenter = CGPointMake(startX+width/2, startY-height/2-5)
                        drawTranslateLabel(labelRect, center: labelCenter, str: "Translating ...")
                        self.performOCR(img, disLabel: self.transRectSelectLabel)
                    }
                } else {
                    // selection area is too big, use botton section
                    self.translateTxt.textAlignment = .Center
                    self.translateTxt.text = "Text Recognition ..."
                    self.performOCR(img, disLabel: self.translateTxt)
                    fadeInLabel(self.translateTxt)
                }
            } else {
                // rect area is too small, cancel rect
                clearTransSelection()
            }
            /////////////////////////////////////
            
            // restore position updating
            //self.beginUpdate = true
            
        }
    }
    
    
    // draw rectangle for pan selection area
    func drawPanSelectionRect(startX: CGFloat, startY: CGFloat, width: CGFloat, height: CGFloat) {
        if (self.transRectSelectView != nil && self.transRectSelectView.isDescendantOfView(self.view)) {
            //println("yes")
            self.transRectSelectView.removeFromSuperview()
        }
        // draw a rectangle
        let imageSize = CGSize(width: width, height: height)
        transRectSelectView = UIImageView(frame: CGRect(origin: CGPoint(x: startX, y: startY), size: imageSize))
        transRectSelectView.image = drawCustomImage(imageSize, color: yellowColor)
        //transRectSelectView.alpha = 0.8
        self.view.addSubview(transRectSelectView)
    }
    
    func drawTranslateLabel(rect: CGRect, center: CGPoint, str: String) {
        if (self.transRectSelectLabel != nil && self.transRectSelectLabel.isDescendantOfView(self.view)) {
            self.transRectSelectLabel.removeFromSuperview()
        }
        // draw a rect
        self.transRectSelectLabel = UILabel(frame: rect)
        self.transRectSelectLabel.backgroundColor = UIColor.grayColor()
        self.transRectSelectLabel.textColor = UIColor.whiteColor()
        self.transRectSelectLabel.font = self.transRectSelectLabel.font.fontWithSize(14)
        self.transRectSelectLabel.center = center
        self.transRectSelectLabel.textAlignment = NSTextAlignment.Center
        self.transRectSelectLabel.text = str
        self.transRectSelectLabel.lineBreakMode = NSLineBreakMode.ByWordWrapping
        self.transRectSelectLabel.numberOfLines = 5
        // set label corner to round
        self.transRectSelectLabel.layer.cornerRadius = 8
        self.transRectSelectLabel.layer.borderWidth = 0
        self.transRectSelectLabel.layer.masksToBounds = true
        self.view.addSubview(self.transRectSelectLabel)
    }
    
    func drawCustomizedLabel(rect: CGRect, center: CGPoint, str: String, bkColor: UIColor, duration: NSTimeInterval) {
        if (self.reminderViewLabel != nil && self.reminderViewLabel.isDescendantOfView(self.view)) {
            self.reminderViewLabel.removeFromSuperview()
        }
        // draw a rect
        self.reminderViewLabel = UILabel(frame: rect)
        self.reminderViewLabel.backgroundColor = bkColor
        self.reminderViewLabel.textColor = UIColor.whiteColor()
        self.reminderViewLabel.alpha = 0
        self.reminderViewLabel.font = self.reminderViewLabel.font.fontWithSize(18)
        self.reminderViewLabel.center = center
        self.reminderViewLabel.textAlignment = NSTextAlignment.Center
        self.reminderViewLabel.text = str
        // set label corner to round
        self.reminderViewLabel.layer.cornerRadius = 12
        self.reminderViewLabel.layer.borderWidth = 0
        self.reminderViewLabel.layer.masksToBounds = true
        self.view.addSubview(self.reminderViewLabel)
        // display
        UIView.animateWithDuration(duration, delay: 0, options: nil, animations: { () -> Void in
            self.reminderViewLabel.alpha = 1
        }) { (finished) -> Void in
            UIView.animateWithDuration(duration, delay: 0.6, usingSpringWithDamping: 0.9, initialSpringVelocity: 0.0, options: nil, animations: {
                self.reminderViewLabel.alpha = 0
            }, completion: { (finished) -> Void in
                if (self.reminderViewLabel != nil && self.reminderViewLabel.isDescendantOfView(self.view)) {
                    self.reminderViewLabel.removeFromSuperview()
                }
            })
        }
        
    }
    
    func clearTransSelection() {
        if (self.transRectSelectView != nil && self.transRectSelectView.isDescendantOfView(self.view)) {
            //println("yes")
            self.transRectSelectView.removeFromSuperview()
        }
        // clear translate label if there exists one
        if (self.transRectSelectLabel != nil && self.transRectSelectLabel.isDescendantOfView(self.view)) {
            self.transRectSelectLabel.removeFromSuperview()
        }
    }
    
    ////////////////////////////////////
    // Image crop
    // topLeftX and topLeftY are both inch in size
    func cropImageFromPoint(image: UIImage, topLeftX: CGFloat, topLeftY: CGFloat) -> UIImage {
        
        var height = CGFloat(image.size.height)
        var width = CGFloat(image.size.width)
        
        let imgWidth = (3.5 / CGFloat(pdfWidth)) * width
        let imgHeight = (1.8 / CGFloat(pdfHeight)) * height
        let imgCol = (topLeftX / CGFloat(pdfWidth)) * width
        let imgRow = (topLeftY / CGFloat(pdfHeight)) * height
        
        println("image width = \(width), image height = \(height)")
        println("cropped image width = \(imgWidth), cropped image height = \(imgHeight)")
        
        let croprect:CGRect = CGRectMake(imgCol, imgRow, imgWidth, imgHeight)
        // Draw new image in current graphics context
        var imageRef = CGImageCreateWithImageInRect(image.CGImage, croprect)
        // Create new cropped UIImage
        let croppedImage:UIImage! = UIImage(CGImage: imageRef)

        return croppedImage
    }
    
    // topLeftX and topLeftY are both pixel in imageview
    func cropImageRect(image: UIImage, topLeftX: CGFloat, topLeftY: CGFloat, width: CGFloat, height: CGFloat) -> UIImage {
        let croprect:CGRect = CGRectMake(topLeftX, topLeftY, width, height)
        // Draw new image in current graphics context
        var imageRef = CGImageCreateWithImageInRect(image.CGImage, croprect)
        // Create new cropped UIImage
        let croppedImage:UIImage! = UIImage(CGImage: imageRef)
        return croppedImage
    }
    
    func scaleImage(image: UIImage, maxDimension: CGFloat) -> UIImage {
        
        var scaledSize = CGSize(width: maxDimension, height: maxDimension)
        var scaleFactor: CGFloat
        
        if image.size.width > image.size.height {
            scaleFactor = image.size.height / image.size.width
            scaledSize.width = maxDimension
            scaledSize.height = scaledSize.width * scaleFactor
        } else {
            scaleFactor = image.size.width / image.size.height
            scaledSize.height = maxDimension
            scaledSize.width = scaledSize.height * scaleFactor
        }
        
        UIGraphicsBeginImageContext(scaledSize)
        image.drawInRect(CGRectMake(0, 0, scaledSize.width, scaledSize.height))
        let scaledImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return scaledImage
    }
    
    func performOCR(image: UIImage, disLabel: UILabel) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), { () -> Void in
            let scaledImage = self.scaleImage(image, maxDimension: OCRMAXDIMENSION)
            if (disLabel == self.translateTxt) {
                // set loading indicator only for translateTxt
                self.startLoadingIndicator()
            }
            println("Texts Recognition ...")
            self.performImageRecognition(scaledImage, disLabel: disLabel)
        })
    }
    
    func performImageRecognition(image: UIImage, disLabel: UILabel) {
        // 1
        let tesseract = G8Tesseract()
        // 2
        tesseract.language = "eng"
        // 3
        tesseract.engineMode = .TesseractOnly
        //tesseract.engineMode = .TesseractCubeCombined
        // 4
        tesseract.pageSegmentationMode = .Auto
        // 5
        tesseract.maximumRecognitionTime = 20.0
        // 6
        tesseract.image = image.g8_blackAndWhite()
        tesseract.recognize()
        // 7 perform online translation
        if (disLabel == self.translateTxt) {
            dispatch_async(dispatch_get_main_queue(), {
                disLabel.text = "Text Translating ..."
                println("Translation ...")
            })
        }
        println(tesseract.recognizedText)
        UIApplication.sharedApplication().networkActivityIndicatorVisible = true
        self.translator!.translate(tesseract.recognizedText) { translation in
            dispatch_async(dispatch_get_main_queue(), {
                println(translation)
                if (disLabel == self.translateTxt) {
                    // if label is self.translateTxt, center alignment
                    disLabel.textAlignment = .Left
                }
                disLabel.text = translation.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
                // 8
                self.stopLoadingIndicator()
                NSLog("MS Translation")
                UIApplication.sharedApplication().networkActivityIndicatorVisible = false
            })
        }
    }
    
    func fadeInLabel(label: UILabel!) {
        if (label.alpha == 1) {
            return
        }
        UIView.animateWithDuration(1, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0.0, options: nil, animations: {
            //self.translateTxt.center = CGPoint(x: self.view.center.x, y: self.view.center.y*3/4)
            self.translateTxt.alpha = 1.0
            let str = self.translateTxt.text as String!
            self.labelBlockView.alpha = 0.95
        }, completion: nil)
    }
    
    func fadeOutLabel(label: UILabel!) {
        if (label.alpha == 0) {
            return
        }
        UIView.animateWithDuration(1, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0.0, options: nil, animations: {
            //self.translateTxt.center = CGPoint(x: self.view.center.x, y: self.view.center.y*3/4)
            self.translateTxt.alpha = 0.0
            self.labelBlockView.alpha = 0.0
            }, completion: nil)
    }
    
    func drawBackgroundBlock(label: UILabel) -> UIImageView {
        let screenSize: CGRect = UIScreen.mainScreen().bounds
        let imageSize = CGSize(width: screenSize.width, height: label.bounds.height+20)
        let blockView = UIImageView(frame: CGRect(origin: CGPoint(x: 0, y: label.center.y-label.bounds.height/2-5), size: imageSize))
        self.view.addSubview(blockView)
        let image = drawCustomImage(imageSize, color: blueColor)
        blockView.image = image
        blockView.alpha = 0.92
        view.bringSubviewToFront(blockView)
        return blockView
    }
    
    func drawCustomImage(size: CGSize, color:UIColor) -> UIImage? {
        //println("drawCustomImg: \(size.width), \(size.height)")
        if (size.width <= 0 || size.height <= 0) {
            return nil
        }
        // Setup our context
        let bounds = CGRect(origin: CGPoint.zeroPoint, size: size)
        let opaque = false
        let scale: CGFloat = 0
        UIGraphicsBeginImageContextWithOptions(size, opaque, scale)
        let context = UIGraphicsGetCurrentContext()
        
        // Setup complete, do drawing here
        //CGContextSetStrokeColorWithColor(context, UIColor.redColor().CGColor)
        
        CGContextSetFillColorWithColor(context, color.CGColor)
        CGContextSetLineWidth(context, 0.0)
        //CGContextStrokeRect(context, bounds)
        CGContextFillRect(context, bounds)
        
        // Drawing complete, retrieve the finished image and cleanup
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }
    
    @IBAction func translateBtn(sender: AnyObject) {
        self.translateTxt.textAlignment = .Center
        self.translateTxt.text = "Text Recognition ..."
        let img = cropImageFromPoint(imageView.image!, topLeftX: CGFloat(self.smoothAvgCol), topLeftY: CGFloat(self.smoothAvgRow))
        self.performOCR(img, disLabel: self.translateTxt)
        fadeInLabel(self.translateTxt)
    }
}
