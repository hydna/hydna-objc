# Usage

In the following example we open a read/write channel, send a "Hello world!"
when the connection has been established and print received messages to
stdout.
    
    :::objective-c
    #import "Channel.h"
    #import "ChannelData.h"

    int main(int argc, const char* argv[])
    {
        NSAutoreleasePool *pool = [[ NSAutoreleasePool alloc ] init ];
        
        Channel *channel = [[ Channel alloc ] init ];
        [ channel connect:@"demo.hydna.net/x11221133" mode:READWRITE token:nil ];
        
        while (![ channel isConnected ]) {
            [ channel checkForChannelError ];
            sleep(1);
        }
        
        [ channel writeString:@"Hello World" ];
        
        for (;;) {
            if (![ channel isDataEmpty ]) {
                ChannelData* data = [ channel popData ];
                NSData *payload = [ data content ];
                
                NSString *message = [[ NSString alloc ]
                    initWithData:payload encoding:NSUTF8StringEncoding ];
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
