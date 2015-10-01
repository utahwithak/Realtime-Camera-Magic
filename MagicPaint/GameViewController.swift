//
//  GameViewController.swift
//  MagicPaint
//
//  Created by Carl Wieland on 9/29/15.
//  Copyright © 2015 Carl Wieland. All rights reserved.
//

import UIKit
import Metal
import MetalKit


class GameViewController:UIViewController {
    weak var delegate:GameViewControllerDelegate? = nil
    var timeSinceLastDraw:NSTimeInterval = 0
    // What vsync refresh interval to fire at. (Sets CADisplayLink frameinterval property)
    // set to 1 by default, which is the CADisplayLink default setting (60 FPS).
    // Setting to 2, will cause gameloop to trigger every other vsync (throttling to 30 FPS)
    var interval = 1
    // Used to pause and resume the controller.
    var paused:Bool{
        get{
            return gameLoopPaused
        }
        set{
            if(gameLoopPaused == newValue)
            {
                return;
            }
            
            if(self.timer != nil)
            {
                // inform the delegate we are about to pause
                self.delegate?.viewController(self,
                    willPause:newValue);
                
                if(newValue == true)
                {
                    gameLoopPaused = newValue;
                    timer?.paused   = true
                    
                    // ask the view to release textures until its resumed
                    (self.view as? MetalView)?.releaseTextures();
                }
                else
                {
                    gameLoopPaused = newValue;
                    timer?.paused   = false;
                }
            }

        }
    }
    
    var timer:CADisplayLink? = nil
    
    var firstDrawOccurred = false
    var timeSinceLastDrawPreviousTime:CFTimeInterval = 0
    var gameLoopPaused = false
    let renderer = MetalRenderer()
    
    
    
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        if let view = self.view as? MetalView{
            view.delegate = renderer
            renderer.configure(view)
        }
        self.delegate = renderer
        interval = 1
        NSNotificationCenter.defaultCenter().addObserver(self, selector: Selector("didEnterBackground:"), name: UIApplicationDidEnterBackgroundNotification, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: Selector("willEnterForground:"), name: UIApplicationWillEnterForegroundNotification, object: nil)
        
    }
    
    deinit{
        NSNotificationCenter.defaultCenter().removeObserver(self, name: UIApplicationDidEnterBackgroundNotification, object: nil)
        NSNotificationCenter.defaultCenter().removeObserver(self, name: UIApplicationWillEnterForegroundNotification, object: nil)
    }
    
    // used to fire off the main game loop
    func dispatchGameLoop(){
        timer = UIScreen.mainScreen().displayLinkWithTarget(self, selector: Selector("gameloop"))
        timer?.frameInterval = self.interval
        timer?.addToRunLoop(NSRunLoop.mainRunLoop(), forMode: NSDefaultRunLoopMode)
    }
    
    // the main game loop called by the timer above
    func gameloop(){
    
        // tell our delegate to update itself here.
        self.delegate?.update(self)
    
        if(!firstDrawOccurred){
            // set up timing data for display since this is the first time through this loop
            timeSinceLastDraw             = 0.0;
            timeSinceLastDrawPreviousTime = CACurrentMediaTime();
            firstDrawOccurred              = true;
        }
        else
        {
            // figure out the time since we last we drew
            let currentTime = CACurrentMediaTime();
    
            timeSinceLastDraw = currentTime - timeSinceLastDrawPreviousTime;
    
            // keep track of the time interval between draws
            timeSinceLastDrawPreviousTime = currentTime;
        }
    
        // display (render)
        assert(self.view.isKindOfClass(MetalView.classForCoder()));
    
        // call the display method directly on the render view (setNeedsDisplay: has been disabled in the renderview by default)
        (self.view as! MetalView).display();
    }
    
    // use invalidates the main game loop. when the app is set to terminate
    func stopGameLoop(){
        timer?.invalidate()
    }

    func didEnterBackground(notification:NSNotification){
        self.paused = true
    }
    func willEnterForground(notification:NSNotification){
        self.paused = false
    }
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        self.dispatchGameLoop()
    }
    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)
        self.stopGameLoop()
    }
    

    
}


protocol GameViewControllerDelegate:NSObjectProtocol{
    func update(controller:GameViewController)->Void
    func viewController(controller:GameViewController, willPause pause:Bool)
    
    
}