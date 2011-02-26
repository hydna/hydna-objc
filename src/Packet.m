//
//  Packet.m
//  hydna-objc
//

#import "Packet.h"

// Upper payload limit (10kb)
const unsigned int PAYLOAD_MAX_LIMIT = 10 * 1024;

@implementation Packet

- (id) initWithAddr:(NSUInteger)addr op:(NSUInteger)op flag:(NSUInteger)flag payload:(NSData*)payload
{
    unsigned int length = HEADER_SIZE + [ payload length ];
    
    if (length > PAYLOAD_MAX_LIMIT) {
        [NSException raise:@"RangeError" format:@"Payload max limit reached"];
    }
        
    if (!(self = [super init])) {
        return nil;
    }
    
    self->m_bytes = [[NSMutableData alloc] initWithCapacity:length];
    
    [ self writeShort:length ];
    [ self writeByte:0 ]; // Reserved
    [ self writeUnsignedInt:addr ];
    [ self writeByte:op << 4 | flag ];
    
    if (payload) {
        [ self writeBytes: payload ];
    }
    
    return self;
}

- (void) writeByte:(char)value
{
    [ m_bytes appendBytes:&value length:1 ];
}

- (void) writeBytes:(NSData*)value
{
    [ m_bytes appendData:value ];
}

- (void) writeShort:(short)value
{
    char result[2];
    
    *(short*)&result[0] = htons(value);
    
    [ m_bytes appendBytes:result length:2 ];
}

- (void) writeUnsignedInt:(unsigned int)value
{
    char result[4];
    
    *(unsigned int*)&result[0] = htonl(value);
    
    [ m_bytes appendBytes:result length:4 ];    
}

- (int) getSize
{
    return [ m_bytes length ];
}

- (const char*) getData
{
    return [ m_bytes bytes ];
}

@end
