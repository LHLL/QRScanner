//
//  QRScanner.swift
//  QRScanner
//
//  Created by 李玲 on 4/17/17.
//  Copyright © 2017 Jay. All rights reserved.
//

import Foundation
import AVFoundation
import QuartzCore
import ImageIO
import CoreMedia
import GLKit

public class QRScanner:NSObject {
    
    fileprivate let session = AVCaptureSession()
    fileprivate let imageOut = AVCaptureVideoDataOutput()
    fileprivate var cameraLayer:AVCaptureVideoPreviewLayer!
    fileprivate var coreImageContext = CIContext()
    fileprivate var renderBuffer:GLuint = 0
    fileprivate let context = EAGLContext(api: EAGLRenderingAPI(rawValue:2)!)
    fileprivate let view:UIView
    fileprivate let size:CGSize
    public weak var cameraDelegate:QRScannerDelegate?
    
    public init(_ view:UIView, imageViewSize:CGSize){
        self.view = view
        self.size = imageViewSize
        super.init()
        let glkView = GLKView(frame: view.frame)
        glkView.context = context!
        glkView.drawableDepthFormat = GLKViewDrawableDepthFormat(rawValue: 2)!
        glGenBuffers(1, &renderBuffer)
        glBindBuffer(GLenum(GL_RENDERBUFFER), renderBuffer)
        coreImageContext = CIContext(eaglContext: context!)
    }
    
    public func performQRCodeDetection(image:CIImage) -> (hightlightedRaw:UIImage?, decode:String,qrcode:UIImage?) {
        var resultImage:CIImage?
        var decode = ""
        var transformedImage:CIImage?
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy:CIDetectorAccuracyHigh])!
        let features = detector.features(in: image)
        for feature in features as! [CIQRCodeFeature] {
            resultImage = drawHighlightOverlayForPoints(image, topLeft: feature.topLeft, topRight: feature.topRight, bottomLeft: feature.bottomLeft, bottomRight: feature.bottomRight)
            decode = feature.messageString!
            let filter = CIFilter(name: "CIQRCodeGenerator")!
            filter.setValue(decode.data(using: .isoLatin1, allowLossyConversion: false), forKey: "inputMessage")
            filter.setValue("Q", forKey: "inputCorrectionLevel")
            let qrImage = filter.outputImage!
            let scaleX = size.width / qrImage.extent.size.width
            let scaleY = size.height / qrImage.extent.size.height
            transformedImage = qrImage.applying(CGAffineTransform(scaleX: scaleX, y: scaleY))
        }
        if resultImage != nil {
            return (UIImage(ciImage: resultImage!),decode,UIImage(ciImage: transformedImage!))
        }else {
            return (nil,decode,nil)
        }
    }
    
    fileprivate func drawHighlightOverlayForPoints(_ image:CIImage,
                                                   topLeft:CGPoint,
                                                   topRight:CGPoint,
                                                   bottomLeft:CGPoint,
                                                   bottomRight:CGPoint) -> CIImage {
        var overlay = CIImage(color: CIColor(red: 1, green: 0.55, blue: 0, alpha: 0.45))
        overlay = overlay.cropping(to: image.extent)
        overlay = overlay.applyingFilter("CIPerspectiveTransformWithExtent", withInputParameters: [
            "inputExtent":CIVector(cgRect: image.extent),
            "inputTopLeft":CIVector(cgPoint: topLeft),
            "inputTopRight":CIVector(cgPoint: topRight),
            "inputBottomLeft":CIVector(cgPoint: bottomLeft),
            "inputBottomRight":CIVector(cgPoint: topLeft)
            ])
        return overlay.compositingOverImage(image)
    }
}

extension QRScanner: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    public func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
        let buffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
        let image = CIImage(cvImageBuffer: buffer)
        let result = performQRCodeDetection(image: image) as! (hightlightedRaw: UIImage?, decode: String, qrCode: UIImage?)
        if result.hightlightedRaw != nil {
            DispatchQueue.main.async {
                self.cameraDelegate?.didFinishProcessingData(result: result)
                self.session.stopRunning()
                self.cameraLayer.removeFromSuperlayer()
            }
        }else {
            cameraDelegate?.didFailProcessingData(error: NSError(domain: "Error", code: 001, userInfo: ["LocalizaedDescription":"Unknow Error, please retry!"]))
        }
        context!.presentRenderbuffer(Int(GL_RENDERER))
    }
}

public protocol QRScannerDelegate:class{
    func didFinishProcessingData(result:(hightlightedRaw:UIImage?, decode:String, qrCode:UIImage?))
    func didFailProcessingData(error:NSError)
}
