//
//  listener.m
//  hydna-objc
//

#import "Stream.h"
#import "StreamData.h"

int main(int argc, const char* argv[])
{
    NSAutoreleasePool *pool = [[ NSAutoreleasePool alloc ] init ];
    
    Stream *stream = [[ Stream alloc ] init ];
    [ stream connect:@"localhost/x11221133" mode:READWRITE token:nil ];
    
    while (![ stream isConnected ]) {
        [ stream checkForStreamError ];
        sleep(1);
    }
    
    for (;;) {
        if (![ stream isDataEmpty ]) {
            StreamData* data = [ stream popData ];
            NSData *payload = [ data content ];
            
            NSString *message = [[ NSString alloc ] initWithData:payload encoding:NSUTF8StringEncoding];
            printf("%s\n", [ message UTF8String ]);
            
            [ message release ];
        } else {
            [ stream checkForStreamError ];
        }
    }
    
    [ stream close ];
    [ stream release ];
    [ pool release ];
}
