//
//  ExtSocket.m
//  hydna-objc
//

#import "ExtSocket.h"
#import "Channel.h"
#import "ChannelError.h"

#ifdef HYDNADEBUG
#import "DebugHelper.h"
#endif

#import <netinet/tcp.h>
#import <netinet/in.h>
#import <arpa/inet.h>

const int HANDSHAKE_SIZE = 9;
const int HANDSHAKE_RESP_SIZE = 5;

static NSLock *m_socketMutex;
static NSMutableDictionary *m_availableSockets = nil;

@interface ExtSocket ()

/**
 *  Check if there are any more references to the socket.
 */
- (void) checkRefCount;

/**
 *  Connect the socket.
 *
 *  @param host The host to connect to.
 *  @param port The port to connect to.
 */
- (void) connectSocketWithHost:(NSString *)host port:(NSUInteger)port;

/**
 *  Send a handshake packet.
 */
- (void) connectHandler;

/**
 *  Handle the Handshake response packet.
 */
- (void) handshakeHandler;

/**
 *  Handles all incomming data.
 */
- (void) receiveHandler;

/**
 *  Process an open packet.
 *
 *  @param ch The channel that should receive the open packet.
 *  @param errcode The error code of the open packet.
 *  @param payload The content of the open packet.
 */
- (void) processOpenPacketWithChannelId:(NSUInteger)ch errcode:(NSInteger)errcode payload:(NSData *)payload;

/**
 *  Process a data packet.
 *
 *  @param ch The channel that should receive the data.
 *  @param priority The priority of the data.
 *  @param payload The content of the data.
 */
- (void) processDataPacketWithChannelId:(NSUInteger)ch priority:(NSInteger)priority payload:(NSData *)payload;

/**
 *  Process a signal packet.
 *
 *  @param channel The channel that should receive the signal.
 *  @param flag The flag of the signal.
 *  @param payload The content of the signal.
 *  @return NO is something went wrong.
 */
- (BOOL) processSignalPacketWithChannel:(Channel *)channel flag:(NSInteger)flag payload:(NSData *)payload;

/**
 *  Process a signal packet.
 *
 *  @param ch The channel that should receive the signal.
 *  @param flag The flag of the signal.
 *  @param payload The content of the signal.
 */
- (void) processSignalPacketWithChannelId:(NSUInteger)ch flag:(NSInteger)flag payload:(NSData *)payload;

/**
 *  Destroy the socket.
 *
 *  @error The cause of the destroy.
 */
- (void) destroy:(NSString *)error;

/**
 * The method that is called in the new thread.
 * Listens for incoming packets.
 *
 * @param param An object with arguments.
 */
- (void) listen:(id)param;

@end

@implementation ExtSocket

+ (id) getSocketWithHost:(NSString*)host port:(NSUInteger)port
{
    if (!m_socketMutex) {
        m_socketMutex = [[ NSLock alloc ] init ];
    }
    
    [ m_socketMutex lock ];
    if (!m_availableSockets) {
        m_availableSockets = [[ NSMutableDictionary alloc ] init ];
    }
    
    NSString* key = [ host stringByAppendingFormat:@"%d", port ];
    ExtSocket* socket = [ m_availableSockets objectForKey:key ];
    
    if (!socket) {
        socket = [[ ExtSocket alloc ] initWithHost:host port:port ];
        [ m_availableSockets setObject:socket forKey:key ];
    }
    [ m_socketMutex unlock ];
    
    return socket;
}

- (id) initWithHost:(NSString*)host port:(NSUInteger)port
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
	debugPrint(@"ExtSocket", 0, [NSString stringWithFormat:@"Allocating a new channel, channel ref count is %i", m_channelRefCount]);
#endif
}

- (void) deallocChannel:(NSUInteger)ch;
{
#ifdef HYDNADEBUG
	debugPrint(@"ExtSocket", ch, @"Deallocatin a channel");
#endif
    [ m_destroyingMutex lock ];
    [ m_closingMutex lock ];
    if (!m_destroying && !m_closing) {
        [ m_closingMutex unlock ];
        [ m_destroyingMutex unlock ];
        
        [ m_openChannelsMutex lock ];
        [ m_openChannels removeObjectForKey:[ NSNumber numberWithInteger:ch ] ];
#ifdef HYDNADEBUG
		debugPrint(@"ExtSocket", ch, [NSString stringWithFormat:@"Size of openChannels is now %i", [ m_openChannels count ]]);
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
		debugPrint(@"ExtSocket", 0, @"No more refs, destroy socket");
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
	debugPrint(@"ExtSocket", chcomp, @"A channel is trying to send a new open request");
#endif
    
    [ m_openChannelsMutex lock ];
    if ([ m_openChannels objectForKey:[ NSNumber numberWithInteger:chcomp ]] != nil) {
        [ m_openChannelsMutex unlock ];
#ifdef HYDNADEBUG
		debugPrint(@"ExtSocket", chcomp, @"The channel was already open, cancel the open request");
#endif
        [ request release ];
        return NO;
    }
    [ m_openChannelsMutex unlock ];
    
    [ m_pendingMutex lock ];
    if ([ m_pendingOpenRequests objectForKey:[ NSNumber numberWithInteger:chcomp ]] != nil) {
        [ m_pendingMutex unlock ];
        
#ifdef HYDNADEBUG
		debugPrint(@"ExtSocket", chcomp, @"A open request is waiting to be sent, queue up the new open request");
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
		debugPrint(@"ExtSocket", chcomp, @"The socket was not connected, queue up the new open request");
#endif
        [ m_pendingOpenRequests setObject:request forKey:[ NSNumber numberWithInteger:chcomp ]];
        [ m_pendingMutex unlock ];
        
        if (!m_connecting) {
            m_connecting = YES;
            [ self connectSocketWithHost:m_host port:m_port ];
        }
    } else {
		[ m_pendingOpenRequests setObject:request forKey:[ NSNumber numberWithInteger:chcomp ]];
        [ m_pendingMutex unlock ];
        
#ifdef HYDNADEBUG
		debugPrint(@"ExtSocket", chcomp, @"The socket was already connected, sending the new open request");
#endif
        [ self writeBytes:[ request packet ]];
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

- (void) connectSocketWithHost:(NSString*)host port:(NSUInteger)port
{
    NSHost *nshost = [ NSHost hostWithName:host ];
    NSArray *addresses =  [ nshost addresses ];
    NSString *address = @"";
    
#ifdef HYDNADEBUG
	debugPrint(@"ExtSocket", 0, @"Connecting socket");
#endif
    
    for (NSString *a in addresses) {
        if ([[ a componentsSeparatedByString:@":"] count ] == 1) {
            address = a;
            break;
        }
    }
    
    if (address != @"") {
        struct sockaddr_in server;
        
        if ((m_socketFDS = socket(PF_INET, SOCK_STREAM, IPPROTO_TCP)) == -1) {
            [ self destroy:@"Socket could not be created" ];
        } else {
            m_connected = YES;
            int flag = 1;
            
            if (setsockopt(m_socketFDS, IPPROTO_TCP,
                           TCP_NODELAY, (char *) &flag,
                           sizeof(flag)) < 0) {
                NSLog(@"WARNING: Could not set TCP_NODELAY");
            }
            
            
            server.sin_addr.s_addr = inet_addr([address UTF8String ]);
            server.sin_family = AF_INET;
            server.sin_port = htons(port);
            
            if (connect(m_socketFDS, (struct sockaddr *)&server, sizeof(server)) == -1) {
                if (connect(m_socketFDS, (struct sockaddr *)&server, sizeof(server)) == -1) {
                    [ self destroy:[ NSString stringWithFormat:@"Could not connect to the host \"%@\"", host ]];
                } else {
                    [ self connectHandler ];
                }
            } else {
                [ self connectHandler ];
            }
        }

    } else {
        [ self destroy:[ NSString stringWithFormat:@"The host \"%@\" could not be resolved", host ]];  
    }

}

- (void) connectHandler
{
#ifdef HYDNADEBUG
	debugPrint(@"ExtSocket", 0, @"Socket connected, sending handshake");
#endif
    
    NSUInteger length = [ m_host length ];
    NSUInteger totalLength = 4 + 1 + length;
    NSInteger n = -1;
    NSUInteger offset = 0;
    
    if (length < 256) {
        char data[totalLength];
        
        data[0] = 'D';
        data[1] = 'N';
        data[2] = 'A';
        data[3] = '1';
        data[4] = length;
        
        for (unsigned int i = 0; i < length; i++) {
            data[5 + i] = [ m_host characterAtIndex:i ];
        }
        
        while (offset < totalLength && n != 0) {
            n = write(m_socketFDS, data + offset, totalLength - offset);
            offset += n;
        }
    }
    
    if (n <= 0) {
        [ self destroy:@"Could not send handshake" ];
    } else {
        [ self handshakeHandler ];
    }
}

- (void) handshakeHandler
{
    NSInteger responseCode = 0;
    NSInteger offset = 0;
    NSInteger n = -1;
    char data[HANDSHAKE_RESP_SIZE];
    NSString *prefix = @"DNA1";
    
#ifdef HYDNADEBUG
	debugPrint(@"ExtSocket", 0, @"Incoming handshake response on socket");
#endif
    
    while (offset < HANDSHAKE_RESP_SIZE && n != 0) {
        n = read(m_socketFDS, data + offset, HANDSHAKE_RESP_SIZE - offset);
        offset += n;
    }
    
    if (offset != HANDSHAKE_RESP_SIZE) {
        [ self destroy:@"Server responded with bad handshake" ];
        return;
    }
    
    responseCode = data[HANDSHAKE_RESP_SIZE - 1];
    data[HANDSHAKE_RESP_SIZE - 1] = '\0';
    
    if (![ prefix isEqualToString:[ NSString stringWithCString:data encoding:NSUTF8StringEncoding ]]) {
        [ self destroy:@"Server responded with bad handshake" ];
        return;
    }
    
    if (responseCode > 0) {
        [ self destroy:[ ChannelError fromHandshakeError:responseCode ]];
        return;
    }
    
    m_handshaked = YES;
    m_connecting = NO;
    
#ifdef HYDNADEBUG
	debugPrint(@"ExtSocket", 0, @"Handshake done on socket");
#endif
    
    for (NSString *key in m_pendingOpenRequests) {
        OpenRequest *request = [ m_pendingOpenRequests objectForKey:key ];
        [ self writeBytes:[ request packet ]];
        
        if (m_connected) {
            [ request setSent:YES ];
#ifdef HYDNADEBUG
			debugPrint(@"ExtSocket", [ request ch ], @"Open request sent");
#endif
        } else {
            return;
        }

    }
    
#ifdef HYDNADEBUG
	debugPrint(@"ExtSocket", 0, @"Creating a new thread for packet listening");
#endif
    
    [NSThread detachNewThreadSelector:@selector(listen:) toTarget:self withObject:nil];
    
    /*
    if (!created) {
        [ self destroy:@"Could not create a new thread for packet listening" ];
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
            n = read(m_socketFDS, header + offset, headerSize - offset);
            offset += n;
        }
        
        if (n <= 0) {
            [ m_listeningMutex lock ];
            if (m_listening) {
                [ m_listeningMutex unlock ];
                [ self destroy:@"Could not read from the socket" ];
            } else {
				[ m_listeningMutex unlock ];
			}
            break;
        }
        
        size = ntohs(*(unsigned short*)&header[0]);
        payload = malloc((size - headerSize) * sizeof(char));
		
        while (offset < size && n > 0) {
            n = read(m_socketFDS, payload + offset - headerSize, size - offset);
            offset += n;
        }
        
        if (n <= 0) {
            [ m_listeningMutex lock ];
            if (m_listening) {
                [ m_listeningMutex unlock ];
                [ self destroy:@"Could not read from the socket" ];
            } else {
				[ m_listeningMutex unlock ];
			}
            break;
        }
        
        // header[2]; Reserved
        ch = ntohl(*(unsigned int*)&header[3]);
        op = header[7] >> 4;
        flag = header[7] & 0xf;
        
        NSData *data = [[ NSData alloc ] initWithBytesNoCopy:payload length:size - headerSize ];
        
        switch (op) {
            case OPEN:
#ifdef HYDNADEBUG
				debugPrint(@"ExtSocket", ch, @"Received open response");
#endif
                [ self processOpenPacketWithChannelId:ch errcode:flag payload:data ];
                break;
                
            case DATA:
#ifdef HYDNADEBUG
				debugPrint(@"ExtSocket", ch, @"Received data");
#endif
                [ self processDataPacketWithChannelId:ch priority:flag payload:data ];
                break;
                
            case SIGNAL:
#ifdef HYDNADEBUG
				debugPrint(@"ExtSocket", ch, @"Received signal");
#endif
                [ self processSignalPacketWithChannelId:ch flag:flag payload:data ];
                break;
        }
        
        offset = 0;
        n = 1;
    }
#ifdef HYDNADEBUG
	debugPrint(@"ExtSocket", 0, @"Listening thread exited");
#endif
    [ pool release ];
}

- (void) processOpenPacketWithChannelId:(NSUInteger)ch errcode:(NSInteger)errcode payload:(NSData*)payload
{
    OpenRequest *request = nil;
    Channel *channel;
    NSUInteger respch = 0;
    
    [ m_pendingMutex lock ];
    request = [ m_pendingOpenRequests objectForKey:[ NSNumber numberWithInteger:ch ]];
    [ m_pendingMutex unlock ];
    
    if (!request) {
        [ self destroy:@"The server sent an invalid open packet" ];
        return;
    }
    
    channel = [ request channel ];
    
    if (errcode == OPEN_SUCCESS) {
        respch = ch;
    } else if (errcode == OPEN_REDIRECT) {
        if ([ payload length ] < 4) {
            [ self destroy:@"Expected redirect channel from the server" ];
            return;
        }
        
        const char *data = [ payload bytes ];
        
        respch = ntohl(*(unsigned int*)&data[0]);
        
#ifdef HYDNADEBUG
		debugPrint(@"ExtSocket",     ch, [ NSString stringWithFormat:@"Redirected from %u", ch]);
		debugPrint(@"ExtSocket", respch, [ NSString stringWithFormat:@"             to %u", respch ]);
#endif
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
		debugPrint(@"ExtSocket", ch, [ NSString stringWithFormat:@"The server rejected the open request, errorcode %i", errcode ]);
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
	debugPrint(@"ExtSocket", respch, @"A new channel was added");
	debugPrint(@"ExtSocket", respch, [ NSString stringWithFormat:@"The size of openChannel is now %i", [ m_openChannels count ]]);
#endif
    [ m_openChannelsMutex unlock ];
    
    [ channel openSuccess:respch ];
    
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
        
        [ self writeBytes:[ request packet ]];
        [ request setSent:YES ];
    } else {
        [[ m_pendingOpenRequests objectForKey:[ NSNumber numberWithInteger:ch ]] release ];
        [ m_pendingOpenRequests removeObjectForKey:[ NSNumber numberWithInteger:ch ]];
    }
    [ m_pendingMutex unlock ];
    [ m_openWaitMutex unlock ];
}

- (void) processDataPacketWithChannelId:(NSUInteger)ch priority:(NSInteger)priority payload:(NSData*)payload
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
        [ self destroy:@"Zero data packet received" ];
        return;
    }
    
    data = [[ ChannelData alloc ] initWithPriority:priority content:payload ];
    [ channel addData:data ];
}

- (BOOL) processSignalPacketWithChannel:(Channel*)channel flag:(NSInteger)flag payload:(NSData*)payload
{
    ChannelSignal *signal;
    
    if (flag > 0x0) {
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

- (void) processSignalPacketWithChannelId:(NSUInteger)ch flag:(NSInteger)flag payload:(NSData*)payload
{
    if (ch == 0) {
        BOOL destroying = NO;
        
        if (flag > 0x0 || [ payload length ] == 0) {
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
            
            if (![ self processSignalPacketWithChannel:channel flag:flag payload:payloadCopy ]) {
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
        
        if (!channel) {
            [ m_openChannelsMutex unlock ];
            [ self destroy:@"Packet sent to unknown channel" ];
            return;
        }
		
		if (flag > 0x0 && ![ channel isClosing ]) {
			[ m_openChannelsMutex unlock ];
			
			Packet *packet = [[ Packet alloc ] initWithChannel:ch op:SIGNAL flag:SIG_END payload:payload ];
			
			@try {
				[ self writeBytes:packet ];
			}
			@catch (NSException *e) {
				[ payload release ];
				[ self destroy: [ e reason ] ];
			}
			
			return;
		}
        
        [ self processSignalPacketWithChannel:channel flag:flag payload:payload ];
        [ m_openChannelsMutex unlock ];
    }

}

- (void) destroy:(NSString*)error
{
    [ m_destroyingMutex lock ];
    m_destroying = YES;
    [ m_destroyingMutex unlock ];
    
#ifdef HYDNADEBUG
	debugPrint(@"ExtSocket", 0, [ NSString stringWithFormat:@"Destroying socket because: %@", error ]);
#endif
    
    [ m_pendingMutex lock ];
#ifdef HYDNADEBUG
	debugPrint(@"ExtSocket", 0, [ NSString stringWithFormat:@"Destroying pendingOpenRequests of size %i", [ m_pendingOpenRequests count ]]);
#endif
    
    for (NSNumber *key in m_pendingOpenRequests) {
#ifdef HYDNADEBUG
		debugPrint(@"ExtSocket", [ key intValue ], @"Destroying channel");
#endif
        [[[ m_pendingOpenRequests objectForKey:key ] channel ] destroy:error ];
    }
    [ m_pendingOpenRequests removeAllObjects ];
    [ m_pendingMutex unlock ];
    
    [ m_openWaitMutex lock ];
#ifdef HYDNADEBUG
	debugPrint(@"ExtSocket", 0, [ NSString stringWithFormat:@"Destroying waitQueue of size %i", [ m_openWaitQueue count ]]);
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
	debugPrint(@"ExtSocket", 0, [ NSString stringWithFormat:@"Destroying openChannels of size %i", [ m_openChannels count ]]);
#endif
    
    for (NSNumber *key in m_openChannels) {
#ifdef HYDNADEBUG
		debugPrint(@"ExtSocket", [ key intValue ], @"Destroying channel");
#endif
        [[ m_openChannels objectForKey:key ] destroy:error ];
    }
    [ m_openChannels removeAllObjects ];
    [ m_openChannelsMutex unlock ];
    
    if (m_connected) {
#ifdef HYDNADEBUG
		debugPrint(@"ExtSocket", 0, @"Closing socket");
#endif
        [ m_listeningMutex lock ];
        m_listening = NO;
        [ m_listeningMutex unlock ];
        
        close(m_socketFDS);
        m_connected = NO;
        m_handshaked = NO;
    }
    NSString* key = [ m_host stringByAppendingFormat:@"%d", m_port ];
    
    [ m_socketMutex lock ];
    ExtSocket *socket = [ m_availableSockets objectForKey:key ];
    
    if (socket) {
        [ socket release ];
        [ m_availableSockets removeObjectForKey:m_host ];
    }
    [ m_socketMutex unlock ];
    
#ifdef HYDNADEBUG
	debugPrint(@"ExtSocket", 0, @"Destroying socket done");
#endif
    
    [ m_destroyingMutex lock ];
    m_destroying = NO;
    [ m_destroyingMutex unlock ];
}

- (BOOL) writeBytes:(Packet*)packet
{
    if (m_handshaked) {
        NSInteger n = -1;
        NSInteger size = [ packet getSize ];
        const char* data = [ packet getData ];
        NSInteger offset = 0;
        
        while (offset < size && n != 0) {
            n = write(m_socketFDS, data + offset, size - offset);
            offset += n;
        }
        
        if (n <= 0) {
            [ self destroy:@"Could not write to the socket" ];
            return NO;
        }
        return  YES;
    }
    return NO;
}

@end
