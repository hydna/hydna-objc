//
//  ChannelData.m
//  hydna-objc
//

#import "HYChannelData.h"


@implementation HYChannelData

@synthesize m_priority;
@synthesize m_content;
@synthesize m_binary;

- (id)initWithPriority:(NSInteger)priority
               content:(NSData*)content
                 ctype:(NSUInteger)ctype
{
    if (!(self = [super init])) {
        return nil;
    }
    
    self->m_priority = priority;
    self->m_binary = (ctype == CTYPE_UTF8) ? NO : YES;
    self->m_content = content;
    
    return self;
}

- (BOOL)isBinaryContent
{
    return self->m_binary;
}

- (BOOL)isUtf8Content
{
    return !self->m_binary;
}


@end