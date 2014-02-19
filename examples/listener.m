//
//  listener.m
//  hydna-objc
//

#import "HYChannel.h"

int main(int argc, const char* argv[])
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc ] init];
    
    Channel *channel = [[Channel alloc ] init];
    [channel connect:@"public.hydna.net/hello" mode:READWRITE token:nil];
    
    while (![channel isConnected]) {
        [channel checkForChannelError];
        sleep(1);
    }
    
    for (;;) {
        if (![channel isDataEmpty]) {
            ChannelData* data = [channel popData];
            NSData *payload = [data content];
            
            NSString *message = [[NSString alloc] initWithData:payload encoding:NSUTF8StringEncoding];
            printf("%s\n", [message UTF8String]);
            
            [message release];
        } else {
            [channel checkForChannelError];
        }
    }
    
    [channel close];
    [channel release];
    [pool release];
}
