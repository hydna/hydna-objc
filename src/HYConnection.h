//
//  Connection.h
//  hydna-objc
//

#import "HYOpenRequest.h"
#import "HYFrame.h"


#define TAKE_N_BITS_FROM(b, p, n) ((b) >> (p)) & ((1 << (n)) - 1);

extern const unsigned int MAX_REDIRECT_ATTEMPTS;

/**
 *  This class is used internally by the Channel class.
 *  A user of the library should not create an instance of this class.
 */
@interface HYConnection : NSObject



/**
 *  Return an available connection or create a new one.
 *
 *  @param host The host associated with the connection.
 *  @param port The port associated with the connection.
 */
+ (HYConnection *)getConnectionWithHost:(NSString *)host
                                 port:(NSUInteger)port
                                 auth:(NSString *)auth;


/**
 *  Checks if redirects should be followed.
 *
 *  @return The current status if redirects should be followed or not.
 */
+ (BOOL)getFollowRedirects;

/**
 *  Sets if redirects should be followed or not.
 *  
 *  @param value The new follow redirects status.
 */
+ (void)setFollowRedirects:(BOOL)value;

/**
 *  Initializes a new Channel instance.
 *
 *  @param host The host the connection should connect to.
 *  @param port The port the connection should connect to.
 */
- (id)initWithHost:(NSString *)host
              port:(NSUInteger)port
              auth:(NSString *)auth;

- (void)dealloc;

/**
 *  Returns the handshake status of the connection.
 *
 *  @return YES if the connection has handshaked.
 */
- (BOOL)hasHandshaked;

/**
 * Method to keep track of the number of channels that is associated 
 * with this connection instance.
 */
- (void)allocChannel;

/**
 *  Decrease the reference count.
 *
 *  @param ch The channel to dealloc.
 */
- (void)deallocChannel:(NSUInteger)ch;

/**
 *  Request to resolve a channel.
 *
 *  @param request The request to resolve the channel.
 *  @return YES if request went well, else NO.
 */
- (BOOL)requestResolve:(HYOpenRequest *)request;


/**
 *  Request to open a channel.
 *
 *  @param request The request to open the channel.
 *  @return YES if request went well, else NO.
 */
- (BOOL)requestOpen:(HYOpenRequest *)request;

/**
 *  Try to cancel an open request. Returns YES on success else NO.
 *
 *  @param request The request to cancel.
 *  @return YES if the request was canceled.
 */
- (BOOL)cancelOpen:(HYOpenRequest *)request;

/**
 *  Writes a frame to the connection.
 *
 *  @param frame The frame to be sent.
 *  @return YES if the frame was sent.
 */
- (BOOL)writeBytes:(HYFrame *)frame;

@end
