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
            let userText:UITextField = ipAddrAlert.textFields?.first as UITextField
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
        // create a new thread to get URL from parse and set webview
        //println("receive OSC message")
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), { () -> Void in
            var locRow:Double = message.arguments.first as Double
            var locCol:Double = message.arguments.last as Double
            
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
        imageView = UIImageView(image: UIImage(named: "file.jpg"))
        //imageView = UIImageView(image: scaleImage(UIImage(named: "file.jpg")!, maxDimension: 1650))
        scrollView = UIScrollView(frame: view.bounds)
        scrollView.backgroundColor = UIColor.blackColor()
        //scrollView.contentSize = imageView.bounds.size
        scrollView.contentSize = view.bounds.size
        scrollView.addSubview(imageView)
        view.addSubview(scrollView)
        
        // enable tap gesture
        var tapRecognizer = UITapGestureRecognizer(target: self, action: "scrollViewTapped:")
        tapRecognizer.numberOfTapsRequired = 1
        tapRecognizer.numberOfTouchesRequired = 1
        scrollView.addGestureRecognizer(tapRecognizer)
    }
    
    func setScrollViewOffset(rowVal:Double, colVal:Double) {
        let height = Double(imageView.bounds.height)
        let width = Double(imageView.bounds.width)
        let xVal:Double = (colVal / pdfWidth) * width
        let yVal:Double = (rowVal / pdfHeight) * height
        if (xVal > 0 && xVal < width && yVal > 0 && yVal < height) {
            scrollView.setContentOffset(CGPoint(x: xVal, y: yVal), animated: true)
        }
    }
    
    func scrollViewTapped(recognizer: UITapGestureRecognizer) {
        
        /*let pointInView = recognizer.locationInView(imageView)
        //println("tap location: x \(pointInView.x)  y \(pointInView.y)")
        // convert x, y into inches
        let colInch = (Double(pointInView.x) / Double(imageView.bounds.width)) * pdfWidth
        let rowInch = (Double(pointInView.y) / Double(imageView.bounds.height)) * pdfHeight
        println("tap location: row \(rowInch)'' col \(colInch)''")
        
        // mapping row and col
        println("mapping pdf Index: \(colInch), \(rowInch)")*/
        
        if (self.translateTxt.alpha == 1) {
            fadeOutLabel(self.translateTxt)
        } else {
            fadeInLabel(self.translateTxt)
        }
    }
    
    
    ////////////////////////////////////
    // Image crop
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
    
    func performOCR(image: UIImage) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), { () -> Void in
            let scaledImage = self.scaleImage(image, maxDimension: OCRMAXDIMENSION)
            self.startLoadingIndicator()
            println("Texts Recognition ...")
            self.performImageRecognition(scaledImage)
        })
    }
    
    func performImageRecognition(image: UIImage) {
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
        dispatch_async(dispatch_get_main_queue(), {
            self.translateTxt.text = "Text Translation ..."
            println("Translation ...")
        })
        println(tesseract.recognizedText)
        UIApplication.sharedApplication().networkActivityIndicatorVisible = true
        self.translator!.translate(tesseract.recognizedText) { translation in
            dispatch_async(dispatch_get_main_queue(), {
                println(translation)
                self.translateTxt.textAlignment = .Left
                self.translateTxt.text = translation
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
        let image = drawCustomImage(imageSize)
        blockView.image = image
        blockView.alpha = 0.92
        view.bringSubviewToFront(blockView)
        return blockView
    }
    
    func drawCustomImage(size: CGSize) -> UIImage {
        // Setup our context
        let bounds = CGRect(origin: CGPoint.zeroPoint, size: size)
        let opaque = false
        let scale: CGFloat = 0
        UIGraphicsBeginImageContextWithOptions(size, opaque, scale)
        let context = UIGraphicsGetCurrentContext()
        
        // Setup complete, do drawing here
        //CGContextSetStrokeColorWithColor(context, UIColor.redColor().CGColor)
        CGContextSetFillColorWithColor(context, blueColor.CGColor)
        CGContextSetLineWidth(context, 0.0)
        
        //CGContextStrokeRect(context, bounds)
        CGContextFillRect(context, bounds)
        
        /*CGContextBeginPath(context)
        CGContextMoveToPoint(context, CGRectGetMinX(bounds), CGRectGetMinY(bounds))
        CGContextAddLineToPoint(context, CGRectGetMaxX(bounds), CGRectGetMaxY(bounds))
        CGContextMoveToPoint(context, CGRectGetMaxX(bounds), CGRectGetMinY(bounds))
        CGContextAddLineToPoint(context, CGRectGetMinX(bounds), CGRectGetMaxY(bounds))
        CGContextStrokePath(context)*/
        
        // Drawing complete, retrieve the finished image and cleanup
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }
    
    @IBAction func translateBtn(sender: AnyObject) {
        self.translateTxt.textAlignment = .Center
        self.translateTxt.text = "Text Recognition ..."
        let img = cropImageFromPoint(imageView.image!, topLeftX: CGFloat(self.smoothAvgCol), topLeftY: CGFloat(self.smoothAvgRow))
        self.performOCR(img)
        fadeInLabel(self.translateTxt)
    }
}
