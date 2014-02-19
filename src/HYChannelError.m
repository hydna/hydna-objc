//
//  ChannelError.m
//  hydna-objc
//

#import "HYChannelError.h"
#import "HYFrame.h"

@implementation HYChannelError

/*
 If a request to open a channel is denied, if the channel is later closed, or if something goes wrong, the channel will
 closed and a onclose-event is triggered. The event handler takes a single argument — event — with the following properties:
 
 reason (String) the reason the channel was closed.
 hadError (boolean) true if the channel was closed due to an error.
 wasDenied (boolean) true if the request to open the channel was denied.
 wasClean (boolean) true if the channel was cleanly ended (either by calling channel.close() or from a Behavior).
 */

- (id)initWithDesc:(NSString *)reason
          wasClean:(BOOL)clean
          hadError:(BOOL)error
         wasDenied:(BOOL)denied{

    if (!(self = [super init])) {
        return nil;
    }
    
    self.reason = reason;
    self.wasClean = clean;
    self.hadError = error;
    self.wasDenied = denied;
    
    return self;
}


+ (HYChannelError *)errorWithDesc:(NSString *)reason
                       wasClean:(BOOL)clean
                       hadError:(BOOL)error
                      wasDenied:(BOOL)denied{
    
    HYChannelError *err = [[HYChannelError alloc] initWithDesc:reason wasClean:clean hadError:error wasDenied:denied];
    
    return err;
}

+ (HYChannelError*)fromOpenError:(NSInteger)flag
                          data:(NSString *)data
{
    NSString *msg = @"";
    
    HYChannelError * err = [HYChannelError errorWithDesc:msg wasClean:YES hadError:NO wasDenied:YES];
    
    if (![data isEqualToString:@""] || [data length] != 0) {
        msg = data;
    } else {
        msg = @"Not allowed to open channel";
    }
    
    err.reason = msg;
    
    return err;
}
    
+ (HYChannelError*)fromSigError:(NSInteger)flag
                         data:(NSString *)data
{
    NSString *msg = @"";
    
    HYChannelError * err = [HYChannelError errorWithDesc:msg wasClean:NO hadError:YES wasDenied:NO];
    
    if (flag == SIG_END) {
        err.wasClean = YES;
        err.hadError = NO;
        err.wasDenied = NO;
    }
    
    if (![data isEqualToString: @""] || [data length] != 0) {
        msg = data;
    }
    
    err.reason = msg;
    
    return err;
}

@end