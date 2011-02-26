//
//  StreamSignal.m
//  hydna-objc
//

#import "StreamSignal.h"


@implementation StreamSignal

- (id) initWithType:(NSInteger)type content:(NSData*)content
{
    if (!(self = [super init])) {
        return nil;
    }
    
    self->m_type = type;
    self->m_content = content;
    
    return self;
}

@synthesize m_type;
@synthesize m_content;

@end
