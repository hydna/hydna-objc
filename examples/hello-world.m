//
//  hello-world.m
//  hydna-objc
//

#import "HYChannel.h"

int main(int argc, const char* argv[])
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    HYChannel *channel = [[HYChannel alloc ] init];
    [channel connect:@"public.hydna.net/hello" mode:READWRITE token:nil];
    
    while (![channel isConnected]) {
        [channel checkForChannelError];
        sleep(1);
    }
	
	NSString *welcomeMessage = [channel message];
	if (![welcomeMessage isEqualToString:@""]) {
		printf("%s\n", [welcomeMessage UTF8String]);
	}
    
    [channel writeString:@"Hello World from obj-c"];
    
    for (;;) {
        if (![ channel isDataEmpty ]) {
            ChannelData *data = [channel popData];
            NSData *payload = [data content];
            
            if([data isUtf8Content]){
                NSString *message = [[NSString alloc] initWithData:payload encoding:NSUTF8StringEncoding];
                printf("%s\n", [message UTF8String]);
                [message release];
            }else{
                printf("%s\n", "binary packet...");
            }
            
            break;
        } else {
            [channel checkForChannelError];
        }
    }
    
    [channel close];
    [channel release];
    [pool release];
}