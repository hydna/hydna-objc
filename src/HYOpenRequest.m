//
//  OpenRequest.m
//  hydna-objc
//

#import "HYOpenRequest.h"
#import "HYChannel.h"

@implementation HYOpenRequest

@synthesize m_channel = _m_channel;
@synthesize m_ch = _m_ch;
@synthesize m_frame = _m_frame;
@synthesize m_sent = _m_sent;
@synthesize m_path = _m_path;
@synthesize m_token = _m_token;

- (id)initWith:(HYChannel *)channel
            ch:(NSUInteger)ch
          path:(NSString *)path
         token:(NSString *)token
         frame:(HYFrame *)frame
{
    if (!(self = [super init])) {
        return nil;
    }
    
    _m_path = path;
    _m_token = token;
    _m_channel = channel;
    _m_ch = ch;
    _m_frame = frame;
    _m_sent = NO;
    
    return self;
}



@end
