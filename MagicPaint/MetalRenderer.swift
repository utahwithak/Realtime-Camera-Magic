//
//  MetalRenderer.swift
//  MagicPaint
//
//  Created by Carl Wieland on 9/29/15.
//  Copyright © 2015 Carl Wieland. All rights reserved.
//

import UIKit
import AVFoundation
import Metal
import MetalPerformanceShaders

let kMaxBufferBytesPerFrame = 1024*1024;
let kInFlightCommandBuffers = 3;
let vertexData:[Float] =
[
    -1.0, -1.0, 0.0, 1.0,
    -1.0,  1.0, 0.0, 1.0,
    1.0, -1.0, 0.0, 1.0,
    
    1.0, -1.0, 0.0, 1.0,
    -1.0,  1.0, 0.0, 1.0,
    1.0,  1.0, 0.0, 1.0,
    
]

let uvData:[Float] =
[
    0, 0,
    0, 1,
    1, 0,
    1, 0,
    0, 1,
    1, 1,
]




class MetalRenderer: NSObject,GameViewControllerDelegate,MetalViewDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    var device:MTLDevice!
    var commandQueue:MTLCommandQueue!
    var defaultLibrary:MTLLibrary!
    var inflight_semaphore:dispatch_semaphore_t = dispatch_semaphore_create(kInFlightCommandBuffers);
    var constantDataBufferIndex = 0;
    
    var dynamicUniformBuffer = [MTLBuffer]()
    
    // render stage
    var pipelineState:MTLRenderPipelineState!;
    var vertexBuffer:MTLBuffer!;
    var uvBuffer:MTLBuffer!;
    var labColorBuffer:MTLBuffer!;

    
    var depthState:MTLDepthStencilState!;
    var sampler:MTLSamplerState!
    
    // Video texture
    let captureSession = AVCaptureSession();
    var videoTextureCache:CVMetalTextureCacheRef!;
    var videoTexture = [MTLTexture?](count:3,repeatedValue:nil)
    
    
    func configure(view:MetalView){
        self.device = view.device
        // setup view with drawable formats
        view.depthPixelFormat   = MTLPixelFormat.Depth32Float;
        view.stencilPixelFormat = MTLPixelFormat.Invalid;
        view.sampleCount        = 1
        
        // create a new command queue
        self.commandQueue = self.device.newCommandQueue();
        
        self.defaultLibrary = self.device.newDefaultLibrary();
        if(self.defaultLibrary == nil) {
            NSLog(">> ERROR: Couldnt create a default shader library");
            // assert here becuase if the shader libary isn't loading, nothing good will happen
            assert(false,"false");
        }
        
        // allocate one region of memory for the constant buffer
        for i in 0..<kInFlightCommandBuffers{
            let buffer = self.device.newBufferWithLength(kMaxBufferBytesPerFrame, options: MTLResourceOptions.CPUCacheModeDefaultCache)
            buffer.label = "ConstantBuffer\(i)"
            dynamicUniformBuffer.append(buffer)
            
        }

        
        // setup the depth state
        let depthStateDesc = MTLDepthStencilDescriptor()
        depthStateDesc.depthCompareFunction = MTLCompareFunction.Always;
        depthStateDesc.depthWriteEnabled = true;
        self.depthState = self.device.newDepthStencilStateWithDescriptor(depthStateDesc);

        
        // generate a large enough buffer to allow streaming vertices for 3 semaphore controlled frames
        vertexBuffer = device.newBufferWithLength(kMaxBufferBytesPerFrame, options: [])
        vertexBuffer.label = "vertices"
        
        uvBuffer = device.newBufferWithLength(kMaxBufferBytesPerFrame, options: [])
        uvBuffer.label = "uvs"
        
        labColorBuffer = device.newBufferWithLength(3 * sizeof(Float), options: MTLResourceOptions.CPUCacheModeDefaultCache)
        labColorBuffer.label = "labColors"
        
        self.defaultLibrary = device.newDefaultLibrary()!
        let fragmentProgram = defaultLibrary.newFunctionWithName("passThroughFragment")!
        let vertexProgram = defaultLibrary.newFunctionWithName("passThroughVertex")!
        
        let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
        pipelineStateDescriptor.vertexFunction = vertexProgram
        pipelineStateDescriptor.fragmentFunction = fragmentProgram
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormat.BGRA8Unorm
        pipelineStateDescriptor.depthAttachmentPixelFormat      = view.depthPixelFormat;

        pipelineStateDescriptor.sampleCount = view.sampleCount
        
        do {
            try pipelineState = device.newRenderPipelineStateWithDescriptor(pipelineStateDescriptor)
        } catch let error {
            print("Failed to create pipeline state, error \(error)")
        }
        
        
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = MTLSamplerMinMagFilter.Nearest;
        samplerDescriptor.magFilter = MTLSamplerMinMagFilter.Linear;
        self.sampler = self.device.newSamplerStateWithDescriptor(samplerDescriptor);
        
        setupVideoCapture()
        
        let LAB = rgbToLAB(0, g:0, b:0)
        let pData = labColorBuffer.contents()
        let vData = UnsafeMutablePointer<Float>(pData)
        vData[0] = LAB.l
        vData[1] = LAB.a
        vData[2] = LAB.b
    }
    
    func update(controller:GameViewController)->Void{
        
        // vData is pointer to the MTLBuffer's Float data contents
        let pData = vertexBuffer.contents()
        let vData = UnsafeMutablePointer<Float>(pData + 256 * constantDataBufferIndex)
        
        // reset the vertices to default before adding animated offsets
        vData.initializeFrom(vertexData)
        
        let uData = uvBuffer.contents()
        let mutUV = UnsafeMutablePointer<Float>(uData + 256 * constantDataBufferIndex)
        
        // reset the vertices to default before adding animated offsets
        mutUV.initializeFrom(uvData)
        
    }
    
    
    func viewController(controller:GameViewController, willPause pause:Bool){
        if(pause){
            
        }
        else{
            
        }
    }
    
    // called if the view changes orientation or size, renderer can precompute its view and projection matricies here for example
    func reshape(view:MetalView)->Void{
        
    }
    
    
    func blurTexture(inout inTexture:MTLTexture,  blurRadius:Float, q:MTLCommandQueue)
    {
        // Create the usual Metal objects.
        // MPS does not need a dedicated MTLCommandBuffer or MTLComputeCommandEncoder.
        // This is a trivial example. You should reuse the MTL objects you already have, if you have them.
        let device = q.device;
        let  buffer = q.commandBuffer();
        let allocator = { (filter:MPSKernel, cmdBuf:MTLCommandBuffer, sourceTexture:MTLTexture) -> MTLTexture in
            let format = sourceTexture.pixelFormat
            let d = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(format, width: sourceTexture.width, height: sourceTexture.height, mipmapped: false)
            let result = cmdBuf.device.newTextureWithDescriptor(d)
            return result
        }
        
        // Create a MPS filter.
        let blur = MPSImageGaussianBlur(device: device, sigma: blurRadius)
        // Defaults are okay here for other MPSKernel properties (clipRect, origin, edgeMode).
    
        // Attempt to do the work in place.  Since we provided a copyAllocator as an out-of-place
        // fallback, we don’t need to check to see if it succeeded or not.
        // See the "Minimal MPSCopyAllocator Implementation" code listing for a sample myAllocator.
        var mutable = inTexture as MTLTexture?;

        blur.encodeToCommandBuffer(buffer, inPlaceTexture: &mutable, fallbackCopyAllocator: allocator)
        buffer.commit()
        
        // The usual Metal enqueue process.
        buffer.waitUntilCompleted();
    
    }

    
    
    
    // delegate should perform all rendering here
    func render(view:MetalView)->Void{
        // Allow the renderer to preflight 3 frames on the CPU (using a semapore as a guard) and commit them to the GPU.
        // This semaphore will get signaled once the GPU completes a frame's work via addCompletedHandler callback below,
        // signifying the CPU can go ahead and prepare another frame.
        dispatch_semaphore_wait(inflight_semaphore, DISPATCH_TIME_FOREVER);
        
        // Prior to sending any data to the GPU, constant buffers should be updated accordingly on the CPU.
//        [self updateConstantBuffer];
        
        // create a new command buffer for each renderpass to the current drawable
        let commandBuffer = self.commandQueue.commandBuffer();
        
        // create a render command encoder so we can render into something

        if let renderPassDescriptor = view.renderPassDescriptor, drawable = view.currentDrawable, texture = self.videoTexture[constantDataBufferIndex]{
        
            let renderEncoder = commandBuffer.renderCommandEncoderWithDescriptor(renderPassDescriptor);
            renderEncoder.setDepthStencilState(depthState)
            
            
            renderEncoder.pushDebugGroup("screen")
            renderEncoder.setRenderPipelineState(pipelineState)
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 256*constantDataBufferIndex, atIndex: 0)
            renderEncoder.setVertexBuffer(uvBuffer, offset: 256*constantDataBufferIndex, atIndex: 1)
            renderEncoder.setVertexBuffer(labColorBuffer, offset:0, atIndex: 2)
            
            renderEncoder.setFragmentSamplerState(self.sampler, atIndex: 0)
//            var toBlur = texture
//            blurTexture(&toBlur, blurRadius: 2, q: self.commandQueue)
            renderEncoder.setFragmentTexture(texture, atIndex: 0)

            renderEncoder.drawPrimitives(.Triangle, vertexStart: 0, vertexCount: 6, instanceCount: 1)
            
            renderEncoder.popDebugGroup()
            renderEncoder.endEncoding();
            
            // schedule a present once the framebuffer is complete
            commandBuffer.presentDrawable(drawable);
        }
        
        // Add a completion handler / block to be called once the command buffer is completed by the GPU. All completion handlers will be returned in the order they were committed.
        let block_sema = inflight_semaphore;
        commandBuffer.addCompletedHandler { (buffer:MTLCommandBuffer) -> Void in
            // GPU has completed rendering the frame and is done using the contents of any buffers previously encoded on the CPU for that frame.
            // Signal the semaphore and allow the CPU to proceed and construct the next frame.
            dispatch_semaphore_signal(block_sema);
        }
        
        // finalize rendering here. this will push the command buffer to the GPU
        commandBuffer.commit();
        
        // This index represents the current portion of the ring buffer being used for a given frame's constant buffer updates.
        // Once the CPU has completed updating a shared CPU/GPU memory buffer region for a frame, this index should be updated so the
        // next portion of the ring buffer can be written by the CPU. Note, this should only be done *after* all writes to any
        // buffers requiring synchronization for a given frame is done in order to avoid writing a region of the ring buffer that the GPU may be reading.
        constantDataBufferIndex = (constantDataBufferIndex + 1) % kInFlightCommandBuffers;

    }
    
    
    
    func setupVideoCapture(){
        
        var texCache = Unmanaged<CVMetalTextureCache>?()
        
        let status = CVMetalTextureCacheCreate(kCFAllocatorDefault,nil, self.device, nil, &texCache)
        if status == kCVReturnSuccess{
            videoTextureCache = texCache!.takeRetainedValue()
        }
        else{
            assert(false,">> ERROR: Couldnt create a texture cache");
        }
        
        self.captureSession.beginConfiguration()
        self.captureSession.sessionPreset = AVCaptureSessionPresetHigh;
                
        // Get the a video device with preference to the front facing camera
        var videoDevice:AVCaptureDevice! = nil
        let devices = AVCaptureDevice.devicesWithMediaType(AVMediaTypeVideo);
        for device in devices
        {
            if (device.position == AVCaptureDevicePosition.Back)
            {
                videoDevice = device as? AVCaptureDevice;
                break;
            }
        }
        if(videoDevice == nil){
            videoDevice = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeVideo);
        }
                
        if(videoDevice == nil){
            assert(false,">> ERROR: Couldnt create a AVCaptureDevice");
        }
        
        do{
            // Device input
            let deviceInput = try AVCaptureDeviceInput(device: videoDevice)
            
            captureSession.addInput(deviceInput);
            
            // Create the output for the capture session.
            let dataOutput = AVCaptureVideoDataOutput()
            dataOutput.alwaysDiscardsLateVideoFrames = true
            let settings = //[String(kCVPixelBufferPixelFormatTypeKey):Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)];
            [(kCVPixelBufferPixelFormatTypeKey as NSString):Int(kCVPixelFormatType_32BGRA)] as [NSObject : AnyObject];
            // Set the color space.
            dataOutput.videoSettings = settings
            
            // Set dispatch to be on the main thread to create the texture in memory and allow Metal to use it for rendering
            dataOutput.setSampleBufferDelegate(self, queue:dispatch_get_main_queue());
            
            captureSession.addOutput(dataOutput);
            captureSession.commitConfiguration()
            // this will trigger capture on its own queue
            captureSession.startRunning();
        }
        catch{
            assert(false,">> ERROR: Couldnt create AVCaptureDeviceInput:\(error)");
        }
    }
    
    func captureOutput(captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, fromConnection connection: AVCaptureConnection!) {
//        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer){
//            
//            var textureY:MTLTexture? = nil;
//            var textureCbCr:MTLTexture? = nil;
//            
//            let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0);
//            var textureRef: Unmanaged<CVMetalTextureRef>?
//            var status = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, videoTextureCache, pixelBuffer,nil, MTLPixelFormat.R8Unorm,  CVPixelBufferGetWidthOfPlane(pixelBuffer, 0), height, 0, &textureRef);
//            if let tex = textureRef where status == kCVReturnSuccess
//            {
//                textureY = CVMetalTextureGetTexture(tex.takeRetainedValue());
//            }
//            
//            
//            // textureCbCr
//            status = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, videoTextureCache, pixelBuffer, nil, MTLPixelFormat.RG8Unorm, CVPixelBufferGetWidthOfPlane(pixelBuffer, 1), CVPixelBufferGetHeightOfPlane(pixelBuffer, 1), 1, &textureRef);
//            if let tex = textureRef where status == kCVReturnSuccess
//            {
//                textureCbCr = CVMetalTextureGetTexture(tex.takeRetainedValue());
//            }
//            if let texY = textureY, texCbCr = textureCbCr{
//                let doubleProvider = TwoTextureProvider(tex1: texY, tex2: texCbCr)
//                let textConversionFilter = TextureColorConversion(provider: doubleProvider, context: context)
//                self.videoTexture[constantDataBufferIndex] = textConversionFilter.texture;
//
////                if let image = UIImage.image(textConversionFilter.texture){
////                    print("image:\(image)")
////                }
//            }
//        }
        if let sourceImageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer){
            let width = CVPixelBufferGetWidth(sourceImageBuffer);
            let height = CVPixelBufferGetHeight(sourceImageBuffer);
            
            
            var textureRef: Unmanaged<CVMetalTextureRef>?
            let status = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, videoTextureCache, sourceImageBuffer,nil, MTLPixelFormat.BGRA8Unorm,  width, height, 0, &textureRef);
            if let tex = textureRef, texture =  CVMetalTextureGetTexture(tex.takeRetainedValue()) where status == kCVReturnSuccess
            {
                self.videoTexture[constantDataBufferIndex] = texture;
            }
            else{
                assert(false,">> ERROR: Couldn't get texture from texture ref");
            }
            
        }
    }
    
}
