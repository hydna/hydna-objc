//
//  OpenRequest.m
//  hydna-objc
//

#import "OpenRequest.h"
#import "Stream.h"

@implementation OpenRequest

- (id) initWith:(Stream*)stream addr:(NSUInteger)addr packet:(Packet*)packet
{
    if (!(self = [super init])) {
        return nil;
    }
    
    self->m_stream = stream;
    self->m_addr = addr;
    self->m_packet = packet;
    self->m_sent = NO;
    
    return self;
}

@synthesize m_stream;
@synthesize m_addr;
@synthesize m_packet;
@synthesize m_sent;

@end
