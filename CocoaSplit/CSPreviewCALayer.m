//
//  CSPreviewMetalLayer.m
//  CocoaSplit
//
//  Created by Zakk on 12/27/18.
//

#import "CSPreviewCALayer.h"
CVReturn DisplayCallback(CVDisplayLinkRef displayLink, const CVTimeStamp *now, const CVTimeStamp *outputTime, CVOptionFlags flagsIn, CVOptionFlags *flagsOut, void *displayLinkContext);


@implementation CSPreviewCALayer

@synthesize doDisplay = _doDisplay;
@synthesize doRender = _doRender;
-(instancetype) init
{
    if (self = [super init])
    {
        self.contentsGravity = kCAGravityResizeAspect;
        _lastBounds = NSZeroRect;
        _lastSurfaceSize = NSZeroSize;
        _lastFpsTime = CACurrentMediaTime();
        self.doDisplay = YES;
        _displayQueue = dispatch_queue_create("PreviewCALayer queue", DISPATCH_QUEUE_SERIAL);
        
        CVDisplayLinkCreateWithCGDisplay(CGMainDisplayID(), &_displayLink);
        CVDisplayLinkSetOutputCallback(_displayLink, &DisplayCallback, (__bridge void * _Nullable)(self));
        CVDisplayLinkStart(_displayLink);
    }
    
    return self;
}


-(bool)doRender
{
    bool retval;
    @synchronized (self) {
        retval = _doRender;
    }
    return retval;
}

-(void) setDoRender:(bool)doRender
{
    @synchronized (self) {
        _doRender = doRender;
    }
}

-(void)setDoDisplay:(bool)doDisplay
{
    _doDisplay = doDisplay;
    if (!_displayLink)
    {
        return;
    }
    
    if (_doDisplay && !CVDisplayLinkIsRunning(_displayLink))
    {
        CVDisplayLinkStart(_displayLink);
    } else if (!_doDisplay && CVDisplayLinkIsRunning(_displayLink)) {
        CVDisplayLinkStop(_displayLink);
    }
}

-(bool)doDisplay
{
    return _doDisplay;
}


-(NSPoint)realPointforWindowPoint:(NSPoint)winPoint
{
    return NSMakePoint((winPoint.x - _scaleRect.origin.x)/_scaleRatio, (winPoint.y - _scaleRect.origin.y)/_scaleRatio);
}


-(NSRect)windowRectforWorldRect:(NSRect)worldRect
{
    NSPoint windowOrigin = NSMakePoint((worldRect.origin.x*_scaleRatio)+_scaleRect.origin.x, (worldRect.origin.y*_scaleRatio)+_scaleRect.origin.y);
    NSSize windowSize = NSMakeSize(worldRect.size.width*_scaleRatio, worldRect.size.height*_scaleRatio);
    return NSMakeRect(windowOrigin.x, windowOrigin.y, windowSize.width, windowSize.height);
}

-(void)updateScaleConstants
{
    float wr = _lastBounds.size.width / _lastSurfaceSize.width;
    float hr = _lastBounds.size.height / _lastSurfaceSize.height;
    
    
    _scaleRatio = (hr < wr ? hr : wr);
    NSSize useSize = NSMakeSize(_lastSurfaceSize.width * _scaleRatio, _lastSurfaceSize.height * _scaleRatio);
    
    CGFloat originX = _lastBounds.size.width/2 - useSize.width/2;
    CGFloat originY = _lastBounds.size.height/2 - useSize.height/2;
    _scaleRect = NSMakeRect(originX, originY, useSize.width, useSize.height);
}




-(void)render
{
    if (!self.renderer || !self.renderer.layout)
    {
        return;
    }
    _frameCnt++;
   dispatch_async(_displayQueue
                   , ^{
                       @autoreleasepool {
                           [CATransaction begin];
                               [self displayContent];
        [CATransaction commit];
                           [CATransaction flush];
                      }
                 });

}


-(void)displayContent
{

    CVPixelBufferRef toDraw;
 
    bool sizeDirty = NO;
    
    if (!self.renderer)
    {
        return;
    }
    
    CFTimeInterval sTime = CACurrentMediaTime();
    if (self.doRender)
    {
        toDraw = [self.renderer currentImg];

        if (toDraw)
        {
            CVPixelBufferRetain(toDraw);
        }
    } else {
        toDraw = [self.renderer currentFrame];
    }
    
    CFTimeInterval eTime = CACurrentMediaTime();
    
    float renderTime = eTime - sTime;
    
    if (renderTime < _minRenderTime)
    {
        _minRenderTime = renderTime;
    }
    
    if (renderTime > _maxRenderTime)
    {
        _maxRenderTime = renderTime;
    }
    
    _sumRenderTime += renderTime;
    if (!toDraw)
    {
        return;
    }
    
    
    size_t sWidth = CVPixelBufferGetWidth(toDraw);
    size_t sHeight = CVPixelBufferGetHeight(toDraw);
    NSSize sSize = NSMakeSize(sWidth, sHeight);
    if (!NSEqualSizes(sSize, _lastSurfaceSize))
    {
        _lastSurfaceSize = sSize;
        sizeDirty = YES;
    }

    if (!NSEqualRects(_lastBounds, self.bounds))
    {
        _lastBounds = self.bounds;
        sizeDirty = YES;
    }
    
    if (sizeDirty)
    {
        [self updateScaleConstants];
    }
    
    
    self.contentsGravity = kCAGravityResizeAspect;
    self.minificationFilter = kCAFilterLinear;
    self.magnificationFilter = kCAFilterTrilinear;
    
    if (toDraw)
    {
        if (@available(macOS 10.12, *))
        {
            self.contents = (__bridge id _Nullable)toDraw;
        } else {
            self.contents = (__bridge id _Nullable)(CVPixelBufferGetIOSurface(toDraw));
        }
        CVPixelBufferRelease(toDraw);
        [self displayIfNeeded];
     }
    

}

CVReturn DisplayCallback(CVDisplayLinkRef displayLink, const CVTimeStamp *now, const CVTimeStamp *outputTime, CVOptionFlags flagsIn, CVOptionFlags *flagsOut, void *displayLinkContext)
{
    CSPreviewCALayer *realSelf = (__bridge CSPreviewCALayer *)displayLinkContext;
    
    [realSelf render];
    return kCVReturnSuccess;
}

-(void)dealloc
{
    if (_displayLink)
    {
        CVDisplayLinkStop(_displayLink);
        CVDisplayLinkRelease(_displayLink);
    }
}



@end
