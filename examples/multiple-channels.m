//
//  multiple-channels.m
//  hydna-objc
//

#import "Channel.h"
#import "ChannelData.h"

int main(int argc, const char* argv[])
{
    NSAutoreleasePool *pool = [[ NSAutoreleasePool alloc ] init ];
    
    Channel *channel = [[ Channel alloc ] init ];
    [ channel connect:@"public.hydna.net/1" mode:READWRITE token:nil ];
    
	Channel *channel2 = [[ Channel alloc ] init ];
    [ channel2 connect:@"public.hydna.net/2" mode:READWRITE token:nil ];
	
    while (![ channel isConnected ]) {
        [ channel checkForChannelError ];
        sleep(1);
    }
	
	while (![ channel2 isConnected ]) {
        [ channel2 checkForChannelError ];
        sleep(1);
    }
    
    [ channel writeString:@"Hello" ];
	[ channel2 writeString:@"World" ];
    
    for (;;) {
        if (![ channel isDataEmpty ]) {
            ChannelData* data = [ channel popData ];
            NSData *payload = [ data content ];
            
            NSString *message = [[ NSString alloc ] initWithData:payload encoding:NSUTF8StringEncoding];
            printf("%s\n", [ message UTF8String ]);
            
            [ message release ];
            break;
        } else {
            [ channel checkForChannelError ];
        }
    }
	
	for (;;) {
        if (![ channel2 isDataEmpty ]) {
            ChannelData* data = [ channel2 popData ];
            NSData *payload = [ data content ];
            
            NSString *message = [[ NSString alloc ] initWithData:payload encoding:NSUTF8StringEncoding];
            printf("%s\n", [ message UTF8String ]);
            
            [ message release ];
            break;
        } else {
            [ channel2 checkForChannelError ];
        }
    }
    
    [ channel close ];
    [ channel release ];
    [ channel2 close ];
    [ channel2 release ];
    [ pool release ];
}