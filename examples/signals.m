//
//  signals.m
//  hydna-objc
//

#import "Channel.h"
#import "ChannelSignal.h"

int main(int argc, const char* argv[])
{
    NSAutoreleasePool *pool = [[ NSAutoreleasePool alloc ] init ];
    
    Channel *channel = [[ Channel alloc ] init ];
    [ channel connect:@"public.hydna.net/hello" mode:READWRITEEMIT token:nil ];
    
    while (![ channel isConnected ]) {
        [ channel checkForChannelError ];
        sleep(1);
    }
	
	NSString *welcomeMessage = [ channel message ];
	if (![ welcomeMessage isEqualToString:@"" ]) {
		printf("%s\n", [ welcomeMessage UTF8String ]);
	}
    
    [ channel emitString:@"ping" ];
    
    for (;;) {
        if (![ channel isSignalEmpty ]) {
            ChannelSignal* signal = [ channel popSignal ];
            NSData *payload = [ signal content ];
            
            NSString *message = [[ NSString alloc ] initWithData:payload encoding:NSUTF8StringEncoding];
            printf("%s\n", [ message UTF8String ]);
            
            [ message release ];
            break;
        } else {
            [ channel checkForChannelError ];
        }
    }
    
    [ channel close ];
    [ channel release ];
    [ pool release ];
}
