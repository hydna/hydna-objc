//
//  ChannelSignal.m
//  hydna-objc
//

#import "HYChannelSignal.h"


@implementation HYChannelSignal

- (id)initWithType:(NSInteger)type
             ctype:(NSUInteger)ctype
           content:(NSData *)content
{
    if (!(self = [super init])) {
        return nil;
    }
    
    self->m_type = type;
    self->m_content = content;
    self->m_binary = (ctype == CTYPE_UTF8) ? NO : YES;
    
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

@synthesize m_type;
@synthesize m_content;

@end
