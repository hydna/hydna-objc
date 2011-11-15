//
//  OpenRequest.h
//  hydna-objc
//

#import <Cocoa/Cocoa.h>

#import "Frame.h"

@class Channel;

/**
 *  This class is used internally by both the Channel and the Connection class.
 *  A user of the library should not create an instance of this class.
 */
@interface OpenRequest : NSObject {
    Channel *m_channel;
    NSUInteger m_ch;
    Frame *m_frame;
    BOOL m_sent;
}

- (id) initWith:(Channel*)channel ch:(NSUInteger)ch frame:(Frame*)frame;

@property (readonly,getter=channel) Channel *m_channel;
@property (readonly,getter=ch) NSUInteger m_ch;
@property (readonly,getter=frame) Frame *m_frame;
@property (getter=sent,setter=setSent:) BOOL m_sent;

@end
