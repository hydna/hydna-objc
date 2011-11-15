//
//  ChannelError.m
//  hydna-objc
//

#import "ChannelError.h"

@implementation ChannelError

+ (NSString*) fromOpenError:(NSInteger)flag data:(NSString*)data
{
    NSString *msg;
    
    if (data != @"" || [ data length ] != 0) {
        msg = data;
    } else if (flag < 7) {
		msg = @"Not allowed to open channel";
    }
    
    return msg;
}
    
+ (NSString*) fromSigError:(NSInteger)flag data:(NSString*)data
{
    NSString *msg;
    
    if (data != @"" || [ data length ] != 0) {
        msg = data;
    } else if (flag == 0) {
		msg = @"Bad signal";    
    }
    
    return msg;
}

@end
