//
//  Channel.h
//  hydna-objc
//

#import <Cocoa/Cocoa.h>

#import "Connection.h"
#import "OpenRequest.h"
#import "ChannelData.h"
#import "ChannelSignal.h"

typedef enum {
    LISTEN = 0x00,
    READ = 0x01,
    WRITE = 0x02,
    READWRITE = 0x03,
    EMIT = 0x04,
    READEMIT = 0x05,
    WRITEEMIT = 0x06,
    READWRITEEMIT = 0x07
} ChannelMode;

/**
 *  This class is used as an interface to the library.
 *  A user of the library should use an instance of this class
 *  to communicate with a server.
 */
@interface Channel : NSObject {
    NSUInteger m_ch;
    NSString *m_path;
    NSString *m_token;
	NSString *m_message;
    
    Connection *m_connection;
    
    BOOL m_connected;
	BOOL m_closing;
	Frame *m_pendingClose;
    BOOL m_readable;
    BOOL m_writable;
    BOOL m_emitable;
    BOOL m_resolved;
    
    NSString *m_error;
    
    NSUInteger m_mode;
    
    OpenRequest *m_openRequest;
    OpenRequest *m_resolveRequest;
    
    NSMutableArray *m_dataQueue;
    NSMutableArray *m_signalQueue;
    
    NSLock *m_dataMutex;
    NSLock *m_signalMutex;
    NSLock *m_connectMutex;
}

/**
 *  Initializes a new Channel instance
 */
- (id) init;

- (void) dealloc;

/**
 *  Checks if redirects should be followed.
 *
 *  @return The current status if redirects should be followed or not.
 */
- (BOOL) getFollowRedirects;

/**
 *  Sets if redirects should be followed or not.
 *
 *  @param value The new follow redirects status.
 */
- (void) setFollowRedirects:(BOOL)value;

/**
 *  Checks the connected state for this Channel instance.
 *
 *  @return The connected state.
 */
- (BOOL) isConnected;

/**
 *  Checks the closing state for this Channel instance.
 *
 *  @return The closing state.
 */
- (BOOL) isClosing;

/**
 *  Checks if the channel is readable.
 *
 *  @return YES if channel is readable.
 */
- (BOOL) isReadable;

/**
 *  Checks if the channel is writable.
 *
 *  @return YES if channel is writable.
 */
- (BOOL) isWritable;

/**
 *  Checks if the channel can emit signals.
 *
 *  @return YES if channel has signal support.
 */
- (BOOL) hasSignalSupport;

/**
 *  Returns the channel that this instance listen to.
 *
 *  @return The channel.
 */
- (NSUInteger) channel;

/**
 *  Returns the message received when connected.
 *
 *  @return The message.
 */
- (NSString*) message;

/**
 *  Resets the error.
 *  
 *  Connects the channel to the specified channel. If the connection fails 
 *  immediately, an exception is thrown.
 *
 *  @param expr The channel to connect to,
 *  @param mode The mode in which to open the channel.
 *  @param token An optional token.
 */
- (void) connect:(NSString*)expr mode:(NSUInteger)mode token:(NSData*)token;

/**
 *  Sends data to the channel.
 *
 *  @param data The data to write to the channel.
 *  @param priority The priority of the data.
 */
- (void) writeBytes:(NSData*)data priority:(NSUInteger)priority ctype:(NSUInteger)ctype;

/**
 *  Calls writeBytes:priority: with a priority of 0.
 *
 *  @param data The data to write to the channel.
 */
- (void) writeBytes:(NSData*)data;

/**
 *  Sends string data to the channel.
 *
 *  @param value The string to be sent.
 */
- (void) writeString:(NSString*)string;

/**
 *  Sends string data to the channel with optional priority.
 *
 *  @param value The string to be sent.
 */
- (void) writeString:(NSString*)string priority:(NSInteger)priority;

/**
 *  Sends data signal to the channel.
 *
 *  @param data The data to write to the channel.
 */
- (void) emitBytes:(NSData*)data;

/**
 *  Sends a string signal to the channel.
 *
 *  @param string The string to be sent.
 */
- (void) emitString:(NSString*)string;

/**
 *  Closes the Channel instance.
 */
- (void) close;


/**
 *  Internal callback for resolve success.
 *  Used by the Connection class.
 *
 *  @param respch The response channel.
 */
- (void) resolveSuccess:(NSUInteger)respch path:(NSString*)path token:(NSString*)token;

/**
 *  Internal callback for open success.
 *  Used by the Connection class.
 *
 *  @param respch The response channel.
 */
- (void) openSuccess:(NSUInteger)respch message:(NSString*)message;



/**
 *  Checks if some error has occured in the channel
 *  and throws an exception if that is the case.
 */
- (void) checkForChannelError;

/**
 *  Internally destroy channel.
 *
 *  @param error The cause of the destroy.
 */
- (void) destroy:(NSString *)error;

/**
 *  Add data to the data queue.
 *
 *  @param data The data to add to queue.
 */
- (void) addData:(ChannelData *)data;

/**
 *  Pop the next data in the data queue.
 *
 *  @return The data that was removed from the queue,
 *          or nil if the queue was empty.
 */
- (ChannelData*) popData;

/**
 *  Checks if the signal queue is empty.
 *
 *  @return YES if the queue is empty.
 */
- (BOOL) isDataEmpty;

/**
 *  Add signals to the signal queue.
 *
 *  @param signal The signal to add to the queue.
 */
- (void) addSignal:(ChannelSignal *)signal;

/**
 *  Pop the next signal in the signal queue.
 *
 *  @return The signal that was removed from the queue,
 *          or nil if the queue was empty.
 */
- (ChannelSignal*) popSignal;

/**
 *  Checks if the signal queue is empty.
 *
 *  @return YES is the queue is empty.
 */
- (BOOL) isSignalEmpty;

@end
