//
//  ChannelError.h
//  hydna-objc
//


@interface ChannelError : NSObject

+ (NSString*) fromOpenError:(NSInteger)flag data:(NSString*)data;
+ (NSString*) fromSigError:(NSInteger)flag data:(NSString*)data;

@end
