//
//  ImageCapture.m
//  CocoaSplit
//
//  Created by Zakk on 12/27/13.
//  Copyright (c) 2013 Zakk. All rights reserved.
//

#import "ImageCapture.h"
#import "AbstractCaptureDevice.h"

@implementation ImageCapture


@synthesize activeVideoDevice = _activeVideoDevice;
@synthesize imageDirectory = _imageDirectory;
@synthesize settingsController = _settingsController;




-(void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:self.activeVideoDevice.uniqueID forKey:@"active_uniqueID"];
    [aCoder encodeObject:self.imageDirectory forKey:@"imageDirectory"];
}



-(id) initWithCoder:(NSCoder *)aDecoder
{
    if (self = [self init])
    {
        
        self.imageDirectory = [aDecoder decodeObjectForKey:@"imageDirectory"];
        NSString *uniqueID = [aDecoder decodeObjectForKey:@"active_uniqueID"];
        [self setDeviceForUniqueID:uniqueID];
    }
    
    return self;
}


-(id)init
{
    if (self = [super init])
    {
        
        _animationQueue = dispatch_queue_create("imageCaptureQueue", NULL);


    }
    
    return self;
    
}


-(CaptureController *)settingsController
{
    return _settingsController;
}


-(void)setSettingsController:(CaptureController *)settingsController
{
    _settingsController = settingsController;
    self.imageDirectory = [self.settingsController getExtraData:@"ImageCapture:Directory"];
}


- (BOOL)needsAdvancedVideo
{
    return YES;
}


-(void) setImageDirectory:(NSString *)imageDirectory
{
    
    _imageDirectory = imageDirectory;
    [self refreshDirectory];
    [self.settingsController setExtraData:imageDirectory forKey:@"ImageCapture:Directory"];
    
}



-(NSString *)imageDirectory
{
    return _imageDirectory;
}



-(void)refreshDirectory
{
 
    if (!self.imageDirectory)
    {
        return;
    }
    
    
    NSArray *filetypes = [NSImage imageFileTypes];
    
    NSArray *allFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.imageDirectory error:nil];
    
    NSArray *imageFiles = [allFiles filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"pathExtension IN %@", filetypes]];
    
    NSString *fileName;
    
    
    NSMutableArray *retArray = [[NSMutableArray alloc] init];

    for(fileName in imageFiles)
    {
        
        [retArray addObject:[[AbstractCaptureDevice alloc] initWithName:fileName device:self.imageDirectory uniqueID:fileName]];
    }

    [self willChangeValueForKey:@"availableVideoDevices"];
    _sourceList = retArray;
    [self didChangeValueForKey:@"availableVideoDevices"];
    
}

-(NSArray *) availableVideoDevices
{
    
    return _sourceList;
}

-(AbstractCaptureDevice *)activeVideoDevice
{
    return _activeVideoDevice;
}


-(void) advanceGifFrame
{
    
    //wait the current duration, THEN increment the frame and rerender
    
    if (_totalFrames > 1)
    {
        
        int next_frame = _frameNumber + 1;
    
        
        if (next_frame >= _totalFrames)
        {
            next_frame = 0;
        }
    
        double frame_duration =  [[_delayList objectAtIndex:_frameNumber] floatValue];

        
        dispatch_time_t frame_time = dispatch_time(DISPATCH_TIME_NOW, frame_duration * NSEC_PER_SEC);
    
        _frameNumber = next_frame;
        __weak ImageCapture *mySelf = self;
        
        dispatch_after(frame_time, _animationQueue, ^(void){

            [mySelf renderImage:next_frame];
        
        });

    }
    
}

-(void) resetImageData
{
    _totalFrames = 0;
    _frameNumber = 0;
    if (_imageSource)
    {
        CFRelease(_imageSource);
        _imageSource = nil;

    }
    
    if (_imageCache)
    {
        _imageCache = nil;

    }
    _delayList = nil;
}




-(void) dealloc
{

    [self resetImageData];
}


-(void) renderImage:(int)forIdx
{
    CGImageRef theImage = NULL;

    CIImage *newImg = nil;
    
    if (_imageCache.count > forIdx)
    {
        newImg = (CIImage *)[_imageCache objectAtIndex:forIdx ];
    }
    
    if (!newImg && _imageSource)
    {
        theImage = CGImageSourceCreateImageAtIndex(_imageSource, forIdx, NULL);
        
        
        newImg = [CIImage imageWithCGImage:theImage];
        CGImageRelease(theImage);
        [_imageCache insertObject:newImg atIndex:forIdx];
        
    }
    
    _ciimage = newImg;
    
    [self advanceGifFrame];

}


-(void)setActiveVideoDevice:(AbstractCaptureDevice *)activeVideoDevice
{
    
    [self resetImageData];
    
    
    NSData *imgData = [NSData dataWithContentsOfFile:[NSString stringWithFormat:@"%@/%@", activeVideoDevice.captureDevice, activeVideoDevice.uniqueID]];
    
    NSDictionary *dict = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:(id)kCGImageSourceShouldCacheImmediately];

    CGImageSourceRef imgSrc = CGImageSourceCreateWithData((__bridge CFDataRef)imgData, (__bridge CFDictionaryRef)dict);
    
    if (_imageSource)
    {
        CFRelease(_imageSource);
    }
    
    _imageSource = imgSrc;
    _imageCache = [[NSMutableArray alloc] init];
    
    
    
    
    _totalFrames = CGImageSourceGetCount(imgSrc);
    
    if (_totalFrames > 1)
    {
        _delayList = [[NSMutableArray alloc] init];
        
        for (int i=0; i < _totalFrames; i++)
        {
            CFDictionaryRef frameprop = CGImageSourceCopyPropertiesAtIndex(imgSrc, i, NULL);
            CFDictionaryRef gProp = CFDictionaryGetValue(frameprop, kCGImagePropertyGIFDictionary);
        
            CFNumberRef udelay = CFDictionaryGetValue(gProp, kCGImagePropertyGIFUnclampedDelayTime);
            CFNumberRef gdelay = CFDictionaryGetValue(gProp, kCGImagePropertyGIFDelayTime);
            if ([(__bridge NSNumber *)udelay isEqualToNumber:@(0)])
            {
                [_delayList insertObject:(__bridge NSNumber *)gdelay atIndex:i];
            } else {
                [_delayList insertObject:(__bridge NSNumber *)udelay atIndex:i];
            }
        }
    }
    
    
    _activeVideoDevice = activeVideoDevice;
    
    //.device is the directory, uniqueID is the filename
    
    _frameNumber = 0;
    [self renderImage:0];
    
}



-(CIImage *) currentImage
{
    return _ciimage;
}

-(CVImageBufferRef) getCurrentFrame
{
    @synchronized(self) {

        if (self.currentFrame)
        {
            CVPixelBufferRetain(self.currentFrame);
            
        }
    }
    
    
    return self.currentFrame;
}


-(void)chooseDirectory
{
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    
    [openPanel setCanChooseDirectories:YES];
    [openPanel setCanChooseFiles:YES];
    [openPanel setAllowsMultipleSelection:NO];
    
    if ([openPanel runModal] == NSOKButton)
    {
        NSArray *directories = [openPanel URLs];
        NSURL *dirUrl = [directories objectAtIndex:0];
        if (dirUrl)
        {
            self.imageDirectory = [dirUrl path];
        }
    }
}
@end
