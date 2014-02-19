//
//  OpenRequest.h
//  hydna-objc
//

#import "HYFrame.h"

@class HYChannel;

/**
 *  This class is used internally by both the Channel and the Connection class.
 *  A user of the library should not create an instance of this class.
 */
@interface HYOpenRequest : NSObject

@property (nonatomic, strong, readonly,getter=channel) HYChannel *m_channel;
@property (readonly,getter=ch) NSUInteger m_ch;
@property (nonatomic, strong, readonly,getter=frame) HYFrame *m_frame;
@property (nonatomic, strong, readonly,getter=path) NSString *m_path;
@property (nonatomic, strong, readonly,getter=token) NSString *m_token;
@property (getter=sent,setter=setSent:) BOOL m_sent;
    

- (id)initWith:(HYChannel *)channel
            ch:(NSUInteger)ch
          path:(NSString *)path
         token:(NSString *)token
         frame:(HYFrame *)frame;


@end
