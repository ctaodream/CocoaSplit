//
//  CSTransitionBase.m
//  CocoaSplit
//
//  Created by Zakk on 3/16/18.
//

#import "CSTransitionBase.h"
#import "CaptureController.h"

@implementation CSTransitionBase

@synthesize duration = _duration;

-(instancetype)init
{
    if (self = [super init])
    {
        self.uuid = [NSUUID UUID].UUIDString;
    }
    
    return self;
}


-(void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:_name forKey:@"name"];
    [aCoder encodeObject:self.uuid forKey:@"uuid"];
    [aCoder encodeObject:self.subType forKey:@"subType"];
    [aCoder encodeBool:self.active forKey:@"active"];
    [aCoder encodeObject:_duration forKey:@"duration"];
}


-(instancetype)initWithCoder:(NSCoder *)aDecoder
{
    if (self = [self init])
    {
        _name = [aDecoder decodeObjectForKey:@"name"];
        self.uuid = [aDecoder decodeObjectForKey:@"uuid"];
        self.subType = [aDecoder decodeObjectForKey:@"subType"];
        self.active = [aDecoder decodeBoolForKey:@"active"];
        _duration = [aDecoder decodeObjectForKey:@"duration"];
    }
    return self;
}



-(id)copyWithZone:(NSZone *)zone
{
    CSTransitionBase *newObj = [[self.class alloc] init];
    newObj.duration = _duration;
    newObj.name = _name;
    newObj.subType = self.subType;
    return newObj;
}


-(void)setDuration:(NSNumber *)duration
{
    _duration = duration;
}

-(NSNumber *)duration
{
    
    if (_duration)
    {
        return _duration;
    }
    
    return CaptureController.sharedCaptureController.transitionDuration;
}

-(void)setName:(NSString *)name
{
    _name = name;
}

-(NSString *)name
{
    return _name;
}


+(NSString *)transitionCategory
{
    return @"Unknown";
}


+(NSArray *)subTypes
{
    return @[];
}

-(NSString *)preChangeAction:(SourceLayout *)targetLayout
{
    return nil;
}

-(NSString *)postChangeAction:(SourceLayout *)targetLayout
{
    return nil;
}

-(NSString *)preReplaceAction:(SourceLayout *)targetLayout
{
    return [self preChangeAction:targetLayout];
}

-(NSString *)postReplaceAction:(SourceLayout *)targetLayout
{
    return [self postChangeAction:targetLayout];
}


-(NSString *)preMergeAction:(SourceLayout *)targetLayout
{
    return [self preChangeAction:targetLayout];
}
-(NSString *)postMergeAction:(SourceLayout *)targetLayout
{
    return [self postChangeAction:targetLayout];
}

-(NSString *)preRemoveAction:(SourceLayout *)targetLayout
{
    return [self preChangeAction:targetLayout];
}

-(NSString *)postRemoveAction:(SourceLayout *)targetLayout
{
    return [self postChangeAction:targetLayout];
}

-(NSViewController<CSLayoutTransitionViewProtocol> *)configurationViewController
{
    return nil;
}

-(bool)skipMergeAction:(SourceLayout *)targetLayout
{
    return NO;
}

-(bool)usesPreTransitions
{
    return NO;
}

-(bool)usesPostTransitions
{
    return NO;
}

@end
