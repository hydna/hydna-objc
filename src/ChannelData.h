//
//  ChannelData.h
//  hydna-objc
//

#import <Cocoa/Cocoa.h>


@interface ChannelData : NSObject {
    NSInteger m_priority;
    NSData *m_content;
    BOOL m_binary;
}

- (id) initWithPriority:(NSInteger)priority content:(NSData *)content;
- (BOOL) isBinaryContent;
- (BOOL) isUtf8Content;

@property (readonly, getter=priority) NSInteger m_priority;
@property (readonly, getter=content) NSData *m_content;
@property (readonly, getter=binary) BOOL m_binary;

@end
