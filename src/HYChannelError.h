//
//  ChannelError.h
//  hydna-objc
//


@interface HYChannelError : NSObject

/*
 If a request to open a channel is denied, if the channel is later closed, or if something goes wrong, the channel will
 closed and a onclose-event is triggered. The event handler takes a single argument — event — with the following properties:
 
 reason (String) the reason the channel was closed.
 hadError (boolean) true if the channel was closed due to an error.
 wasDenied (boolean) true if the request to open the channel was denied.
 wasClean (boolean) true if the channel was cleanly ended (either by calling channel.close() or from a Behavior).
 */

@property(nonatomic, strong) NSString *reason;
@property(nonatomic) BOOL wasClean;
@property(nonatomic) BOOL hadError;
@property(nonatomic) BOOL wasDenied;

+ (HYChannelError *)fromOpenError:(NSInteger)flag
                           data:(NSString *)data;

+ (HYChannelError *)fromSigError:(NSInteger)flag
                          data:(NSString *)data;

+ (HYChannelError *)errorWithDesc:(NSString *)reason
                       wasClean:(BOOL)wasClean
                       hadError:(BOOL)hadError
                      wasDenied:(BOOL)wasDenied;

@end
