//
//  OpenRequest.m
//  hydna-objc
//

#import "OpenRequest.h"
#import "Stream.h"

@implementation OpenRequest

- (id) initWith:(Stream*)stream ch:(NSUInteger)ch packet:(Packet*)packet
{
    if (!(self = [super init])) {
        return nil;
    }
    
    self->m_stream = stream;
    self->m_ch = ch;
    self->m_packet = packet;
    self->m_sent = NO;
    
    return self;
}

@synthesize m_stream;
@synthesize m_ch;
@synthesize m_packet;
@synthesize m_sent;

@end
