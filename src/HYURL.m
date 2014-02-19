//
//  URL.m
//  hydna-objc
//

#import "HYURL.h"


@implementation HYURL

- (id)initWithExpr:(NSString *)expr
{
    if (!(self = [super init])) {
        return nil;
    }
    
    NSString *host = expr;
    NSUInteger port = 80;
    NSString *path = @"";
    NSString *tokens = @"";
    NSString *auth = @"";
    NSString *protocol = @"http";
    NSString *error = @"";
    NSRange pos;
    
    // Host can be on the form "http://auth@localhost:80/path?token"
    
    // Take out the protocol
    pos = [host rangeOfString:@"://"];
    if (pos.length != 0) {
        protocol = [host substringToIndex:pos.location];
        protocol = [protocol lowercaseString];
        host = [host substringFromIndex:pos.location + 3];
    }
    
    // Take out the auth
    pos = [host rangeOfString:@"@"];
    if (pos.length != 0) {
        auth = [host substringToIndex:pos.location];
        host = [host substringFromIndex:pos.location + 1];
    }
    
    // Take out the token
    pos = [host rangeOfString:@"?"];
    if (pos.length != 0) {
        tokens = [host substringFromIndex:pos.location + 1];
        host = [host substringToIndex:pos.location];
    }
    
    // Take out the path
    pos = [host rangeOfString:@"/"];
    if (pos.length != 0) {
        path = [host substringFromIndex:pos.location + 1];
        host = [host substringToIndex:pos.location];
    }
    
    // Take out the port
    pos = [host rangeOfString:@":"];
    if (pos.length != 0) {
        port = [[host substringFromIndex:pos.location + 1] integerValue];
        
        if (port == 0) {
            error = @"Could not read the port \"%i\"";
        }
        
        host = [host substringToIndex:pos.location];
    }
    
    self->m_path = path;
    self->m_token = tokens;
    self->m_host = host;
    self->m_port = port;
    self->m_auth = auth;
    self->m_protocol = protocol;
    self->m_error = error;
    
    return self;
}

@synthesize m_port;
@synthesize m_path;
@synthesize m_host;
@synthesize m_token;
@synthesize m_auth;
@synthesize m_protocol;
@synthesize m_error;

@end