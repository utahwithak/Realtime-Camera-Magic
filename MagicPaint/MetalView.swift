//
//  MetalView.swift
//  MagicPaint
//
//  Created by Carl Wieland on 9/29/15.
//  Copyright © 2015 Carl Wieland. All rights reserved.
//

import UIKit
import Metal


@objc protocol MetalViewDelegate{
    // called if the view changes orientation or size, renderer can precompute its view and projection matricies here for example
    func reshape(view:MetalView)->Void
    
    // delegate should perform all rendering here
    func render(view:MetalView)->Void
}


class MetalView: UIView {
    weak var delegate:MetalViewDelegate? = nil
    weak var _metalLayer:CAMetalLayer? = nil
    
    var _depthTex:MTLTexture? = nil
    var _stencilTex:MTLTexture? = nil
    var _msaaTex:MTLTexture? = nil
    var _layerSizeDidUpdate = false

    let device:MTLDevice!
    
    var _currentDrawable:CAMetalDrawable? = nil
    var currentDrawable:CAMetalDrawable?{
        if(_currentDrawable == nil){
            _currentDrawable = _metalLayer?.nextDrawable()
        }
        return _currentDrawable
    }
    
    
    var depthPixelFormat:MTLPixelFormat = MTLPixelFormat.Invalid
    var stencilPixelFormat:MTLPixelFormat = MTLPixelFormat.Invalid;
    var sampleCount:Int = 0
    
    
    override init(frame: CGRect) {
        self.device = MTLCreateSystemDefaultDevice()
        
        super.init(frame: frame)
        self.opaque = true
        self.backgroundColor = nil
        _metalLayer = self.layer as? CAMetalLayer
        _metalLayer?.device = self.device
        _metalLayer?.pixelFormat = MTLPixelFormat.BGRA8Unorm;
        
        // this is the default but if we wanted to perform compute on the final rendering layer we could set this to no
        _metalLayer?.framebufferOnly = true;


    }
    required init?(coder aDecoder: NSCoder) {

        self.device = MTLCreateSystemDefaultDevice()

        super.init(coder: aDecoder)
        
        self.opaque = true
        self.backgroundColor = nil
        _metalLayer = self.layer as? CAMetalLayer
        _metalLayer?.device = self.device
        _metalLayer?.pixelFormat     = MTLPixelFormat.BGRA8Unorm;
        
        // this is the default but if we wanted to perform compute on the final rendering layer we could set this to no
        _metalLayer?.framebufferOnly = true;

    }
    static override func layerClass()->AnyClass{
        return CAMetalLayer.classForCoder()
    }
    
    override func didMoveToWindow() {
        self.contentScaleFactor = (self.window?.screen.nativeScale)!
    }
    
    override var contentScaleFactor:CGFloat{
        didSet{
            self._layerSizeDidUpdate = true
        }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        self._layerSizeDidUpdate = true
    }
    
    func setupRenderPassDescriptorForTexture(texture:MTLTexture){
        if(_renderPassDescriptor == nil){
            _renderPassDescriptor = MTLRenderPassDescriptor()
        }
        
        // create a color attachment every frame since we have to recreate the texture every frame
        let colorAttachment = _renderPassDescriptor.colorAttachments[0];
        colorAttachment.texture = texture;
        
        // make sure to clear every frame for best performance
        colorAttachment.loadAction = MTLLoadAction.Clear;
        colorAttachment.clearColor = MTLClearColorMake(0.65, 0.65, 0.65, 1.0);
        
        // if sample count is greater than 1, render into using MSAA, then resolve into our color texture
        if(sampleCount > 1)
        {
           let doUpdate = _msaaTex == nil || ( _msaaTex != nil && (   ( _msaaTex?.width != texture.width  )  ||  ( _msaaTex?.height != texture.height ) ||  ( _msaaTex?.sampleCount != self.sampleCount   )));
            
            if(doUpdate)
            {
                let desc = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat( MTLPixelFormat.BGRA8Unorm,
                    width: texture.width,
                    height: texture.height,
                    mipmapped:false);
                desc.textureType =  MTLTextureType.Type2DMultisample
                
                // sample count was specified to the view by the renderer.
                // this must match the sample count given to any pipeline state using this render pass descriptor
                desc.sampleCount = self.sampleCount;
                
                _msaaTex = self.device?.newTextureWithDescriptor(desc);
            }
            
            // When multisampling, perform rendering to _msaaTex, then resolve
            // to 'texture' at the end of the scene
            colorAttachment.texture = _msaaTex;
            colorAttachment.resolveTexture = texture;
            
            // set store action to resolve in this case
            colorAttachment.storeAction = MTLStoreAction.MultisampleResolve;
        }
        else
        {
            // store only attachments that will be presented to the screen, as in this case
            colorAttachment.storeAction = MTLStoreAction.Store;
        } // color0
        
        // Now create the depth and stencil attachments
        
        if(self.depthPixelFormat != MTLPixelFormat.Invalid)
        {
            let doUpdate =   _depthTex == nil || (  ( _depthTex?.width != texture.width  )  ||  ( _depthTex?.height != texture.height ) ||  ( _depthTex?.sampleCount != self.sampleCount   ));
            
            if( doUpdate)
            {
                //  If we need a depth texture and don't have one, or if the depth texture we have is the wrong size
                //  Then allocate one of the proper size
                let desc = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(depthPixelFormat,
                    width: texture.width,
                    height: texture.height,
                    mipmapped: false);
                
                desc.textureType = (self.sampleCount > 1) ? MTLTextureType.Type2DMultisample : MTLTextureType.Type2D;
                desc.sampleCount = self.sampleCount;
                
                _depthTex = self.device?.newTextureWithDescriptor(desc);
                
                let depthAttachment = _renderPassDescriptor.depthAttachment;
                depthAttachment.texture = _depthTex;
                depthAttachment.loadAction = MTLLoadAction.Clear;
                depthAttachment.storeAction = MTLStoreAction.DontCare;
                depthAttachment.clearDepth = 1.0;
            }
        } // depth
        
        if(stencilPixelFormat != MTLPixelFormat.Invalid)
        {
            let doUpdate  = _stencilTex == nil || (  ( _stencilTex?.width       != texture.width  )
                ||  ( _stencilTex?.height      != texture.height )
                ||  ( _stencilTex?.sampleCount != self.sampleCount   ));
            
            if(doUpdate)
            {
                //  If we need a stencil texture and don't have one, or if the depth texture we have is the wrong size
                //  Then allocate one of the proper size
                let desc = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(stencilPixelFormat,
                    width: texture.width,
                    height: texture.height,
                    mipmapped: false);
                
                desc.textureType = (self.sampleCount > 1) ? MTLTextureType.Type2DMultisample : MTLTextureType.Type2D;
                desc.sampleCount = self.sampleCount;
                
                _stencilTex = self.device?.newTextureWithDescriptor(desc);
                
                let stencilAttachment = _renderPassDescriptor.stencilAttachment;
                stencilAttachment.texture = _stencilTex;
                stencilAttachment.loadAction = MTLLoadAction.Clear;
                stencilAttachment.storeAction = MTLStoreAction.DontCare;
                stencilAttachment.clearStencil = 0;
            }
        } //stencil
        
        
    }
    
    var _renderPassDescriptor:MTLRenderPassDescriptor! = nil
    var renderPassDescriptor:MTLRenderPassDescriptor?{
        if let drawable = self.currentDrawable{
            self.setupRenderPassDescriptorForTexture(drawable.texture)
        }
        else{
            _renderPassDescriptor = nil
        }
        return _renderPassDescriptor
    }
    
    
    
    func display(){
        // Create autorelease pool per frame to avoid possible deadlock situations
        // because there are 3 CAMetalDrawables sitting in an autorelease pool.
        
        autoreleasepool
        {
            // handle display changes here
            if(_layerSizeDidUpdate)
            {
                // set the metal layer to the drawable size in case orientation or size changes
                var drawableSize = self.bounds.size;
                drawableSize.width  *= self.contentScaleFactor;
                drawableSize.height *= self.contentScaleFactor;
                
                _metalLayer?.drawableSize = drawableSize;
                
                // renderer delegate method so renderer can resize anything if needed
                self.delegate?.reshape(self);
                
                _layerSizeDidUpdate = false;
            }
            
            // rendering delegate method to ask renderer to draw this frame's content
            self.delegate?.render(self);
            
            // do not retain current drawable beyond the frame.
            // There should be no strong references to this object outside of this view class
            _currentDrawable = nil;
        }

    }
    
    func releaseTextures(){
        _depthTex = nil;
        _stencilTex = nil
        _msaaTex = nil
    }
    
    
    
    
}
