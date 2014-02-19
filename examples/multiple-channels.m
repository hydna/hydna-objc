//
//  multiple-channels.m
//  hydna-objc
//

#import "HYChannel.h"

int main(int argc, const char* argv[])
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc ] init];
    
    HYChannel *channel = [[HYChannel alloc ] init];
    [channel connect:@"public.hydna.net/first-hello" mode:READWRITE token:nil];
    
	HYChannel *channel2 = [[HYChannel alloc ] init];
    [channel2 connect:@"public.hydna.net/second-hello" mode:READWRITE token:nil];
	
    while (![ channel isConnected ]) {
        [channel checkForChannelError];
        sleep(1);
    }
	
	while (![ channel2 isConnected ]) {
        [channel2 checkForChannelError];
        sleep(1);
    }
    
    [channel writeString:@"Hello"];
	[channel2 writeString:@"World"];
    
    for (;;) {
        if (![channel isDataEmpty]) {
            ChannelData* data = [channel popData];
            NSData *payload = [data content];
            
            NSString *message = [[NSString alloc] initWithData:payload encoding:NSUTF8StringEncoding];
            printf("%s\n", [message UTF8String]);
            
            [message release];
            break;
        } else {
            [channel checkForChannelError];
        }
    }
	
	for (;;) {
        if (![ channel2 isDataEmpty ]) {
            ChannelData *data = [channel2 popData];
            NSData *payload = [data content];
            
            NSString *message = [[NSString alloc] initWithData:payload encoding:NSUTF8StringEncoding];
            printf("%s\n", [message UTF8String]);
            
            [message release];
            break;
        } else {
            [channel2 checkForChannelError];
        }
    }
    
    [channel close];
    [channel release];
    [channel2 close];
    [channel2 release ];
    [pool release];
}