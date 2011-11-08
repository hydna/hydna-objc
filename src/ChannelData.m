//
//  ChannelData.m
//  hydna-objc
//

#import "ChannelData.h"


@implementation ChannelData

- (id) initWithPriority:(NSInteger)priority content:(NSData*)content
{
    if (!(self = [super init])) {
        return nil;
    }
    
    self->m_priority = priority;
    self->m_content = content;
    
    return self;
}

@synthesize m_priority;
@synthesize m_content;

@end
