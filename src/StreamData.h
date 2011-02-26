//
//  StreamData.h
//  hydna-objc
//

#import <Cocoa/Cocoa.h>


@interface StreamData : NSObject {
    NSInteger m_priority;
    NSData *m_content;
}

- (id) initWithPriority:(NSInteger)priority content:(NSData *)content;

@property (readonly, getter=priority) NSInteger m_priority;
@property (readonly, getter=content) NSData *m_content;

@end
