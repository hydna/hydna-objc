//
//  ExtSocket.h
//  hydna-objc
//

#import <Cocoa/Cocoa.h>

#import "OpenRequest.h"
#import "Packet.h"

extern const int HANDSHAKE_SIZE;
extern const int HANDSHAKE_RESP_SIZE;

/**
 *  This class is used internally by the Channel class.
 *  A user of the library should not create an instance of this class.
 */
@interface ExtSocket : NSObject {
    NSLock *m_channelRefMutex;
    NSLock *m_destroyingMutex;
    NSLock *m_closingMutex;
    NSLock *m_openChannelsMutex;
    NSLock *m_openWaitMutex;
    NSLock *m_pendingMutex;
    NSLock *m_listeningMutex;
    
    BOOL m_connecting;
    BOOL m_connected;
    BOOL m_handshaked;
    BOOL m_destroying;
    BOOL m_closing;
    BOOL m_listening;
    
    NSString *m_host;
    NSUInteger m_port;
    NSInteger m_socketFDS;
    
    NSMutableDictionary *m_pendingOpenRequests;
    NSMutableDictionary *m_openChannels;
    NSMutableDictionary *m_openWaitQueue;
    
    NSInteger m_channelRefCount;
}

/**
 *  Return an available socket or create a new one.
 *
 *  @param host The host associated with the socket.
 *  @param port The port associated with the socket.
 */
+ (id) getSocketWithHost:(NSString*)host port:(NSUInteger)port;

/**
 *  Initializes a new Channel instance.
 *
 *  @param host The host the socket should connect to.
 *  @param port The port the socket should connect to.
 */
- (id) initWithHost:(NSString*)host port:(NSUInteger)port;

- (void) dealloc;

/**
 *  Returns the handshake status of the socket.
 *
 *  @return YES if the socket has handshaked.
 */
- (BOOL) hasHandshaked;

/**
 * Method to keep track of the number of channels that is associated 
 * with this socket instance.
 */
- (void) allocChannel;

/**
 *  Decrease the reference count.
 *
 *  @param ch The channel to dealloc.
 */
- (void) deallocChannel:(NSUInteger)ch;

/**
 *  Request to open a channel.
 *
 *  @param request The request to open the channel.
 *  @return YES if request went well, else NO.
 */
- (BOOL) requestOpen:(OpenRequest*)request;

/**
 *  Try to cancel an open request. Returns YES on success else NO.
 *
 *  @param request The request to cancel.
 *  @return YES if the request was canceled.
 */
- (BOOL) cancelOpen:(OpenRequest*)request;

/**
 *  Writes a packet to the socket.
 *
 *  @param packet The packet to be sent.
 *  @return YES if the packet was sent.
 */
- (BOOL) writeBytes:(Packet*)packet;

@end
