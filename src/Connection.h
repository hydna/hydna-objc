//
//  Connection.h
//  hydna-objc
//

#import <Cocoa/Cocoa.h>

#import "OpenRequest.h"
#import "Frame.h"

extern const unsigned int MAX_REDIRECT_ATTEMPTS;

/**
 *  This class is used internally by the Channel class.
 *  A user of the library should not create an instance of this class.
 */
@interface Connection : NSObject {
    NSLock *m_channelRefMutex;
    NSLock *m_destroyingMutex;
    NSLock *m_closingMutex;
    NSLock *m_openChannelsMutex;
    NSLock *m_openWaitMutex;
    NSLock *m_pendingMutex;
    NSLock *m_resolveMutex; // new
    NSLock *m_resolveWaitMutex; // new
    NSLock *m_resolveChannelsMutex; // new
    NSLock *m_listeningMutex;
    
    BOOL m_connecting;
    BOOL m_connected;
    BOOL m_handshaked;
    BOOL m_destroying;
    BOOL m_closing;
    BOOL m_listening;
    BOOL m_resolved; // new
    
    NSString *m_host;
    NSUInteger m_port;
	NSString *m_auth;
    NSInteger m_connectionFDS;
    NSUInteger m_attempt;
	
    NSMutableDictionary *m_pendingOpenRequests;
    NSMutableDictionary *m_pendingResolveRequests; // resolve que
    NSMutableDictionary *m_openChannels;
    NSMutableDictionary *m_openWaitQueue;
    NSMutableDictionary *m_resolveWaitQueue; // resolve que
    
    NSInteger m_channelRefCount;
}

/**
 *  Return an available connection or create a new one.
 *
 *  @param host The host associated with the connection.
 *  @param port The port associated with the connection.
 */
+ (id) getConnectionWithHost:(NSString*)host port:(NSUInteger)port auth:(NSString*)auth;


/**
 *  Checks if redirects should be followed.
 *
 *  @return The current status if redirects should be followed or not.
 */
+ (BOOL) getFollowRedirects;

/**
 *  Sets if redirects should be followed or not.
 *  
 *  @param value The new follow redirects status.
 */
+ (void) setFollowRedirects:(BOOL)value;

/**
 *  Initializes a new Channel instance.
 *
 *  @param host The host the connection should connect to.
 *  @param port The port the connection should connect to.
 */
- (id) initWithHost:(NSString*)host port:(NSUInteger)port auth:(NSString*)auth;

- (void) dealloc;

/**
 *  Returns the handshake status of the connection.
 *
 *  @return YES if the connection has handshaked.
 */
- (BOOL) hasHandshaked;

/**
 * Method to keep track of the number of channels that is associated 
 * with this connection instance.
 */
- (void) allocChannel;

/**
 *  Decrease the reference count.
 *
 *  @param ch The channel to dealloc.
 */
- (void) deallocChannel:(NSUInteger)ch;

/**
 *  Request to resolve a channel.
 *
 *  @param request The request to resolve the channel.
 *  @return YES if request went well, else NO.
 */
- (BOOL) requestResolve:(OpenRequest*)request;


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
 *  Writes a frame to the connection.
 *
 *  @param frame The frame to be sent.
 *  @return YES if the frame was sent.
 */
- (BOOL) writeBytes:(Frame*)frame;

@end
