//
//  OpenRequest.h
//  hydna-objc
//

#import <Cocoa/Cocoa.h>

#import "Packet.h"

@class Stream;

/**
 *  This class is used internally by both the Stream and the ExtSocket class.
 *  A user of the library should not create an instance of this class.
 */
@interface OpenRequest : NSObject {
    Stream *m_stream;
    NSUInteger m_addr;
    Packet *m_packet;
    BOOL m_sent;
}

- (id) initWith:(Stream*)stream addr:(NSUInteger)addr packet:(Packet*)packet;

@property (readonly,getter=stream) Stream *m_stream;
@property (readonly,getter=addr) NSUInteger m_addr;
@property (readonly,getter=packet) Packet *m_packet;
@property (getter=sent,setter=setSent:) BOOL m_sent;

@end
