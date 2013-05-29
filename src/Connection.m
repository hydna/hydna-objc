//
//  Connection.m
//  hydna-objc
//

#import "Connection.h"
#import "Channel.h"
#import "ChannelError.h"
#import "URL.h"

#ifdef HYDNADEBUG
#import "DebugHelper.h"
#endif

#import <netinet/tcp.h>
#import <netinet/in.h>
#import <arpa/inet.h>

static NSLock *m_connectionMutex;
static NSMutableDictionary *m_availableConnections = nil;
static BOOL m_followRedirects = YES;
const unsigned int MAX_REDIRECT_ATTEMPTS = 5;

@interface Connection ()

/**
 *  Check if there are any more references to the connection.
 */
- (void) checkRefCount;

/**
 *  Connect the connection.
 *
 *  @param host The host to connect to.
 *  @param port The port to connect to.
 */
- (void) connectConnectionWithHost:(NSString *)host port:(NSUInteger)port auth:(NSString*)auth;

/**
 *  Send HTTP upgrade request.
 */
- (void) connectHandler:(NSString*)auth;

/**
 *  Handle the Handshake response frame.
 */
- (void) handshakeHandler;

/**
 *  Handles all incomming data.
 */
- (void) receiveHandler;

/**
 *  Process an open frame.
 *
 *  @param ch The channel that should receive the open frame.
 *  @param errcode The error code of the open frame.
 *  @param payload The content of the open frame.
 */
- (void) processOpenFrameWithChannelId:(NSUInteger)ch errcode:(NSInteger)errcode payload:(NSData *)payload;

/**
 *  Process a data frame.
 *
 *  @param ch The channel that should receive the data.
 *  @param priority The priority of the data.
 *  @param payload The content of the data.
 */
- (void) processDataFrameWithChannelId:(NSUInteger)ch priority:(NSInteger)priority payload:(NSData *)payload;

/**
 *  Process a signal frame.
 *
 *  @param channel The channel that should receive the signal.
 *  @param flag The flag of the signal.
 *  @param payload The content of the signal.
 *  @return NO is something went wrong.
 */
- (BOOL) processSignalFrameWithChannel:(Channel *)channel flag:(NSInteger)flag payload:(NSData *)payload;

/**
 *  Process a signal frame.
 *
 *  @param ch The channel that should receive the signal.
 *  @param flag The flag of the signal.
 *  @param payload The content of the signal.
 */
- (void) processSignalFrameWithChannelId:(NSUInteger)ch flag:(NSInteger)flag payload:(NSData *)payload;

/**
 *  Destroy the connection.
 *
 *  @error The cause of the destroy.
 */
- (void) destroy:(NSString *)error;

/**
 * The method that is called in the new thread.
 * Listens for incoming frames.
 *
 * @param param An object with arguments.
 */
- (void) listen:(id)param;

@end

@implementation Connection

+ (id) getConnectionWithHost:(NSString*)host port:(NSUInteger)port auth:(NSString*)auth
{
    if (!m_connectionMutex) {
        m_connectionMutex = [[ NSLock alloc ] init ];
    }
    
    [ m_connectionMutex lock ];
    if (!m_availableConnections) {
        m_availableConnections = [[ NSMutableDictionary alloc ] init ];
    }
    
    NSString *key = [ host stringByAppendingFormat:@"%d%@", port, auth ];
    Connection *connection = [ m_availableConnections objectForKey:key ];
    
    if (!connection) {
        connection = [[ Connection alloc ] initWithHost:host port:port auth:auth ];
        [ m_availableConnections setObject:connection forKey:key ];
    }
    [ m_connectionMutex unlock ];
    
    return connection;
}

+ (BOOL) getFollowRedirects
{
	return m_followRedirects;
}

+ (void) setFollowRedirects:(BOOL)value
{
	m_followRedirects = value;
}

- (id) initWithHost:(NSString*)host port:(NSUInteger)port auth:(NSString*)auth
{
    if (!(self = [super init])) {
        return nil;
    }
    
    self->m_channelRefMutex = [[ NSLock alloc ] init ];
    self->m_destroyingMutex = [[ NSLock alloc ] init ];
    self->m_closingMutex = [[ NSLock alloc ] init ];
    self->m_openChannelsMutex = [[ NSLock alloc ] init ];
    self->m_openWaitMutex = [[ NSLock alloc ] init ];
    self->m_pendingMutex = [[ NSLock alloc ] init ];
    self->m_listeningMutex = [[ NSLock alloc ] init ];
    
    self->m_connecting = NO;
    self->m_connected = NO;
    self->m_handshaked = NO;
    self->m_destroying = NO;
    self->m_closing = NO;
    self->m_listening = NO;
    
    self->m_host = host;
    self->m_port = port;
	self->m_auth = auth;
	self->m_attempt = 0;
    
    self->m_pendingOpenRequests = [[ NSMutableDictionary alloc ] init ];
    self->m_openChannels = [[ NSMutableDictionary alloc ] init ];
    self->m_openWaitQueue = [[ NSMutableDictionary alloc ] init ];
    
    self->m_channelRefCount = 0;
    
    return self;
}

- (void) dealloc
{
    [ m_channelRefMutex release ];
    [ m_destroyingMutex release ];
    [ m_closingMutex release ];
    [ m_openChannelsMutex release ];
    [ m_openWaitMutex release ];
    [ m_pendingMutex release ];
    [ m_listeningMutex release ];
    
    [ m_pendingOpenRequests release ];
    [ m_openChannels release ];
    [ m_openWaitQueue release ];
    
    [ super dealloc ];
}

- (BOOL) hasHandshaked
{
    return m_handshaked;
}

- (void) allocChannel
{
    [ m_channelRefMutex lock ];
    ++m_channelRefCount;
    [ m_channelRefMutex unlock ];
#ifdef HYDNADEBUG
	debugPrint(@"Connection", 0, [NSString stringWithFormat:@"Allocating a new channel, channel ref count is %i", m_channelRefCount]);
#endif
}

- (void) deallocChannel:(NSUInteger)ch;
{
#ifdef HYDNADEBUG
	debugPrint(@"Connection", ch, @"Deallocating a channel");
#endif
    [ m_destroyingMutex lock ];
    [ m_closingMutex lock ];
    if (!m_destroying && !m_closing) {
        [ m_closingMutex unlock ];
        [ m_destroyingMutex unlock ];
        
        [ m_openChannelsMutex lock ];
        [ m_openChannels removeObjectForKey:[ NSNumber numberWithInteger:ch ] ];
#ifdef HYDNADEBUG
		debugPrint(@"Connection", ch, [NSString stringWithFormat:@"Size of openChannels is now %i", [ m_openChannels count ]]);
#endif
        [ m_openChannelsMutex unlock ];
    } else {
        [ m_closingMutex unlock ];
        [ m_destroyingMutex unlock ];
    }

    [ m_channelRefMutex lock ];
    --m_channelRefCount;
    [ m_channelRefMutex unlock ];
    
    [ self checkRefCount ];
}

- (void) checkRefCount
{
    [ m_channelRefMutex lock ];
    if (m_channelRefCount == 0) {
        [ m_channelRefMutex unlock ];
#ifdef HYDNADEBUG
		debugPrint(@"Connection", 0, @"No more refs, destroy connection");
#endif
        [ m_destroyingMutex lock ];
        [ m_closingMutex lock ];
        if (!m_destroying && !m_closing) {
            [ m_closingMutex unlock ];
            [ m_destroyingMutex unlock ];
            [ self destroy:@"" ];
        } else {
            [ m_closingMutex unlock ];
            [ m_destroyingMutex unlock ];
        }
    } else {
        [ m_channelRefMutex unlock ];
    }
}

- (BOOL) requestOpen:(OpenRequest*)request
{
    NSUInteger chcomp = [ request ch ];
    NSMutableArray *queue;
    
#ifdef HYDNADEBUG
	debugPrint(@"Connection", chcomp, @"A channel is trying to send a new open request");
#endif
    
    [ m_openChannelsMutex lock ];
    if ([ m_openChannels objectForKey:[ NSNumber numberWithInteger:chcomp ]] != nil) {
        [ m_openChannelsMutex unlock ];
#ifdef HYDNADEBUG
		debugPrint(@"Connection", chcomp, @"The channel was already open, cancel the open request");
#endif
        [ request release ];
        return NO;
    }
    [ m_openChannelsMutex unlock ];
    
    [ m_pendingMutex lock ];
    if ([ m_pendingOpenRequests objectForKey:[ NSNumber numberWithInteger:chcomp ]] != nil) {
        [ m_pendingMutex unlock ];
        
#ifdef HYDNADEBUG
		debugPrint(@"Connection", chcomp, @"A open request is waiting to be sent, queue up the new open request");
#endif
        [ m_openWaitMutex lock ];
        queue = [ m_openWaitQueue objectForKey:[ NSNumber numberWithInteger:chcomp ]];
        
        if (!queue) {
            queue = [[ NSMutableArray alloc ] init ];
            [ m_openWaitQueue setObject:queue forKey:[ NSNumber numberWithInteger:chcomp ]];
        }
        
        [ queue addObject:request ];
        [ m_openWaitMutex unlock ];
    } else if (!m_handshaked) {
#ifdef HYDNADEBUG
		debugPrint(@"Connection", chcomp, @"No connection, queue up the new open request");
#endif
        [ m_pendingOpenRequests setObject:request forKey:[ NSNumber numberWithInteger:chcomp ]];
        [ m_pendingMutex unlock ];
        
        if (!m_connecting) {
            m_connecting = YES;
            [ self connectConnectionWithHost:m_host port:m_port auth:m_auth ];
        }
    } else {
		[ m_pendingOpenRequests setObject:request forKey:[ NSNumber numberWithInteger:chcomp ]];
        [ m_pendingMutex unlock ];
        
#ifdef HYDNADEBUG
		debugPrint(@"Connection", chcomp, @"Already connected, sending the new open request");
#endif
        [ self writeBytes:[ request frame ]];
        [ request setSent:YES ];
    }

    return m_connected;
}

- (BOOL) cancelOpen:(OpenRequest*)request
{
    NSNumber *channelcomp = [ NSNumber numberWithInteger:[ request ch ]];
    NSMutableArray *queue = nil;
    NSMutableArray *tmp = [[ NSMutableArray alloc ] init ];
    BOOL found = NO;
    
    if ([ request sent ]) {
        return NO;
    }
    
    [ m_openWaitMutex lock ];
    queue = [ m_openWaitQueue objectForKey:channelcomp];
    
    [ m_pendingMutex lock ];
    if ([ m_pendingOpenRequests objectForKey:channelcomp ] != nil) {
        [[ m_pendingOpenRequests objectForKey:channelcomp ] release ];
        [ m_pendingOpenRequests removeObjectForKey:channelcomp ];
        
        if (queue && [ queue count ] > 0) {
            [ m_pendingOpenRequests setObject:[ queue objectAtIndex:0 ] forKey:channelcomp ];
            [ queue removeObjectAtIndex:0 ];
        }
        
        [ m_pendingMutex unlock ];
        [ m_openWaitMutex unlock ];
        return YES;
    }
    [ m_pendingMutex unlock ];
    
    // Should not happen...
    if (!queue) {
        [ m_openWaitMutex unlock ];
        return NO;
    }
    
    while ([ queue count ] != 0 && !found) {
        OpenRequest *r = [ queue objectAtIndex:0 ];
        [ queue removeObjectAtIndex:0 ];
        
        if (r == request) {
            [ r release ];
            found = YES;
        } else {
            [ tmp addObject:r ];
        }
    }
    
    while ([ tmp count ] != 0) {
        OpenRequest *r = [ tmp objectAtIndex:0 ];
        [ tmp removeObjectAtIndex:0 ];
        [ queue addObject:r ];
    }
    [ m_openWaitMutex unlock ];
    
    return found;
}

- (void) connectConnectionWithHost:(NSString*)host port:(NSUInteger)port auth:(NSString*)auth
{
    NSHost *nshost = [ NSHost hostWithName:host ];
    NSArray *addresses =  [ nshost addresses ];
    NSString *address = @"";
    
	++m_attempt;
	
#ifdef HYDNADEBUG
	debugPrint(@"Connection", 0, [ NSString stringWithFormat:@"Connecting, attempt %i", m_attempt]);
#endif
    
    for (NSString *a in addresses) {
        if ([[ a componentsSeparatedByString:@":"] count ] == 1) {
            address = a;
            break;
        }
    }
    
    if (![address isEqualToString:@""]) {
        struct sockaddr_in server;
        
        if ((m_connectionFDS = socket(PF_INET, SOCK_STREAM, IPPROTO_TCP)) == -1) {
            [ self destroy:@"Connection could not be created" ];
        } else {
            m_connected = YES;
            int flag = 1;
            
            if (setsockopt(m_connectionFDS, IPPROTO_TCP,
                           TCP_NODELAY, (char *) &flag,
                           sizeof(flag)) < 0) {
                NSLog(@"WARNING: Could not set TCP_NODELAY");
            }
            
            
            server.sin_addr.s_addr = inet_addr([address UTF8String ]);
            server.sin_family = AF_INET;
            server.sin_port = htons(port);
            
            if (connect(m_connectionFDS, (struct sockaddr *)&server, sizeof(server)) == -1) {
                if (connect(m_connectionFDS, (struct sockaddr *)&server, sizeof(server)) == -1) {
                    [ self destroy:[ NSString stringWithFormat:@"Could not connect to the host \"%@\" on the port %i", host, port ]];
                } else {
                    [ self connectHandler:auth ];
                }
            } else {
#ifdef HYDNADEBUG
				debugPrint(@"Connection", 0, @"Connected, sending HTTP upgrade request");
#endif
                [ self connectHandler:auth ];
            }
        }

    } else {
        [ self destroy:[ NSString stringWithFormat:@"The host \"%@\" could not be resolved", host ]];  
    }

}

- (void) connectHandler:(NSString*)auth
{
    const char *data;
    NSUInteger length;
    NSInteger n = -1;
    NSUInteger offset = 0;
    
	NSString *request = [ NSString stringWithFormat:@"GET /%@ HTTP/1.1\r\n"
						"Connection: upgrade\r\n"
						"Upgrade: winksock/1\r\n"
						"Host: %@\r\n"
						"X-Follow-Redirects: ", auth, m_host ];
	
	// Redirects are not supported yet
	if (m_followRedirects) {
		request = [ request stringByAppendingFormat:@"yes" ];
	} else {
		request = [ request stringByAppendingFormat:@"no" ];
	}
	
	// End of upgrade request
	request = [ request stringByAppendingFormat:@"\r\n\r\n" ];
	
	data = [ request UTF8String ];
	length = [ request length ];
        
    while (offset < length && n != 0) {
        n = write(m_connectionFDS, data + offset, length - offset);
        offset += n;
    }
    
    if (n <= 0) {
        [ self destroy:@"Could not send upgrade request" ];
    } else {
        [ self handshakeHandler ];
    }
}

- (void) handshakeHandler
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
			read(m_connectionFDS, &c, 1);
			
			if (c != lf && c != cr) {
				[ line appendFormat:@"%c", c ];
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
				pos = [ line rangeOfString:@" " ];
				if (pos.length != 0) {
					NSString *line2 = [ line substringFromIndex:pos.location + 1 ];
					pos = [ line2 rangeOfString:@" " ];
					
					if (pos.length != 0) {
						code = [[ line2 substringToIndex:pos.location ] integerValue ];
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
							[ self destroy:@"Bad handshake (HTTP-redirection disabled)" ];
							return;
						}
						
						if (m_attempt > MAX_REDIRECT_ATTEMPTS) {
							[ self destroy:@"Bad handshake (Too many redirect attempts)" ];
							return;
						}
						
						gotRedirect = YES;
						break;
					default:
						[ self destroy:[ NSString stringWithFormat:@"Server responded with bad HTTP response code, %i", code ] ];
						return;
				}
				
				gotResponse = YES;
			} else {
				NSString *lowline = [ line lowercaseString ];
				NSRange pos;
				
				if (gotRedirect) {
					pos = [ lowline rangeOfString:@"location: " ];
					if (pos.length != 0) {
						location = [ lowline substringFromIndex:pos.location + 10 ];
					}
				} else {
					pos = [ lowline rangeOfString:@"upgrade: " ];
					if (pos.length != 0) {
						NSString *header = [ lowline substringFromIndex:pos.location + 9 ];
					
						if (![ header isEqualToString:@"winksock/1" ]) {
							[ self destroy:[ NSString stringWithFormat:@"Bad protocol version: %@", header ] ];
							return;
						}
					}
				}
			}
		}
	}

	if (gotRedirect) {
		m_connected = NO;
		
#ifdef HYDNADEBUG
		debugPrint(@"Connection", 0, [ NSString stringWithFormat:@"Redirected to location: %@", location]);
#endif
		URL *url = [[[ URL alloc ] initWithExpr:location ] autorelease ];
		
		if (![[ url protocol ] isEqualToString:@"http" ]) {
			if ([[ url protocol ] isEqualToString:@"https" ]) {
				[ self destroy:@"The protocol HTTPS is not supported" ];
			} else {
				[ self destroy:[ NSString stringWithFormat:@"Unknown protocol, \"%@\"", [ url protocol ]]];
			}
		}
		
		if (![[ url error ] isEqualToString:@"" ]) {
			[ self destroy:[ NSString stringWithFormat:@"%@", [ url error ]]];
		}
		
		[ self connectConnectionWithHost:[ url host ] port:[ url port ] auth:[ url path ]];
		return;
	}
    
    m_handshaked = YES;
    m_connecting = NO;
    
#ifdef HYDNADEBUG
	debugPrint(@"Connection", 0, @"Handshake done on connection");
#endif
    
    for (NSString *key in m_pendingOpenRequests) {
        OpenRequest *request = [ m_pendingOpenRequests objectForKey:key ];
        [ self writeBytes:[ request frame ]];
        
        if (m_connected) {
            [ request setSent:YES ];
#ifdef HYDNADEBUG
			debugPrint(@"Connection", [ request ch ], @"Open request sent");
#endif
        } else {
            return;
        }

    }
    
#ifdef HYDNADEBUG
	debugPrint(@"Connection", 0, @"Creating a new thread for frame listening");
#endif
    
    [NSThread detachNewThreadSelector:@selector(listen:) toTarget:self withObject:nil];
    
    /*
    if (!created) {
        [ self destroy:@"Could not create a new thread for frame listening" ];
        return;
    }
    */
}

- (void) listen:(id)param
{
    [ self receiveHandler ];
}

- (void) receiveHandler
{
    NSAutoreleasePool *pool = [[ NSAutoreleasePool alloc ] init ];
    
    NSUInteger size;
    NSUInteger headerSize = HEADER_SIZE;
    NSUInteger ch;
    NSInteger op;
    NSInteger flag;
    
    char header[headerSize];
    char* payload;
    
    NSUInteger offset = 0;
    NSInteger n = 1;
    
    [ m_listeningMutex lock ];
    m_listening = YES;
    [ m_listeningMutex unlock ];
    
    for (;;) {
        while (offset < headerSize && n > 0) {
            n = read(m_connectionFDS, header + offset, headerSize - offset);
            offset += n;
        }
        
        if (n <= 0) {
            [ m_listeningMutex lock ];
            if (m_listening) {
                [ m_listeningMutex unlock ];
                [ self destroy:@"Could not read from the connection" ];
            } else {
				[ m_listeningMutex unlock ];
			}
            break;
        }
        
        size = ntohs(*(unsigned short*)&header[0]);
        payload = malloc((size - headerSize) * sizeof(char));
		
        while (offset < size && n > 0) {
            n = read(m_connectionFDS, payload + offset - headerSize, size - offset);
            offset += n;
        }
        
        if (n <= 0) {
            [ m_listeningMutex lock ];
            if (m_listening) {
                [ m_listeningMutex unlock ];
                [ self destroy:@"Could not read from the connection" ];
            } else {
				[ m_listeningMutex unlock ];
			}
            break;
        }
        
        ch = ntohl(*(unsigned int*)&header[2]);
        op = header[6] >> 3 & 3;
        flag = header[6] & 7;
        
        NSData *data = [[ NSData alloc ] initWithBytesNoCopy:payload length:size - headerSize ];
        
        switch (op) {
            case OPEN:
#ifdef HYDNADEBUG
				debugPrint(@"Connection", ch, @"Received open response");
#endif
                [ self processOpenFrameWithChannelId:ch errcode:flag payload:data ];
                break;
                
            case DATA:
#ifdef HYDNADEBUG
				debugPrint(@"Connection", ch, @"Received data");
#endif
                [ self processDataFrameWithChannelId:ch priority:flag payload:data ];
                break;
                
            case SIGNAL:
#ifdef HYDNADEBUG
				debugPrint(@"Connection", ch, @"Received signal");
#endif
                [ self processSignalFrameWithChannelId:ch flag:flag payload:data ];
                break;
        }
        
        offset = 0;
        n = 1;
    }
#ifdef HYDNADEBUG
	debugPrint(@"Connection", 0, @"Listening thread exited");
#endif
    [ pool release ];
}

- (void) processOpenFrameWithChannelId:(NSUInteger)ch errcode:(NSInteger)errcode payload:(NSData*)payload
{
    OpenRequest *request = nil;
    Channel *channel;
    NSUInteger respch = 0;
	NSString *message = @"";
    
    [ m_pendingMutex lock ];
    request = [ m_pendingOpenRequests objectForKey:[ NSNumber numberWithInteger:ch ]];
    [ m_pendingMutex unlock ];
    
    if (!request) {
        [ self destroy:@"The server sent an invalid open frame" ];
        return;
    }
    
    channel = [ request channel ];
    
    if (errcode == OPEN_ALLOW) {
        respch = ch;
		
		if ([ payload length ] > 0) {
			message = [[ NSString alloc ] initWithBytes:[ payload bytes ] length:[ payload length ] encoding:NSUTF8StringEncoding ];
		}
    } else if (errcode == OPEN_REDIRECT) {
        if ([ payload length ] < 4) {
            [ self destroy:@"Expected redirect channel from the server" ];
            return;
        }
        
        const char *data = [ payload bytes ];
        
        respch = ntohl(*(unsigned int*)&data[0]);
        
#ifdef HYDNADEBUG
		debugPrint(@"Connection",     ch, [ NSString stringWithFormat:@"Redirected from %u", ch]);
		debugPrint(@"Connection", respch, [ NSString stringWithFormat:@"             to %u", respch ]);
#endif
		
		if ([ payload length ] > 4) {
			message = [[ NSString alloc ] initWithBytes:[ payload bytes ]+4 length:[ payload length ]-4 encoding:NSUTF8StringEncoding ];
		}
    } else {
        [ m_pendingMutex lock ];
        [ request release ];
        [ m_pendingOpenRequests removeObjectForKey:[ NSNumber numberWithInteger:ch ]];
        [ m_pendingMutex unlock ];

        const void *data = [ payload bytes ];
        NSString *m = @"";
        
        if ([ payload length ] > 0) {
            m = [ [NSString alloc ] initWithBytes:data length:[ payload length ] encoding:NSUTF8StringEncoding ];
            [ m autorelease ];
        } else {
            m = @"";
        }

#ifdef HYDNADEBUG
		debugPrint(@"Connection", ch, [ NSString stringWithFormat:@"The server rejected the open request, errorcode %i", errcode ]);
#endif
        [ channel destroy:[ ChannelError fromOpenError:errcode data:m ]];
        return;
    }

    [ m_openChannelsMutex lock ];
    if ([ m_openChannels objectForKey:[ NSNumber numberWithInteger:respch ]] != nil) {
        [ m_openChannelsMutex unlock ];
        [ self destroy:@"Server redirected to  open channel" ];
        return;
    }
    
    [ m_openChannels setObject:channel forKey:[ NSNumber numberWithInteger:respch ]];
    
#ifdef HYDNADEBUG
	debugPrint(@"Connection", respch, @"A new channel was added");
	debugPrint(@"Connection", respch, [ NSString stringWithFormat:@"The size of openChannel is now %i", [ m_openChannels count ]]);
#endif
    [ m_openChannelsMutex unlock ];
    
    [ channel openSuccess:respch message:message ];
    
    [ m_openWaitMutex lock ];
    [ m_pendingMutex lock ];
    NSMutableArray *queue = [ m_openWaitQueue objectForKey:[ NSNumber numberWithInteger:ch ]];
    if (queue != nil) {
        // Destroy all pending request IF response wans't a redirect channel.
        if (respch == ch) {
            [[ m_pendingOpenRequests objectForKey:[ NSNumber numberWithInteger:ch ]] release ];
            [ m_pendingOpenRequests removeObjectForKey:[ NSNumber numberWithInteger:ch ]];
            
            while ([ queue count ] > 0) {
                request = [ queue objectAtIndex:0 ];
                [ queue removeObjectAtIndex:0 ];
                
                [[ request channel ] destroy:@"Channel already open" ];
            }
            
            return;
        }
        
        request = [ queue objectAtIndex:0 ];
        [ queue removeObjectAtIndex:0 ];
        [ m_pendingOpenRequests setObject:request forKey:[ NSNumber numberWithInteger:ch ]];
        
        if ([ queue count ] == 0) {
            [[ m_openWaitQueue objectForKey:[ NSNumber numberWithInteger:ch ]] release ];
            [ m_openWaitQueue removeObjectForKey:[ NSNumber numberWithInteger:ch ]];
        }
        
        [ self writeBytes:[ request frame ]];
        [ request setSent:YES ];
    } else {
        [[ m_pendingOpenRequests objectForKey:[ NSNumber numberWithInteger:ch ]] release ];
        [ m_pendingOpenRequests removeObjectForKey:[ NSNumber numberWithInteger:ch ]];
    }
    [ m_pendingMutex unlock ];
    [ m_openWaitMutex unlock ];
}

- (void) processDataFrameWithChannelId:(NSUInteger)ch priority:(NSInteger)priority payload:(NSData*)payload
{
    [ m_openChannelsMutex lock ];
    Channel *channel = [ m_openChannels objectForKey:[ NSNumber numberWithInteger:ch ]];
    [ m_openChannelsMutex unlock ];
    ChannelData *data;
    
    if (!channel) {
        [ self destroy:@"No channel was available to take care of the data received" ];
        return;
    }
    
    if ([ payload length ] == 0) {
        [ self destroy:@"Zero data frame received" ];
        return;
    }
    
    data = [[ ChannelData alloc ] initWithPriority:priority content:payload ];
    [ channel addData:data ];
}

- (BOOL) processSignalFrameWithChannel:(Channel*)channel flag:(NSInteger)flag payload:(NSData*)payload
{
    ChannelSignal *signal;
    
    if (flag != SIG_EMIT) {
        NSString *m = @"";
        
        if ([ payload length ] > 0) {
            m = [[ NSString alloc ] initWithBytes:payload length:[ payload length ] encoding:NSUTF8StringEncoding ];
        }
        
        if (flag != SIG_END) {
            [ channel destroy:[ ChannelError fromSigError:flag data:m ]];
        } else {
            [ channel destroy:@"" ];
        }
        return NO;
    }
    
    if (!channel) {
        return NO;
    }
    
    signal = [[ ChannelSignal alloc ] initWithType:flag content:payload];
    [ channel addSignal:signal ];
    return YES;
}

- (void) processSignalFrameWithChannelId:(NSUInteger)ch flag:(NSInteger)flag payload:(NSData*)payload
{
    if (ch == 0) {
        BOOL destroying = NO;
        
        if (flag != SIG_EMIT || [ payload length ] == 0) {
            destroying = YES;
            
            [ m_closingMutex lock ];
            m_closing = YES;
            [ m_closingMutex unlock ];
        }
        
        [ m_openChannelsMutex lock ];
        for (NSNumber *key in [ m_openChannels allKeys ]) {
            Channel* channel = [ m_openChannels objectForKey:key ];
            NSData *payloadCopy = [[ NSData alloc ] initWithData:payload ];
            
            if (!destroying && !channel) {
                destroying = YES;
                
                [ m_closingMutex lock ];
                m_closing = YES;
                [ m_closingMutex unlock ];
            }
            
            if (![ self processSignalFrameWithChannel:channel flag:flag payload:payloadCopy ]) {
                [ m_openChannels removeObjectForKey:key ];
            }
        }
        [ m_openChannelsMutex unlock ];
        
        if (destroying) {
            [ m_closingMutex lock ];
            m_closing = NO;
            [ m_closingMutex unlock ];
            
            [ self checkRefCount ];
        }
    } else {
        [ m_openChannelsMutex lock ];
        Channel *channel = [ m_openChannels objectForKey:[ NSNumber numberWithInteger:ch ]];
        [ m_openChannelsMutex unlock ];
		
        if (!channel) {
            [ self destroy:@"Frame sent to unknown channel" ];
            return;
        }
		
		if (flag != SIG_EMIT && ![ channel isClosing ]) {
			Frame *frame = [[ Frame alloc ] initWithChannel:ch op:SIGNAL flag:SIG_END payload:payload ];
			
			@try {
				[ self writeBytes:frame ];
			}
			@catch (NSException *e) {
				[ payload release ];
				[ self destroy: [ e reason ] ];
			}
			
			return;
		}
		
        [ self processSignalFrameWithChannel:channel flag:flag payload:payload ];
    }

}

- (void) destroy:(NSString*)error
{
    [ m_destroyingMutex lock ];
    m_destroying = YES;
    [ m_destroyingMutex unlock ];
    
#ifdef HYDNADEBUG
	debugPrint(@"Connection", 0, [ NSString stringWithFormat:@"Destroying connection because: %@", error ]);
#endif
    
    [ m_pendingMutex lock ];
#ifdef HYDNADEBUG
	debugPrint(@"Connection", 0, [ NSString stringWithFormat:@"Destroying pendingOpenRequests of size %i", [ m_pendingOpenRequests count ]]);
#endif
    
    for (NSNumber *key in m_pendingOpenRequests) {
#ifdef HYDNADEBUG
		debugPrint(@"Connection", [ key intValue ], @"Destroying channel");
#endif
        [[[ m_pendingOpenRequests objectForKey:key ] channel ] destroy:error ];
    }
    [ m_pendingOpenRequests removeAllObjects ];
    [ m_pendingMutex unlock ];
    
    [ m_openWaitMutex lock ];
#ifdef HYDNADEBUG
	debugPrint(@"Connection", 0, [ NSString stringWithFormat:@"Destroying waitQueue of size %i", [ m_openWaitQueue count ]]);
#endif
    
    for (NSNumber *key in m_openWaitQueue) {
        NSMutableArray *queue = [ m_openWaitQueue objectForKey:key ];
        
        while ([ queue count ] > 0) {
            [[[ queue objectAtIndex:0 ] channel ] destroy:error ];
            [ queue removeObjectAtIndex:0 ];
        }
    }
    [ m_openWaitQueue removeAllObjects ];
    [ m_openWaitMutex unlock ];
    
    [ m_openChannelsMutex lock ];
#ifdef HYDNADEBUG
	debugPrint(@"Connection", 0, [ NSString stringWithFormat:@"Destroying openChannels of size %i", [ m_openChannels count ]]);
#endif
    
    for (NSNumber *key in m_openChannels) {
#ifdef HYDNADEBUG
		debugPrint(@"Connection", [ key intValue ], @"Destroying channel");
#endif
        [[ m_openChannels objectForKey:key ] destroy:error ];
    }
    [ m_openChannels removeAllObjects ];
    [ m_openChannelsMutex unlock ];
    
    if (m_connected) {
#ifdef HYDNADEBUG
		debugPrint(@"Connection", 0, @"Closing connection");
#endif
        [ m_listeningMutex lock ];
        m_listening = NO;
        [ m_listeningMutex unlock ];
        
        close(m_connectionFDS);
        m_connected = NO;
        m_handshaked = NO;
    }
    NSString *key = [ m_host stringByAppendingFormat:@"%d%@", m_port, m_auth ];
    
    [ m_connectionMutex lock ];
    Connection *connection = [ m_availableConnections objectForKey:key ];
    
    if (connection) {
        [ connection release ];
        [ m_availableConnections removeObjectForKey:m_host ];
    }
    [ m_connectionMutex unlock ];
    
#ifdef HYDNADEBUG
	debugPrint(@"Connection", 0, @"Destroying connection done");
#endif
    
    [ m_destroyingMutex lock ];
    m_destroying = NO;
    [ m_destroyingMutex unlock ];
}

- (BOOL) writeBytes:(Frame*)frame
{
    if (m_handshaked) {
        NSInteger n = -1;
        NSInteger size = [ frame size ];
        const char* data = [ frame data ];
        NSInteger offset = 0;
        
        while (offset < size && n != 0) {
            n = write(m_connectionFDS, data + offset, size - offset);
            offset += n;
        }
        
        if (n <= 0) {
            [ self destroy:@"Could not write to the connection" ];
            return NO;
        }
        return  YES;
    }
    return NO;
}

@end
