//
//  StreamSignal.h
//  hydna-objc
//

#import <Cocoa/Cocoa.h>


@interface StreamSignal : NSObject {
    NSInteger m_type;
    NSData *m_content;
}

- (id) initWithType:(NSInteger)type content:(NSData*)content;

@property (readonly, getter=type) NSInteger m_type;
@property (readonly, getter=content) NSData *m_content;

@end
