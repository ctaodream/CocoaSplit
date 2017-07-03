//
//  CSTransitionAnimationDelegate.m
//  CocoaSplit
//
//  Created by Zakk on 4/16/17.
//  Copyright © 2017 Zakk. All rights reserved.
//

#import "CSTransitionAnimationDelegate.h"
#import "InputSource.h"

@implementation CSTransitionAnimationDelegate

-(void)animationDidStart:(CAAnimation *)anim
{
    NSLog(@"DELEGATE ANIMATION STARTED");
    
    if (self.fullScreen)
    {
        [self.forLayout.rootLayer addAnimation:self.useAnimation forKey:nil];
    }

    for (InputSource *nSrc in self.addedInputs)
    {
        if (self.useAnimation && !self.fullScreen)
        {
            [nSrc.layer addAnimation:self.useAnimation forKey:nil];
        }
        nSrc.layer.hidden = NO;

    }
    
    for (InputSource *cSrc in self.changedInputs)
    {
        if (self.useAnimation && !self.fullScreen)
        {
            [cSrc.layer addAnimation:self.useAnimation forKey:nil];
        }
        cSrc.layer.hidden = NO;

    }
    
    for (InputSource *cSrc in self.changeremoveInputs)
    {
        if (self.useAnimation && !self.fullScreen)
        {
            [cSrc.layer addAnimation:self.useAnimation forKey:nil];
        }
        cSrc.layer.hidden = YES;
        
    }
    
    for (InputSource *rSrc in self.removedInputs)
    {
        if (self.useAnimation && !self.fullScreen)
        {
            [rSrc.layer addAnimation:self.useAnimation forKey:nil];
        }
        rSrc.layer.hidden = YES;
    }

}


-(void)animationDidStop:(CAAnimation *)anim finished:(BOOL)flag
{
    NSLog(@"DELEGATE ANIMATION STOPPED");
}
@end