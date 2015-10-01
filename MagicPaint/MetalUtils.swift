//
//  MetalProtocols.swift
//  RAV
//
//  Created by Carl Wieland on 7/7/15.
//  Copyright © 2015 Carl Wieland. All rights reserved.
//
import UIKit
import Metal

protocol MetalTextureProvider:class{
    var texture:MTLTexture{get}
}

protocol MetalTextureConsumer:class{
    var provider:MetalTextureProvider?{get}
}

//func writeImageToFile( image:CGImageRef, path:String)->Bool {
//    let url = NSURL(fileURLWithPath: path);
//    guard let destination = CGImageDestinationCreateWithURL(url, kUTTypePNG, 1, nil) else{
//        NSLog("Failed to create CGImageDestination for \(path)");
//        return false;
//    }
//    
//    CGImageDestinationAddImage(destination, image, nil);
//    
//    if (!CGImageDestinationFinalize(destination)) {
//        NSLog("Failed to write image to \(path)");
//        
//        return false;
//    }
//    
//    return true;
//}

func rgbToLAB(r:Float, g:Float, b:Float)->(l:Float,a:Float,b:Float){
    var var_R = r;
    var var_G = g;
    var var_B = b;
    
    if ( var_R > 0.04045 ){
        var_R = pow(( ( var_R + 0.055 ) / 1.055 ), 2.4);
    }
    else{
        var_R = var_R / 12.92;
    }
    
    if ( var_G > 0.04045 ) {
        var_G = pow(( ( var_G + 0.055 ) / 1.055 ) , 2.4);
    }
    else{
        var_G = var_G / 12.92;
    }
    if ( var_B > 0.04045 ){
        var_B = pow(( ( var_B + 0.055 ) / 1.055 ), 2.4);
    }
    else{
        var_B = var_B / 12.92;
        
    }
    var_R = var_R * 100;
    var_G = var_G * 100;
    var_B = var_B * 100;
    
    //Observer. = 2°, Illuminant = D65
    let X = var_R * 0.4124 + var_G * 0.3576 + var_B * 0.1805;
    let Y = var_R * 0.2126 + var_G * 0.7152 + var_B * 0.0722;
    let Z = var_R * 0.0193 + var_G * 0.1192 + var_B * 0.9505;
    
    var var_X = X / 95.047;//ref_X          //ref_X =  95.047   Observer= 2°, Illuminant= D65
    var var_Y = Y / 100.000;          //ref_Y = 100.000
    var var_Z = Z / 108.883;          //ref_Z = 108.883
    
    if ( var_X > 0.008856 ){
        var_X = pow(var_X,0.333333333333);
    }
    else{
        var_X = ( 7.787 * var_X ) + ( 16 / 116 );
    }
    if ( var_Y > 0.008856 ){
        var_Y = pow(var_Y ,0.333333333333);
    }
    else{
        var_Y = ( 7.787 * var_Y ) + ( 16 / 116 );
    }
    if ( var_Z > 0.008856 ){
        var_Z = pow(var_Z,0.333333333333);
    }
    else{
        var_Z = ( 7.787 * var_Z ) + ( 16 / 116 );
    }
    
    let CIEL = ( 116 * var_Y ) - 16;
    let CIEa = 500 * ( var_X - var_Y );
    let CIEb = 200 * ( var_Y - var_Z );
    return (CIEL,CIEa,CIEb)
}

extension UIImage{
    static func image(texture:MTLTexture)->UIImage?{
        
//        assert(texture.pixelFormat == MTLPixelFormat.RGBA8Unorm,"Pixel format of texture must be RGBA8Unorm to create UIImage");
        
        let width = texture.width
        let height = texture.height
        let imageByteCount = width * height * 4;
        let data = NSMutableData(length: imageByteCount)!

        let imageBytes = UnsafeMutablePointer<UInt8>(data.bytes)
        
        let bytesPerRow = width * 4;
        let region = MTLRegionMake2D(0, 0, width, height);
        texture.getBytes(imageBytes, bytesPerRow:bytesPerRow, fromRegion:region,mipmapLevel:0);
        let provider = CGDataProviderCreateWithData(nil, data.bytes, imageByteCount,nil);
        let bitsPerComponent = 8;
        let bitsPerPixel = 32;
        let colorSpaceRef = CGColorSpaceCreateDeviceRGB()!
        let bitmapInfo = CGBitmapInfo (rawValue: CGImageAlphaInfo.PremultipliedLast.rawValue | CGBitmapInfo.ByteOrder32Big.rawValue);
        let renderingIntent = CGColorRenderingIntent.RenderingIntentDefault;
        if let imageRef = CGImageCreate(width,
            height,
            bitsPerComponent,
            bitsPerPixel,
            bytesPerRow,
            colorSpaceRef,
            bitmapInfo,
            provider,
            nil,
            false,
            renderingIntent){
        
                let image = UIImage(CGImage: imageRef)
//                let dir = NSFileManager.defaultManager().applicationSupportDirectory().stringByAppendingString("/test.png")
//                print("Dir:\(dir)")
//                writeImageToFile(imageRef,path:dir)
                return image
        }
        
        return nil

    }
    
    
//    func fixOrientation()->UIImage {
//    
////    // No-op if the orientation is already correct
////    if (self.imageOrientation == UIImageOrientation.Up) return self;
//    
//    // We need to calculate the proper transformation to make the image upright.
//    // We do it in 2 steps: Rotate if Left/Right/Down, and then flip if Mirrored.
//    var transform = CGAffineTransformIdentity;
//    
//    switch (self.imageOrientation) {
//    case UIImageOrientation.Down: fallthrough
//    case UIImageOrientation.DownMirrored:
//        transform = CGAffineTransformTranslate(transform, self.size.width, self.size.height);
//        transform = CGAffineTransformRotate(transform, CGFloat(M_PI));
//    case UIImageOrientation.Left: fallthrough
//    case UIImageOrientation.LeftMirrored:
//        transform = CGAffineTransformTranslate(transform, self.size.width, 0);
//        transform = CGAffineTransformRotate(transform,CGFloat(M_PI_2));
//    
//    case UIImageOrientation.Right: fallthrough
//    case UIImageOrientation.RightMirrored:
//        transform = CGAffineTransformTranslate(transform, 0, self.size.height);
//        transform = CGAffineTransformRotate(transform, CGFloat(-M_PI_2));
//    case UIImageOrientation.Up:fallthrough
//    case UIImageOrientation.UpMirrored:
//    break;
//    }
//    
//    switch (self.imageOrientation) {
//    case UIImageOrientation.UpMirrored:fallthrough
//    case UIImageOrientation.DownMirrored:
//        transform = CGAffineTransformTranslate(transform, self.size.width, 0);
//        transform = CGAffineTransformScale(transform, -1, 1);
//    break;
//    
//    case UIImageOrientation.LeftMirrored:fallthrough
//    case UIImageOrientation.RightMirrored:
//        transform = CGAffineTransformTranslate(transform, self.size.height, 0);
//        transform = CGAffineTransformScale(transform, -1, 1);
//    break;
//    case UIImageOrientation.Up:fallthrough
//    case UIImageOrientation.Down:fallthrough
//    case UIImageOrientation.Left:fallthrough
//    case UIImageOrientation.Right:
//    break;
//    }
//    
//    // Now we draw the underlying CGImage into a new context, applying the transform
//    // calculated above.
//    let ctx = CGBitmapContextCreate(nil, Int(self.size.width), Int(self.size.height),
//    CGImageGetBitsPerComponent(self.CGImage), 0,
//    CGImageGetColorSpace(self.CGImage)!,
//    CGImageGetBitmapInfo(self.CGImage).rawValue);
//    CGContextConcatCTM(ctx, transform);
//    switch (self.imageOrientation) {
//    case UIImageOrientation.Left:fallthrough
//    case UIImageOrientation.LeftMirrored:fallthrough
//    case UIImageOrientation.Right:fallthrough
//    case UIImageOrientation.RightMirrored:
//    // Grr...
//    CGContextDrawImage(ctx, CGRectMake(0,0,self.size.height,self.size.width), self.CGImage);
//    break;
//    
//    default:
//    CGContextDrawImage(ctx, CGRectMake(0,0,self.size.width,self.size.height), self.CGImage);
//    break;
//    }
//    
//    // And now we just create a new UIImage from the drawing context
//    let cgimg = CGBitmapContextCreateImage(ctx)!
//    let img = UIImage(CGImage: cgimg)
//    return img;
//    }
//
    
}