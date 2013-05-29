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
    
    self->m_priority = (priority >> 1);
    self->m_binary = (priority & 1) == 1 ? NO : YES;
    self->m_content = content;
    
    return self;
}

- (BOOL) isBinaryContent
{
    return self->m_binary;
}

- (BOOL) isUtf8Content
{
    return !self->m_binary;
}

@synthesize m_priority;
@synthesize m_content;
@synthesize m_binary;

@end
