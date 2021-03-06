//
//  CSPreviewRendererLayer.h
//  CocoaSplit
//
//  Created by Zakk on 12/27/18.
//

#ifndef CSPreviewRendererLayer_h
#define CSPreviewRendererLayer_h
#import "LayoutRenderer.h"

@protocol CSPreviewRendererLayer
@property (strong) LayoutRenderer *renderer;
@property (assign) bool doRender;
@property (assign) bool midiActive;
@property (assign) bool resizeDirty;
@property (assign) bool doDisplay;

@property (assign) float measuredFrameRate;
@property (assign) float minRenderTime;
@property (assign) float maxRenderTime;
@property (assign) float avgRenderTime;


-(NSPoint)realPointforWindowPoint:(NSPoint)winPoint;
-(NSRect)windowRectforWorldRect:(NSRect)worldRect;
-(void)renderIfNeeded;

@end


#endif /* CSPreviewRendererLayer_h */
