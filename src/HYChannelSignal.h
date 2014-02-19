//
//  ChannelSignal.h
//  hydna-objc
//

#import "HYFrame.h"


@interface HYChannelSignal : NSObject {
    NSInteger m_type;
    NSData *m_content;
    BOOL m_binary;
}

- (id)initWithType:(NSInteger)type
             ctype:(NSUInteger)ctype
           content:(NSData *)content;

- (BOOL)isBinaryContent;
- (BOOL)isUtf8Content;

@property (readonly, getter=type) NSInteger m_type;
@property (readonly, getter=content) NSData *m_content;

@end
