//
//  OpenRequest.m
//  hydna-objc
//

#import "OpenRequest.h"
#import "Channel.h"

@implementation OpenRequest

- (id) initWith:(Channel*)channel ch:(NSUInteger)ch path:(NSString*)path token:(NSString*)token frame:(Frame*)frame
{
    if (!(self = [super init])) {
        return nil;
    }
    
    self->m_path = path;
    self->m_token = token;
    self->m_channel = channel;
    self->m_ch = ch;
    self->m_frame = frame;
    self->m_sent = NO;
    
    return self;
}

@synthesize m_channel;
@synthesize m_ch;
@synthesize m_frame;
@synthesize m_sent;
@synthesize m_path;
@synthesize m_token;

@end
