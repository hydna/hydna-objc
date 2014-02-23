//
//  Connection.m
//  hydna-objc
//

#import "HYConnection.h"
#import "HYChannel.h"
#import "HYChannelError.h"
#import "HYURL.h"

#ifdef HYDNADEBUG
#import "DebugHelper.h"
#endif

#import <netinet/tcp.h>
#import <netinet/in.h>
#import <arpa/inet.h>

#import "HYHost.h"

static NSLock *m_connectionMutex;
static NSMutableDictionary *m_availableConnections = nil;
static BOOL m_followRedirects = YES;
const unsigned int MAX_REDIRECT_ATTEMPTS = 5;

@interface HYConnection ()

@property (atomic) BOOL m_connecting;
@property (atomic) BOOL m_connected;
@property (atomic) BOOL m_handshaked;
@property (atomic) BOOL m_destroying;
@property (atomic) BOOL m_closing;
@property (atomic) BOOL m_listening;
@property (atomic) BOOL m_resolved; // new

@property (atomic) NSUInteger m_port;
@property (atomic) NSInteger m_connectionFDS;
@property (atomic) NSUInteger m_attempt;
@property (atomic, strong) NSString *m_host;
@property (atomic, strong) NSString *m_auth;
@property (atomic) NSInteger m_channelRefCount;

@property (atomic, strong) NSMutableDictionary *m_pendingOpenRequests;
@property (atomic, strong) NSMutableDictionary *m_pendingResolveRequests;
@property (atomic, strong) NSMutableDictionary *m_openChannels;
@property (atomic, strong) NSMutableDictionary *m_openWaitQueue;
@property (atomic, strong) NSMutableDictionary *m_resolveWaitQueue;;

@property (atomic, strong) NSLock *m_channelRefMutex;
@property (nonatomic, strong) NSLock *m_destroyingMutex;
@property (atomic, strong) NSLock *m_closingMutex;
@property (atomic, strong) NSLock *m_openChannelsMutex;
@property (atomic, strong) NSLock *m_openWaitMutex;
@property (atomic, strong) NSLock *m_pendingMutex;
@property (atomic, strong) NSLock *m_resolveMutex; // new
@property (atomic, strong) NSLock *m_resolveWaitMutex; // new
@property (atomic, strong) NSLock *m_resolveChannelsMutex; // new
@property (atomic, strong) NSLock *m_listeningMutex;

/**
 *  Check if there are any more references to the connection.
 */
- (void)checkRefCount;

/**
 *  Connect the connection.
 *
 *  @param host The host to connect to.
 *  @param port The port to connect to.
 */
- (void)connectConnectionWithHost:(NSString *)host
                             port:(NSUInteger)port
                             auth:(NSString *)auth;

/**
 *  Send HTTP upgrade request.
 */
- (void)connectHandler:(NSString *)auth;

/**
 *  Handle the Handshake response frame.
 */
- (void)handshakeHandler;

/**
 *  Handles all incomming data.
 */
- (void)receiveHandler;

/**
 *  Process a resolve frame.
 *
 *  @param ch The channel that should receive the resolve frame.
 *  @param errcode The error code of the resolve frame.
 *  @param payload The content of the resolve frame.
 */
- (void)processResolveFrameWithChannelId:(NSUInteger)ch
                                 errcode:(NSInteger)errcode
                                 payload:(NSData *)payload;

/**
 *  Process an open frame.
 *
 *  @param ch The channel that should receive the open frame.
 *  @param errcode The error code of the open frame.
 *  @param payload The content of the open frame.
 */
- (void)processOpenFrameWithChannelId:(NSUInteger)ch
                              errcode:(NSInteger)errcode
                              payload:(NSData *)payload;

/**
 *  Process a data frame.
 *
 *  @param ch The channel that should receive the data.
 *  @param priority The priority of the data.
 *  @param payload The content of the data.
 */
- (void)processDataFrameWithChannelId:(NSUInteger)ch
                                ctype:(NSUInteger)ctype
                             priority:(NSInteger)priority
                              payload:(NSData *)payload;

/**
 *  Process a signal frame.
 *
 *  @param channel The channel that should receive the signal.
 *  @param flag The flag of the signal.
 *  @param payload The content of the signal.
 *  @return NO is something went wrong.
 */
- (BOOL)processSignalFrameWithChannel:(HYChannel *)channel
                                ctype:(NSUInteger)ctype
                                 flag:(NSInteger)flag
                              payload:(NSData *)payload;

/**
 *  Process a signal frame.
 *
 *  @param ch The channel that should receive the signal.
 *  @param flag The flag of the signal.
 *  @param payload The content of the signal.
 */
- (void)processSignalFrameWithChannelId:(NSUInteger)ch
                                  ctype:(NSUInteger)ctype
                                   flag:(NSInteger)flag
                                payload:(NSData *)payload;

/**
 *  Destroy the connection.
 *
 *  @error The cause of the destroy.
 */
- (void)destroy:(HYChannelError *)error;

/**
 * The method that is called in the new thread.
 * Listens for incoming frames.
 *
 * @param param An object with arguments.
 */
- (void)listen:(id)param;

@end

@implementation HYConnection

+ (HYConnection *)getConnectionWithHost:(NSString *)host
                                 port:(NSUInteger)port
                                 auth:(NSString *)auth
{
    if (!m_connectionMutex) {
        m_connectionMutex = [[NSLock alloc] init];
    }
    
    [m_connectionMutex lock];
    if (!m_availableConnections) {
        m_availableConnections = [[NSMutableDictionary alloc] init];
    }
    
    NSString *key = [host stringByAppendingFormat:@"%d%@", port, auth];
    HYConnection *connection = [m_availableConnections objectForKey:key];
    
    if (!connection) {
        connection = [[HYConnection alloc] initWithHost:host port:port auth:auth];
        [m_availableConnections setObject:connection forKey:key];
    }
    
    [m_connectionMutex unlock];
    
    return connection;
}

+ (BOOL)getFollowRedirects
{
    return m_followRedirects;
}

+ (void)setFollowRedirects:(BOOL)value
{
    m_followRedirects = value;
}

- (id)initWithHost:(NSString *)host
              port:(NSUInteger)port
              auth:(NSString *)auth
{
    if (!(self = [super init])) {
        return nil;
    }
    
    self.m_channelRefMutex = [[NSLock alloc] init];
    self.m_destroyingMutex = [[NSLock alloc] init];
    self.m_closingMutex = [[NSLock alloc ] init];
    self.m_openChannelsMutex = [[NSLock alloc ] init];
    self.m_openWaitMutex = [[NSLock alloc ] init];
    self.m_pendingMutex = [[NSLock alloc ] init];
    self.m_listeningMutex = [[NSLock alloc ] init];
    
    self.m_resolveMutex = [[NSLock alloc ] init];
    self.m_resolveWaitMutex = [[NSLock alloc ] init];
    self.m_resolveChannelsMutex = [[NSLock alloc ] init];
    
    self.m_connecting = NO;
    self.m_connected = NO;
    self.m_handshaked = NO;
    self.m_destroying = NO;
    self.m_closing = NO;
    self.m_listening = NO;
    self.m_resolved = NO;
    
    self.m_host = host;
    self.m_port = port;
    self.m_auth = auth;
    self.m_attempt = 0;
    
    self.m_pendingOpenRequests = [[NSMutableDictionary alloc ] init];
    self.m_pendingResolveRequests = [[NSMutableDictionary alloc ] init];
    self.m_openChannels = [[NSMutableDictionary alloc ] init];
    self.m_openWaitQueue = [[NSMutableDictionary alloc ] init];
    self.m_resolveWaitQueue = [[NSMutableDictionary alloc ] init];
    
    self.m_channelRefCount = 0;
    
    return self;
}

- (void)dealloc
{
    [self.m_channelRefMutex release];
    [self.m_destroyingMutex release];
    [self.m_closingMutex release];
    [self.m_openChannelsMutex release];
    [self.m_openWaitMutex release];
    [self.m_pendingMutex release];
    [self.m_listeningMutex release];
    
    [self.m_pendingOpenRequests release];
    [self.m_openChannels release];
    [self.m_openWaitQueue release];
    [self.m_pendingResolveRequests release];
    [self.m_resolveWaitQueue release];
    
    [self.m_resolveMutex release];
    [self.m_resolveWaitMutex release];
    [self.m_resolveChannelsMutex release];
    
    [super dealloc];
}

- (BOOL)hasHandshaked
{
    return self.m_handshaked;
}

- (void)allocChannel
{
    [self.m_channelRefMutex lock];
    ++self.m_channelRefCount;
    [self.m_channelRefMutex unlock];
#ifdef HYDNADEBUG
    debugPrint(@"Connection", 0, [NSString stringWithFormat:@"Allocating a new channel, channel ref count is %i", self.m_channelRefCount]);
#endif
}

- (void)deallocChannel:(NSUInteger)ch;
{
#ifdef HYDNADEBUG
    debugPrint(@"Connection", ch, @"Deallocating a channel");
#endif
    [self.m_destroyingMutex lock];
    [self.m_closingMutex lock];
    if (!self.m_destroying && !self.m_closing) {
        [self.m_closingMutex unlock];
        [self.m_destroyingMutex unlock];
        
        [self.m_openChannelsMutex lock];
        [self.m_openChannels removeObjectForKey:[NSNumber numberWithInteger:ch]];
#ifdef HYDNADEBUG
        debugPrint(@"Connection", ch, [NSString stringWithFormat:@"Size of openChannels is now %i", [self.m_openChannels count]]);
#endif
        [self.m_openChannelsMutex unlock];
    } else {
        [self.m_closingMutex unlock];
        [self.m_destroyingMutex unlock];
    }

    [self.m_channelRefMutex lock];
    --self.m_channelRefCount;
    [self.m_channelRefMutex unlock];
    
    [self checkRefCount];
}

- (void)checkRefCount
{
    [self.m_channelRefMutex lock];
    if (self.m_channelRefCount == 0) {
        [self.m_channelRefMutex unlock];
#ifdef HYDNADEBUG
        debugPrint(@"Connection", 0, @"No more refs, destroy connection");
#endif
        [self.m_destroyingMutex lock];
        [self.m_closingMutex lock];
        if (!self.m_destroying && !self.m_closing) {
            [self.m_closingMutex unlock];
            [self.m_destroyingMutex unlock];
            [self destroy:nil];
        } else {
            [self.m_closingMutex unlock];
            [self.m_destroyingMutex unlock];
        }
    } else {
        [self.m_channelRefMutex unlock];
    }
}

- (BOOL)requestResolve:(HYOpenRequest *)request
{
    NSString *path = request.path;
    
    NSMutableArray *queue;
    
    if (self.m_resolved) {
#ifdef HYDNADEBUG
        debugPrint(@"Connection", 0, @"The channel was already resolved, cancel the resolve request");
#endif
        [request release];
        return NO;
    }
    
    [self.m_resolveMutex lock];
    if ([self.m_pendingResolveRequests objectForKey:path] != nil) {
        [self.m_resolveMutex unlock];
        
#ifdef HYDNADEBUG
        debugPrint(@"Connection", 0, @"A resolve request is waiting to be sent, queue up the new open request");
#endif
        [self.m_resolveWaitMutex lock];
        queue = [self.m_resolveWaitQueue objectForKey:path];
        
        if (!queue) {
            queue = [[NSMutableArray alloc] init];
            [self.m_resolveWaitQueue setObject:queue forKey:path];
        }
        
        [queue addObject:request];
        [self.m_resolveWaitMutex unlock];
    } else if (!self.m_handshaked) {
#ifdef HYDNADEBUG
        debugPrint(@"Connection", 0, @"No connection, queue up the new resolve request");
#endif
        [self.m_pendingResolveRequests setObject:request forKey:path];
        [self.m_resolveMutex unlock];
        
        if (!self.m_connecting) {
            self.m_connecting = YES;
            [self connectConnectionWithHost:self.m_host port:self.m_port auth:self.m_auth];
        }
    } else {
        [self.m_pendingResolveRequests setObject:request forKey:path];
        [self.m_resolveMutex unlock];
        
#ifdef HYDNADEBUG
        debugPrint(@"Connection", 0, @"Already connected, sending the new resolve request");
#endif
        
        [self writeBytes:[request frame]];
        [request setSent:YES];
    }

    return self.m_connected;
}

- (BOOL)requestOpen:(HYOpenRequest *)request
{
    NSUInteger chcomp = [request ch];
    NSMutableArray *queue;
    
#ifdef HYDNADEBUG
    debugPrint(@"Connection", chcomp, @"A channel is trying to send a new open request");
#endif
    
    [self.m_openChannelsMutex lock];
    if ([self.m_openChannels objectForKey:[NSNumber numberWithInteger:chcomp]] != nil) {
        [self.m_openChannelsMutex unlock];
#ifdef HYDNADEBUG
        debugPrint(@"Connection", chcomp, @"The channel was already open, cancel the open request");
#endif
        [request release];
        return NO;
    }
    [self.m_openChannelsMutex unlock];
    
    [self.m_pendingMutex lock];
    if ([self.m_pendingOpenRequests objectForKey:[NSNumber numberWithInteger:chcomp]] != nil) {
        [self.m_pendingMutex unlock];
        
#ifdef HYDNADEBUG
        debugPrint(@"Connection", chcomp, @"A open request is waiting to be sent, queue up the new open request");
#endif
        [self.m_openWaitMutex lock];
        queue = [self.m_openWaitQueue objectForKey:[NSNumber numberWithInteger:chcomp]];
        
        if (!queue) {
            queue = [[NSMutableArray alloc] init];
            [self.m_openWaitQueue setObject:queue forKey:[NSNumber numberWithInteger:chcomp]];
        }
        
        [queue addObject:request];
        [self.m_openWaitMutex unlock];
    } else if (!self.m_handshaked) {
#ifdef HYDNADEBUG
        debugPrint(@"Connection", chcomp, @"No connection, queue up the new open request");
#endif
        [self.m_pendingOpenRequests setObject:request forKey:[NSNumber numberWithInteger:chcomp]];
        [self.m_pendingMutex unlock];
        
        if (!self.m_connecting) {
            self.m_connecting = YES;
            [self connectConnectionWithHost:self.m_host port:self.m_port auth:self.m_auth];
        }
    } else {
        [self.m_pendingOpenRequests setObject:request forKey:[NSNumber numberWithInteger:chcomp]];
        [self.m_pendingMutex unlock];
        
#ifdef HYDNADEBUG
        debugPrint(@"Connection", chcomp, @"Already connected, sending the new open request");
#endif
        [self writeBytes:[request frame]];
        [request setSent:YES];
    }

    return self.m_connected;
}


// TODO add cancel resolve

- (BOOL)cancelOpen:(HYOpenRequest *)request
{
    NSNumber *channelcomp = [NSNumber numberWithInteger:[request ch]];
    NSMutableArray *queue = nil;
    NSMutableArray *tmp = [[NSMutableArray alloc] init];
    BOOL found = NO;
    
    if ([request sent]) {
        return NO;
    }
    
    [self.m_openWaitMutex lock];
    queue = [self.m_openWaitQueue objectForKey:channelcomp];
    
    [self.m_pendingMutex lock];
    if ([self.m_pendingOpenRequests objectForKey:channelcomp] != nil) {
        [[self.m_pendingOpenRequests objectForKey:channelcomp] release];
        [self.m_pendingOpenRequests removeObjectForKey:channelcomp];
        
        if (queue && [queue count] > 0) {
            [self.m_pendingOpenRequests setObject:[queue objectAtIndex:0] forKey:channelcomp];
            [queue removeObjectAtIndex:0];
        }
        
        [self.m_pendingMutex unlock];
        [self.m_openWaitMutex unlock];
        return YES;
    }
    [self.m_pendingMutex unlock];
    
    // Should not happen...
    if (!queue) {
        [self.m_openWaitMutex unlock];
        return NO;
    }
    
    while ([queue count] != 0 && !found) {
        HYOpenRequest *r = [queue objectAtIndex:0];
        [queue removeObjectAtIndex:0];
        
        if (r == request) {
            [r release];
            found = YES;
        } else {
            [tmp addObject:r];
        }
    }
    
    while ([tmp count] != 0) {
        HYOpenRequest *r = [tmp objectAtIndex:0];
        [tmp removeObjectAtIndex:0];
        [queue addObject:r];
    }
    [self.m_openWaitMutex unlock];
    
    return found;
}

- (void)connectConnectionWithHost:(NSString *)host
                             port:(NSUInteger)port
                             auth:(NSString *)auth
{
    
    NSString *address = [HYHost addressForHostname:host];
    
    ++self.m_attempt;
    
#ifdef HYDNADEBUG
    debugPrint(@"Connection", 0, [NSString stringWithFormat:@"Connecting, attempt %i to address: %@", self.m_attempt, address]);
#endif
    
    if (address && ![address isEqualToString:@""]) {
        struct sockaddr_in server;
        
        if ((self.m_connectionFDS = socket(PF_INET, SOCK_STREAM, IPPROTO_TCP)) == -1) {
            [self destroy:[HYChannelError errorWithDesc:@"Connection could not be created" wasClean:NO hadError:YES wasDenied:NO]];
        } else {
            self.m_connected = YES;
            int flag = 1;
            
            if (setsockopt(self.m_connectionFDS, IPPROTO_TCP,
                           TCP_NODELAY, (char *) &flag,
                           sizeof(flag)) < 0) {
                NSLog(@"Connection: WARNING: Could not set TCP_NODELAY");
            }
            
            server.sin_addr.s_addr = inet_addr([address UTF8String]);
            server.sin_family = AF_INET;
            server.sin_port = htons(port);
            
            if (connect(self.m_connectionFDS, (struct sockaddr *)&server, sizeof(server)) == -1) {
                if (connect(self.m_connectionFDS, (struct sockaddr *)&server, sizeof(server)) == -1) {
                    [self destroy:[HYChannelError errorWithDesc:[ NSString stringWithFormat:@"Could not connect to the host \"%@\" on the port %i", host, port] wasClean:NO hadError:YES wasDenied:NO]];
                    
                } else {
                    [self connectHandler:auth];
                }
            } else {
#ifdef HYDNADEBUG
                debugPrint(@"Connection", 0, @"Connected, sending HTTP upgrade request");
#endif
                [self connectHandler:auth];
            }
        }

    } else {

        [self destroy:[HYChannelError errorWithDesc:[NSString stringWithFormat:@"The host \"%@\" could not be resolved", host] wasClean:NO hadError:YES wasDenied:NO]];
    }

}

- (void)connectHandler:(NSString *)auth
{
    const char *data;
    NSUInteger length;
    NSInteger n = -1;
    NSUInteger offset = 0;
    
    NSString *request = [NSString stringWithFormat:@"GET /%@ HTTP/1.1\r\n"
                        "Connection: upgrade\r\n"
                        "Upgrade: winksock/1\r\n"
                        "Host: %@\r\n"
                        "X-Follow-Redirects: ", auth, self.m_host];
    
    // Redirects are not supported yet
    if (m_followRedirects) {
        request = [request stringByAppendingFormat:@"yes"];
    } else {
        request = [request stringByAppendingFormat:@"no"];
    }
    
    // End of upgrade request
    request = [request stringByAppendingFormat:@"\r\n\r\n"];
    
    data = [request UTF8String];
    length = [request length];
        
    while (offset < length && n != 0) {
        n = write(self.m_connectionFDS, data + offset, length - offset);
        offset += n;
    }
    
    if (n <= 0) {
        [self destroy:[HYChannelError errorWithDesc:@"Could not send upgrade request" wasClean:NO hadError:YES wasDenied:NO]];
    } else {
        [self handshakeHandler];
    }
}

- (void)handshakeHandler
{
#ifdef HYDNADEBUG
    debugPrint(@"Connection", 0, @"Incoming upgrade response");
#endif
    
    char lf = '\n';
    char cr = '\r';
    BOOL fieldsLeft = YES;
    BOOL gotResponse = NO;
    BOOL gotRedirect = NO;
    NSString *location = @"";
    
    while (fieldsLeft) {
        NSMutableString *line = [NSMutableString stringWithCapacity:100];
        char c = ' ';
        
        while (c != lf) {
            read(self.m_connectionFDS, &c, 1);
            
            if (c != lf && c != cr) {
                [line appendFormat:@"%c", c];
            } else if ([ line length ] == 0) {
                fieldsLeft = NO;
            }
        }
        
        if (fieldsLeft) {
            // First line is a response, all others are fields
            if (!gotResponse) {
                NSInteger code = 0;
                NSRange pos;
                
                // Take the response code from "HTTP/1.1 101 Switching Protocols"
                pos = [line rangeOfString:@" "];
                if (pos.length != 0) {
                    NSString *line2 = [line substringFromIndex:pos.location + 1];
                    pos = [line2 rangeOfString:@" "];
                    
                    if (pos.length != 0) {
                        code = [[line2 substringToIndex:pos.location ] integerValue];
                    }
                }
                
                switch (code) {
                    case 101:
                        // Everything is ok, continue.
                        break;
                    case 300:
                    case 301:
                    case 302:
                    case 303:
                    case 304:
                        if (!m_followRedirects) {
                            [self destroy:[HYChannelError errorWithDesc:@"Bad handshake (HTTP-redirection disabled)" wasClean:NO hadError:YES wasDenied:NO]];
                            return;
                        }
                        
                        if (self.m_attempt > MAX_REDIRECT_ATTEMPTS) {
                            [self destroy:[HYChannelError errorWithDesc:@"Bad handshake (Too many redirect attempts)" wasClean:NO hadError:YES wasDenied:NO]];
                            return;
                        }
                        
                        gotRedirect = YES;
                        break;
                    default:
                        [self destroy:[HYChannelError errorWithDesc:[NSString stringWithFormat:@"Server responded with bad HTTP response code, %i", code] wasClean:NO hadError:YES wasDenied:NO]];
                        return;
                }
                
                gotResponse = YES;
                
            } else {
                NSString *lowline = [line lowercaseString];
                NSRange pos;
                
                if (gotRedirect) {
                    pos = [lowline rangeOfString:@"location: "];
                    if (pos.length != 0) {
                        location = [lowline substringFromIndex:pos.location + 10];
                    }
                } else {
                    pos = [lowline rangeOfString:@"upgrade: "];
                    if (pos.length != 0) {
                        NSString *header = [lowline substringFromIndex:pos.location + 9];
                    
                        if (![header isEqualToString:@"winksock/1"]) {
                            [self destroy:[HYChannelError errorWithDesc:[NSString stringWithFormat:@"Bad protocol version: %@", header] wasClean:NO hadError:YES wasDenied:NO]];
                            return;
                        }
                    }
                }
            }
        }
    }

    if (gotRedirect) {
        self.m_connected = NO;
        
#ifdef HYDNADEBUG
        debugPrint(@"Connection", 0, [NSString stringWithFormat:@"Redirected to location: %@", location]);
#endif
        HYURL *url = [[[HYURL alloc] initWithExpr:location] autorelease];
        
        if (![[url protocol] isEqualToString:@"http"]) {
            if ([[url protocol] isEqualToString:@"https"]) {
                [self destroy:[HYChannelError errorWithDesc:@"The protocol HTTPS is not supported" wasClean:NO hadError:YES wasDenied:NO]];
            } else {
                [self destroy:[HYChannelError errorWithDesc:[NSString stringWithFormat:@"Unknown protocol, \"%@\"", [url protocol]] wasClean:NO hadError:YES wasDenied:NO]];
            }
        }
        
        if (![[url error] isEqualToString:@""]) {
            [self destroy:[HYChannelError errorWithDesc:[NSString stringWithFormat:@"%@", [url error]] wasClean:NO hadError:YES wasDenied:NO]];
        }
        
        [self connectConnectionWithHost:[url host] port:[url port] auth:[url path]];
        return;
    }
    
    self.m_handshaked = YES;
    self.m_connecting = NO;
    
#ifdef HYDNADEBUG
    debugPrint(@"Connection", 0, @"Handshake done on connection");
#endif
    
    for (NSString *key in self.m_pendingResolveRequests) {
        HYOpenRequest *request = [self.m_pendingResolveRequests objectForKey:key];
        [ self writeBytes:[request frame]];
        
        if (self.m_connected) {
            [request setSent:YES];
#ifdef HYDNADEBUG
            debugPrint(@"Connection", [request ch], @"Resolve request sent");
#endif
        } else {
            return;
        }

    }
    
#ifdef HYDNADEBUG
    debugPrint(@"Connection", 0, @"Creating a new thread for frame listening");
#endif
    
    [NSThread detachNewThreadSelector:@selector(listen:) toTarget:self withObject:nil];

}

- (void)listen:(id)param
{
    [self receiveHandler];
}

- (void)receiveHandler
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    NSUInteger size;
    NSUInteger headerSize = HEADER_SIZE;
    NSUInteger ch;
    NSInteger op;
    NSInteger flag;
    NSInteger ctype;
    
    char header[headerSize];
    char *payload;
    
    NSUInteger offset = 0;
    NSInteger n = 1;
    
    [self.m_listeningMutex lock];
    self.m_listening = YES;
    [self.m_listeningMutex unlock];
    
    for (;;) {
        while (offset < headerSize + LENGTH_OFFSET && n > 0) {
            n = read(self.m_connectionFDS, header + offset, headerSize + LENGTH_OFFSET - offset);
            offset += n;
        }
        
        if (n <= 0) {
            [self.m_listeningMutex lock];
            if (self.m_listening) {
                [self.m_listeningMutex unlock];
                [self destroy:[HYChannelError errorWithDesc:@"Could not read from the connection" wasClean:NO hadError:YES wasDenied:NO]];
            } else {
                [self.m_listeningMutex unlock];
            }
            break;
        }
        
        size = ntohs(*(unsigned short*)&header[0]);
        payload = malloc((size - headerSize) * sizeof(char));
        
        while (offset < size + LENGTH_OFFSET && n > 0) {
            n = read(self.m_connectionFDS, payload + offset - (headerSize + LENGTH_OFFSET), (size + LENGTH_OFFSET) - offset);
            offset += n;
        }
        
        if (n <= 0) {
            [self.m_listeningMutex lock];
            if (self.m_listening) {
                [self.m_listeningMutex unlock];
                [self destroy:[HYChannelError errorWithDesc:@"Could not read from the connection" wasClean:NO hadError:YES wasDenied:NO]];
            } else {
                [self.m_listeningMutex unlock];
            }
            break;
        }
        
        ch = ntohl(*(unsigned int*)&header[2]);
        
        ctype = header[6] >> CTYPE_BITPOS;
        op = (header[6] >> OP_BITPOS) & OP_BITMASK;
        flag = header[6] & 7;
        
        NSData *data = [[NSData alloc] initWithBytesNoCopy:payload length:size - headerSize];
        
        switch (op) {
            case KEEPALIVE:
#ifdef HYDNADEBUG
                debugPrint(@"Connection", ch, @"Received heartbeat");
#endif
                break;    
            case OPEN:
#ifdef HYDNADEBUG
                debugPrint(@"Connection", ch, @"Received open response");
#endif
                [self processOpenFrameWithChannelId:ch errcode:flag payload:data];
                break;
                
            case DATA:
#ifdef HYDNADEBUG
                debugPrint(@"Connection", ch, @"Received data");
#endif
                [self processDataFrameWithChannelId:ch ctype:ctype priority:flag payload:data];
                break;
                
            case SIGNAL:
#ifdef HYDNADEBUG
                debugPrint(@"Connection", ch, @"Received signal");
#endif
                [self processSignalFrameWithChannelId:ch ctype:ctype flag:flag payload:data];
                break;
                
            case RESOLVE:
#ifdef HYDNADEBUG
                debugPrint(@"Connection", ch, @"Received resolve");
#endif          
                [self processResolveFrameWithChannelId:ch errcode:flag payload:data];
                break;
        }
        
        offset = 0;
        n = 1;
    }
#ifdef HYDNADEBUG
    debugPrint(@"Connection", 0, @"Listening thread exited");
#endif
    [pool release];
}

- (void)processResolveFrameWithChannelId:(NSUInteger)ch
                                 errcode:(NSInteger)errcode
                                 payload:(NSData *)payload
{
    
    if (errcode != 0) {
        [self destroy:[HYChannelError errorWithDesc:@"The server sent an invalid resolve frame" wasClean:NO hadError:YES wasDenied:NO]];
        return;
    }
    
    NSString *path = @"";
    
    if (payload && [payload length] > 0) {
        path = [[NSString alloc] initWithData:payload encoding:NSUTF8StringEncoding];
    }
    
    HYOpenRequest *request = nil;
    HYChannel* channel;
    
    [self.m_resolveMutex lock];
    
    request = [self.m_pendingResolveRequests objectForKey:path];
    
    [self.m_resolveMutex unlock];
    
    if (!request) {
        [self destroy:[HYChannelError errorWithDesc:@"The server sent an invalid resolve frame" wasClean:NO hadError:YES wasDenied:NO]];
        return;
    }
    
    channel = [request channel];
    
    if(request && channel){
        [channel resolveSuccess:ch path:path token:[request token]];
    }
    
    [self.m_resolveMutex lock];
    [request release];
    [self.m_pendingResolveRequests removeObjectForKey:path];
    [self.m_resolveMutex unlock];
}

- (void)processOpenFrameWithChannelId:(NSUInteger)ch
                              errcode:(NSInteger)errcode
                              payload:(NSData *)payload
{
    HYOpenRequest *request = nil;
    HYChannel *channel;
    NSUInteger respch = 0;
    NSString *message = @"";
    
    [self.m_pendingMutex lock];
    request = [self.m_pendingOpenRequests objectForKey:[NSNumber numberWithInteger:ch]];
    [self.m_pendingMutex unlock];
    
    if (!request) {
        [self destroy:[HYChannelError errorWithDesc:@"The server sent an invalid open frame" wasClean:NO hadError:YES wasDenied:NO]];
        return;
    }
    
    channel = [request channel];
    
    if (errcode == OPEN_ALLOW) {
        respch = ch;
        
        if ([payload length] > 0) {
            message = [[NSString alloc] initWithBytes:[payload bytes] length:[payload length] encoding:NSUTF8StringEncoding];
        }
    } else if (errcode == OPEN_REDIRECT) {
        if ([payload length] < 4) {
            [self destroy:[HYChannelError errorWithDesc:@"Expected redirect channel from the server" wasClean:NO hadError:YES wasDenied:NO]];
            return;
        }
        
        const char *data = [payload bytes];
        
        respch = ntohl(*(unsigned int*)&data[0]);
        
#ifdef HYDNADEBUG
        debugPrint(@"Connection",     ch, [NSString stringWithFormat:@"Redirected from %u", ch]);
        debugPrint(@"Connection", respch, [NSString stringWithFormat:@"             to %u", respch]);
#endif
        
        if ([payload length] > 4) {
            message = [[NSString alloc] initWithBytes:[payload bytes]+4 length:[payload length]-4 encoding:NSUTF8StringEncoding];
        }
    } else {
        [self.m_pendingMutex lock];
        [request release];
        
        [self.m_pendingOpenRequests removeObjectForKey:[NSNumber numberWithInteger:ch]];
        [self.m_pendingMutex unlock];

        const void *data = [payload bytes];
        NSString *m = @"";
        
        if ([payload length] > 0) {
            m = [[NSString alloc] initWithBytes:data length:[payload length] encoding:NSUTF8StringEncoding];
            [m autorelease];
        } else {
            m = @"";
        }

#ifdef HYDNADEBUG
        debugPrint(@"Connection", ch, [NSString stringWithFormat:@"The server rejected the open request, errorcode %i", errcode]);
#endif
        
        [channel destroy:[HYChannelError fromOpenError:errcode data:m]];
        
        return;
    }

    [self.m_openChannelsMutex lock];
    if ([self.m_openChannels objectForKey:[NSNumber numberWithInteger:respch]] != nil) {
        [self.m_openChannelsMutex unlock];
        [self destroy:[HYChannelError errorWithDesc:@"Server redirected to open channel" wasClean:NO hadError:YES wasDenied:NO]];
        return;
    }
    
    [self.m_openChannels setObject:channel forKey:[NSNumber numberWithInteger:respch]];
    
#ifdef HYDNADEBUG
    debugPrint(@"Connection", respch, @"A new channel was added");
    debugPrint(@"Connection", respch, [NSString stringWithFormat:@"The size of openChannel is now %i", [self.m_openChannels count]]);
#endif
    [self.m_openChannelsMutex unlock];
    
    [channel openSuccess:respch message:message];
    
    [self.m_openWaitMutex lock];
    [self.m_pendingMutex lock];
    NSMutableArray *queue = [self.m_openWaitQueue objectForKey:[NSNumber numberWithInteger:ch]];
    if (queue != nil) {
        // Destroy all pending request IF response wasn't a redirect channel.
        if (respch == ch) {
            [[self.m_pendingOpenRequests objectForKey:[NSNumber numberWithInteger:ch]] release];
            [self.m_pendingOpenRequests removeObjectForKey:[NSNumber numberWithInteger:ch]];
            
            while ([queue count] > 0) {
                request = [queue objectAtIndex:0];
                [queue removeObjectAtIndex:0];
                
                [[request channel] destroy:[HYChannelError errorWithDesc:@"Channel already open" wasClean:NO hadError:YES wasDenied:NO]];
            }
            
            return;
        }
        
        request = [queue objectAtIndex:0];
        [queue removeObjectAtIndex:0];
        [self.m_pendingOpenRequests setObject:request forKey:[NSNumber numberWithInteger:ch]];
        
        if ([queue count] == 0) {
            [[self.m_openWaitQueue objectForKey:[NSNumber numberWithInteger:ch]] release];
            [self.m_openWaitQueue removeObjectForKey:[ NSNumber numberWithInteger:ch]];
        }
        
        [self writeBytes:[request frame]];
        [request setSent:YES];
    } else {
        [[self.m_pendingOpenRequests objectForKey:[NSNumber numberWithInteger:ch]] release];
        [self.m_pendingOpenRequests removeObjectForKey:[NSNumber numberWithInteger:ch]];
    }
    [self.m_pendingMutex unlock];
    [self.m_openWaitMutex unlock];
}

- (void)processDataFrameWithChannelId:(NSUInteger)ch
                                ctype:(NSUInteger)ctype
                             priority:(NSInteger)priority
                              payload:(NSData *)payload
{
    
    [self.m_openChannelsMutex lock];
    HYChannel *channel = [self.m_openChannels objectForKey:[NSNumber numberWithInteger:ch]];
    [self.m_openChannelsMutex unlock];
    HYChannelData *data;
    
    if (!channel) {
        [self destroy:[HYChannelError errorWithDesc:@"No channel was available to take care of the data received" wasClean:NO hadError:YES wasDenied:NO] ];
        return;
    }
    
    if ([payload length] == 0) {
        [self destroy:[HYChannelError errorWithDesc:@"Zero data frame received" wasClean:NO hadError:YES wasDenied:NO]];
        return;
    }
    
    data = [[HYChannelData alloc] initWithPriority:priority content:payload ctype:ctype];
    [channel addData:data];
}

- (BOOL)processSignalFrameWithChannel:(HYChannel *)channel
                                ctype:(NSUInteger)ctype
                                 flag:(NSInteger)flag
                              payload:(NSData *)payload
{
    HYChannelSignal *signal;
    
    if (flag != SIG_EMIT) {
        NSString *m = @"";
        
        if ([payload length] > 0 && ctype == CTYPE_UTF8) {
            m = [[NSString alloc] initWithBytes:payload length:[payload length] encoding:NSUTF8StringEncoding];
        }
        
        [channel destroy:[HYChannelError fromSigError:flag data:m]];
        
        return NO;
    }
    
    if (!channel) {
        return NO;
    }
    
    signal = [[HYChannelSignal alloc] initWithType:flag ctype:ctype content:payload];
    [channel addSignal:signal];
    return YES;
}

- (void)processSignalFrameWithChannelId:(NSUInteger)ch
                                  ctype:(NSUInteger)ctype
                                   flag:(NSInteger)flag
                                payload:(NSData *)payload
{
    if (ch == 0) {
        BOOL destroying = NO;
        
        if (flag != SIG_EMIT || [payload length] == 0) {
            destroying = YES;
            
            [self.m_closingMutex lock];
            self.m_closing = YES;
            [self.m_closingMutex unlock];
        }
        
        [self.m_openChannelsMutex lock];
        for (NSNumber *key in [self.m_openChannels allKeys]) {
            HYChannel *channel = [self.m_openChannels objectForKey:key];
            NSData *payloadCopy = [[NSData alloc] initWithData:payload];
            
            if (!destroying && !channel) {
                destroying = YES;
                
                [self.m_closingMutex lock];
                self.m_closing = YES;
                [self.m_closingMutex unlock];
            }
            
            if (![self processSignalFrameWithChannel:channel ctype:ctype flag:flag payload:payloadCopy]) {
                [self.m_openChannels removeObjectForKey:key];
            }
        }
        [self.m_openChannelsMutex unlock];
        
        if (destroying) {
            [self.m_closingMutex lock];
            self.m_closing = NO;
            [self.m_closingMutex unlock];
            
            [self checkRefCount];
        }
    } else {
        [self.m_openChannelsMutex lock];
        HYChannel *channel = [self.m_openChannels objectForKey:[NSNumber numberWithInteger:ch]];
        [self.m_openChannelsMutex unlock];
        
        if (!channel) {
            [self destroy:[HYChannelError errorWithDesc:@"Frame sent to unknown channel" wasClean:NO hadError:YES wasDenied:NO]];
            return;
        }
        
        if (flag != SIG_EMIT && ![channel isClosing]) {
            
            HYFrame *frame = [[HYFrame alloc] initWithChannel:ch ctype:ctype op:SIGNAL flag:SIG_END payload:payload];
            
            @try {
                [self writeBytes:frame];
            }

            @catch (NSException *e) {
                [payload release];
                [self destroy:[HYChannelError errorWithDesc:[e reason] wasClean:NO hadError:YES wasDenied:NO]];
            }
            
            return;
        }
        
        [self processSignalFrameWithChannel:channel ctype:ctype flag:flag payload:payload];
    }

}

- (void)destroy:(HYChannelError *)error
{
    [self.m_destroyingMutex lock];
    self.m_destroying = YES;
    [self.m_destroyingMutex unlock];
    
#ifdef HYDNADEBUG
    if(error){
        debugPrint(@"Connection", 0, [NSString stringWithFormat:@"Destroying connection because: %@", error.reason]);
    }
#endif
    
    [self.m_resolveMutex lock];
#ifdef HYDNADEBUG
    debugPrint(@"Connection", 0, [NSString stringWithFormat:@"Destroying pendingResolveRequests of size %i", [self.m_pendingResolveRequests count]]);
#endif
    
    for (NSNumber *key in self.m_pendingResolveRequests) {
#ifdef HYDNADEBUG
        debugPrint(@"Connection", [key intValue], @"Destroying channel");
#endif
        HYOpenRequest *resolveReq = [self.m_pendingResolveRequests objectForKey:key];
        [resolveReq.channel destroy:error];
        [resolveReq release];
    }
    [self.m_pendingResolveRequests removeAllObjects];
    [self.m_resolveMutex unlock];
    
    
    [self.m_pendingMutex lock];
#ifdef HYDNADEBUG
    debugPrint(@"Connection", 0, [NSString stringWithFormat:@"Destroying pendingOpenRequests of size %i", [self.m_pendingOpenRequests count]]);
#endif
    
    for (NSNumber *key in self.m_pendingOpenRequests) {
#ifdef HYDNADEBUG
        debugPrint(@"Connection", [key intValue], @"Destroying channel");
#endif
        HYOpenRequest *openReq = [self.m_pendingOpenRequests objectForKey:key];
        [openReq.channel destroy:error];
        [openReq release];
    }
    [self.m_pendingOpenRequests removeAllObjects];
    [self.m_pendingMutex unlock];
    
    [self.m_openWaitMutex lock];
#ifdef HYDNADEBUG
    debugPrint(@"Connection", 0, [NSString stringWithFormat:@"Destroying openWaitQueue of size %i", [self.m_openWaitQueue count]]);
#endif
    
    for (NSNumber *key in self.m_openWaitQueue) {
        NSMutableArray *queue = [self.m_openWaitQueue objectForKey:key];
        
        while ([queue count] > 0) {
            
            HYOpenRequest *openWaitChannelReq = [queue objectAtIndex:0];
            [openWaitChannelReq.channel destroy:error];
            [queue removeObjectAtIndex:0];
        }
    }
    [self.m_openWaitQueue removeAllObjects];
    [self.m_openWaitMutex unlock];
    
    [self.m_openChannelsMutex lock];
#ifdef HYDNADEBUG
    debugPrint(@"Connection", 0, [NSString stringWithFormat:@"Destroying openChannels of size %i", [self.m_openChannels count]]);
#endif
    
    for (NSNumber *key in self.m_openChannels) {
#ifdef HYDNADEBUG
        debugPrint(@"Connection", [key intValue], @"Destroying channel");
#endif
        HYChannel *openChannel = [self.m_openChannels objectForKey:key];
        [openChannel destroy:error];
    }
    
    [self.m_openChannels removeAllObjects];
    [self.m_openChannelsMutex unlock];
    
    if (self.m_connected) {
#ifdef HYDNADEBUG
        debugPrint(@"Connection", 0, @"Closing connection");
#endif
        [self.m_listeningMutex lock];
        self.m_listening = NO;
        [self.m_listeningMutex unlock];
        
        close(self.m_connectionFDS);
        self.m_connected = NO;
        self.m_handshaked = NO;
    }
    
    NSString *key = [self.m_host stringByAppendingFormat:@"%d%@", self.m_port, self.m_auth];
    
    [m_connectionMutex lock];
    HYConnection *connection = [m_availableConnections objectForKey:key];
    
    if (connection) {
        // TODO: do a release here?
        [m_availableConnections removeObjectForKey:key];
    }
    [m_connectionMutex unlock];
    
#ifdef HYDNADEBUG
    debugPrint(@"Connection", 0, @"Destroying connection done");
#endif
    
    [self.m_destroyingMutex lock];
    self.m_destroying = NO;
    [self.m_destroyingMutex unlock];

}

- (BOOL)writeBytes:(HYFrame *)frame
{
    
    // TODO, add reset of hearbeat timeout
    
    if (self.m_handshaked) {
        NSInteger n = -1;
        NSInteger size = [ frame size ];
        const char* data = [ frame data ];
        NSInteger offset = 0;
        
        while (offset < size && n != 0) {
            n = write(self.m_connectionFDS, data + offset, size - offset);
            offset += n;
        }
        
        if (n <= 0) {
            [self destroy:[HYChannelError errorWithDesc:@"Could not write to the connection" wasClean:NO hadError:YES wasDenied:NO]];
            return NO;
        }
        return  YES;
    }
    return NO;
}

@end
