//
//  OpenRequest.h
//  hydna-objc
//

#import <Cocoa/Cocoa.h>

#import "Packet.h"

@class Channel;

/**
 *  This class is used internally by both the Channel and the ExtSocket class.
 *  A user of the library should not create an instance of this class.
 */
@interface OpenRequest : NSObject {
    Channel *m_channel;
    NSUInteger m_ch;
    Packet *m_packet;
    BOOL m_sent;
}

- (id) initWith:(Channel*)channel ch:(NSUInteger)ch packet:(Packet*)packet;

@property (readonly,getter=channel) Channel *m_channel;
@property (readonly,getter=ch) NSUInteger m_ch;
@property (readonly,getter=packet) Packet *m_packet;
@property (getter=sent,setter=setSent:) BOOL m_sent;

@end
