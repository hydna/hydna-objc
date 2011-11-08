//
//  OpenRequest.m
//  hydna-objc
//

#import "OpenRequest.h"
#import "Channel.h"

@implementation OpenRequest

- (id) initWith:(Channel*)channel ch:(NSUInteger)ch packet:(Packet*)packet
{
    if (!(self = [super init])) {
        return nil;
    }
    
    self->m_channel = channel;
    self->m_ch = ch;
    self->m_packet = packet;
    self->m_sent = NO;
    
    return self;
}

@synthesize m_channel;
@synthesize m_ch;
@synthesize m_packet;
@synthesize m_sent;

@end
