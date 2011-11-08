//
//  ChannelError.h
//  hydna-objc
//

#import <Cocoa/Cocoa.h>


@interface ChannelError : NSObject

+ (NSString*) fromHandshakeError:(NSInteger)flag;
+ (NSString*) fromOpenError:(NSInteger)flag data:(NSString*)data;
+ (NSString*) fromSigError:(NSInteger)flag data:(NSString*)data;

@end
