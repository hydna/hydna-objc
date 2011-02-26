//
//  Stream.h
//  hydna-objc
//

#import <Cocoa/Cocoa.h>

#import "ExtSocket.h"
#import "OpenRequest.h"
#import "StreamData.h"
#import "StreamSignal.h"

typedef enum {
    LISTEN = 0x00,
    READ = 0x01,
    WRITE = 0x02,
    READWRITE = 0x03,
    EMIT = 0x04,
    READ_EMIT = 0x05,
    WRITE_EMIT = 0x06,
    READWRITE_EMIT = 0x07
} StreamMode;

/**
 *  This class is used as an interface to the library.
 *  A user of the library should use an instance of this class
 *  to communicate with a server.
 */
@interface Stream : NSObject {
    NSString *m_host;
    NSUInteger m_port;
    NSUInteger m_addr;
    
    ExtSocket *m_socket;
    
    BOOL m_connected;
    BOOL m_pendingClose;
    BOOL m_readable;
    BOOL m_writable;
    BOOL m_emitable;
    
    NSString* m_error;
    
    NSUInteger m_mode;
    
    OpenRequest *m_openRequest;
    
    NSMutableArray *m_dataQueue;
    NSMutableArray *m_signalQueue;
    
    NSLock *m_dataMutex;
    NSLock *m_signalMutex;
    NSLock *m_connectMutex;
}

/**
 *  Initializes a new Stream instance
 */
- (id) init;

- (void) dealloc;

/**
 *  Checks the connected state for this Stream instance.
 *
 *  @return The connected state.
 */
- (BOOL) isConnected;

/**
 *  Checks if the stream is readable.
 *
 *  @return YES if stream is readable.
 */
- (BOOL) isReadable;

/**
 *  Checks if the stream is writable.
 *
 *  @return YES if stream is writable.
 */
- (BOOL) isWritable;

/**
 *  Checks if the stream can emit signals.
 *
 *  @return YES if stream has signal support.
 */
- (BOOL) hasSignalSupport;

/**
 *  Returns the addr that this instance listen to.
 *
 *  @return addr The address.
 */
- (NSUInteger) getAddr;

/**
 *  Resets the error.
 *  
 *  Connects the stream to the specified addr. If the connection fails 
 *  immediately, an exception is thrown.
 *
 *  @param expr The address to connect to,
 *  @param mode The mode in which to open the stream.
 *  @param token An optional token.
 */
- (void) connect:(NSString*)expr mode:(NSUInteger)mode token:(NSData*)token;

/**
 *  Sends data to the stream.
 *
 *  @param data The data to write to the stream.
 *  @param priority The priority of the data.
 */
- (void) writeBytes:(NSData*)data priority:(NSUInteger)priority;

/**
 *  Calls writeBytes:priority: with a priority of 1.
 *
 *  @param data The data to write to the stream.
 */
- (void) writeBytes:(NSData*)data;

/**
 *  Sends string data to the stream.
 *
 *  @param value The string to be sent.
 */
- (void) writeString:(NSString*)string;

/**
 *  Sends data signal to the stream.
 *
 *  @param data The data to write to the stream.
 *  @param type The type of the signal.
 */
- (void) emitBytes:(NSData*)data type:(NSUInteger)type;

/**
 *  Calls emitBytes:type: with the type 0.
 *
 *  @param data The data to write to the stream.
 */
- (void) emitBytes:(NSData*)data;

/**
 *  Sends a string signal to the stream.
 *
 *  @param value The string to be sent.
 *  @param type The type of the signal.
 */
- (void) emitString:(NSString*)string type:(NSUInteger)type;

/**
 *  Calls emitString:type: with the type 0.
 *
 *  @param value The string to be sent.
 */
- (void) emitString:(NSString*)string;

/**
 *  Closes the Stream instance.
 */
- (void) close;

/**
 *  Internal callback for open success.
 *  Used by the ExtSocket class.
 *
 *  @param respaddr The response address.
 */
- (void) openSuccess:(NSUInteger)respaddr;

/**
 *  Checks if some error has occured in the stream
 *  and throws an exception if that is the case.
 */
- (void) checkForStreamError;

/**
 *  Internally destroy socket.
 *
 *  @param error The cause of the destroy.
 */
- (void) destroy:(NSString *)error;

/**
 *  Add data to the data queue.
 *
 *  @param data The data to add to queue.
 */
- (void) addData:(StreamData *)data;

/**
 *  Pop the next data in the data queue.
 *
 *  @return The data that was removed from the queue,
 *          or nil if the queue was empty.
 */
- (StreamData*) popData;

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
- (void) addSignal:(StreamSignal *)signal;

/**
 *  Pop the next signal in the signal queue.
 *
 *  @return The signal that was removed from the queue,
 *          or nil if the queue was empty.
 */
- (StreamSignal*) popSignal;

/**
 *  Checks if the signal queue is empty.
 *
 *  @return YES is the queue is empty.
 */
- (BOOL) isSignalEmpty;

@end
