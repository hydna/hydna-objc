//
//  ChannelData.h
//  hydna-objc
//

#import "HYFrame.h"


@interface HYChannelData : NSObject {
    NSInteger m_priority;
    BOOL m_binary;
}

- (id)initWithPriority:(NSInteger)priority
               content:(NSData *)content
                 ctype:(NSUInteger)ctype;

- (BOOL)isBinaryContent;
- (BOOL)isUtf8Content;

@property (readonly, getter=priority) NSInteger m_priority;
@property (readonly, getter=content) NSData *m_content;
@property (readonly, getter=binary) BOOL m_binary;

@end
