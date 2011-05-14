//
//  Packet.h
//  hydna-objc
//

#import <Cocoa/Cocoa.h>

enum {
    HEADER_SIZE = 0x08
};

enum {    
    // Opcodes
    OPEN   = 0x01,
    DATA   = 0x02,
    SIGNAL = 0x03
};
    
enum {
    // Handshake flags
    HANDSHAKE_UNKNOWN = 0x01,
    HANDSHAKE_SERVER_BUSY = 0x02,
    HANDSHAKE_BADFORMAT = 0x03,
    HANDSHAKE_HOSTNAME = 0x04,
    HANDSHAKE_PROTOCOL = 0x05,
    HANDSHAKE_SERVER_ERROR = 0x06
};

enum {
    // Open Flags
    OPEN_SUCCESS = 0x0,
    OPEN_REDIRECT = 0x1,
    OPEN_FAIL_NA = 0x8,
    OPEN_FAIL_MODE = 0x9,
    OPEN_FAIL_PROTOCOL = 0xa,
    OPEN_FAIL_HOST = 0xb,
    OPEN_FAIL_AUTH = 0xc,
    OPEN_FAIL_SERVICE_NA = 0xd,
    OPEN_FAIL_SERVICE_ERR = 0xe,
    OPEN_FAIL_OTHER = 0xf
};

enum {
    // Signal Flags
    SIG_EMIT = 0x0,
    SIG_END = 0x1,
    SIG_ERR_PROTOCOL = 0xa,
    SIG_ERR_OPERATION = 0xb,
    SIG_ERR_LIMIT = 0xc,
    SIG_ERR_SERVER = 0xd,
    SIG_ERR_VIOLATION = 0xe,
    SIG_ERR_OTHER = 0xf
};

// Upper payload limit (10kb)
extern const unsigned int PAYLOAD_MAX_LIMIT;


@interface Packet : NSObject {
    NSMutableData *m_bytes;
}

- (id) initWithChannel:(NSUInteger)ch op:(NSUInteger)op flag:(NSUInteger)flag payload:(NSData*)payload;

- (void) writeByte:(char)value;

- (void) writeBytes:(NSData*)value;

- (void) writeShort:(short)value;

- (void) writeUnsignedInt:(unsigned int)value;

- (int) getSize;

- (const char*) getData;

- (void) setChannel:(NSUInteger)value;

@end
