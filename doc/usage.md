# Usage

In the following example we open a read/write stream, send a "Hello world!"
when the connection has been established and print received messages to
stdout.
    
    :::objective-c
    #import "Stream.h"
    #import "StreamData.h"

    int main(int argc, const char* argv[])
    {
        NSAutoreleasePool *pool = [[ NSAutoreleasePool alloc ] init ];
        
        Stream *stream = [[ Stream alloc ] init ];
        [ stream connect:@"demo.hydna.net/x11221133" mode:READWRITE token:nil ];
        
        while (![ stream isConnected ]) {
            [ stream checkForStreamError ];
            sleep(1);
        }
        
        [ stream writeString:@"Hello World" ];
        
        for (;;) {
            if (![ stream isDataEmpty ]) {
                StreamData* data = [ stream popData ];
                NSData *payload = [ data content ];
                
                NSString *message = [[ NSString alloc ]
                    initWithData:payload encoding:NSUTF8StringEncoding ];
                printf("%s\n", [ message UTF8String ]);
                
                [ message release ];
                break;
            } else {
                [ stream checkForStreamError ];
            }
        }
        
        [ stream close ];
        [ stream release ];
        [ pool release ];
    }
