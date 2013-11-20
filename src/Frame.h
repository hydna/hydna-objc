//
//  Frame.h
//  hydna-objc
//

#import <Cocoa/Cocoa.h>

enum {
    HEADER_SIZE = 0x07
};

enum {    
    // Opcodes
	NOOP   = 0x00,
    KEEPALIVE = 0x00,
    OPEN   = 0x01,
    DATA   = 0x02,
    SIGNAL = 0x03,
    RESOLVE = 0x04
};

enum {
    // Open Flags
    OPEN_ALLOW = 0x0,
    OPEN_REDIRECT = 0x1,
    OPEN_DENY = 0x7
};

enum {
    // Signal Flags
    SIG_EMIT = 0x0,
    SIG_END = 0x1,
    SIG_ERROR = 0x7
};

enum {
    // Bitmasks
    FLAG_BITMASK = 0x7,
    OP_BITPOS = 3,
    OP_BITMASK = ((1 << 3) - 1),
    CTYPE_BITPOS = 6,
    CTYPE_BITMASK = (0x01 << CTYPE_BITPOS)  
};

enum {
    CTYPE_UTF8 = 0x0,
    CTYPE_BINARY = 0x1
};

// Upper payload limit (10kb)
extern const unsigned int PAYLOAD_MAX_LIMIT;
extern const unsigned int RESOLVE_CHANNEL;


@interface Frame : NSObject {
    NSMutableData *m_bytes;
}

- (id) initWithChannel:(NSUInteger)ch ctype:(NSUInteger)ctype op:(NSUInteger)op flag:(NSUInteger)flag payload:(NSData*)payload;

- (void) writeByte:(char)value;

- (void) writeBytes:(NSData*)value;

- (void) writeShort:(short)value;

- (void) writeUnsignedInt:(unsigned int)value;

- (int) size;

- (const char*) data;

- (void) setChannel:(NSUInteger)value;

@end
