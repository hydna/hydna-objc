//
//  speed-test.m
//  hydna-objc
//

#import "Channel.h"
#import "ChannelData.h"

#import <sys/time.h>

static const unsigned int NO_BROADCASTS = 100000;
static NSString *CONTENT = @"fjhksdffkhjfhjsdkahjkfsadjhksfjhfsdjhlasfhjlksadfhjldaljhksfadjhsfdahjsljhdfjlhksfadlfsjhadljhkfsadjlhkajhlksdfjhlljhsa";

int getmicrosec() {
    int result = 0;
    struct timeval tv;
    gettimeofday(&tv, (void *)NULL);
    
    result += (tv.tv_sec - 0) * 1000000;
    result += (tv.tv_usec - 0);
    
    return result;
}

int main(int argc, const char* argv[])
{
    NSAutoreleasePool *pool = [[ NSAutoreleasePool alloc ] init ];
    
    if (argc != 2) {
        printf("Usage: %s {receive|send}\n", argv[0]);
        return -1;
    }
    
    unsigned int i = 0;
    
    @try {
        Channel *channel = [[ Channel alloc ] init ];
        [ channel connect:@"localhost:7010/x11221133" mode:READWRITE token:nil ];
        
        while (![ channel isConnected ]) {
            [ channel checkForChannelError ];
            sleep(1);
        }
        
        int time = 0;
        
        if (strcmp(argv[1], "receive") == 0) {
            printf("Receiving from x11221133\n");
            
            for (;;) {
                if (![ channel isDataEmpty ]) {
                    [ channel popData ];
                    
                    if (i == 0) {
                        time = getmicrosec();
                    }
                    
                    ++i;
                    
                    if (i == NO_BROADCASTS) {
                        time = getmicrosec() - time;
                        printf("\nReceived %u frames\n", i);
                        printf("Time: %i ms\n", time/1000);
                        i = 0;
                    }
                } else {
                    [ channel checkForChannelError ];
                }
            }
        } else if (strcmp(argv[1], "send") == 0) {
            printf("Sending %u frames to x11221133\n", NO_BROADCASTS);
            
            time = getmicrosec();
            
            for (i = 0; i < NO_BROADCASTS; i++) {
                [ channel writeString:CONTENT ];
            }
            
            time = getmicrosec() - time;
            
            printf("Time: %i ms\n", time/1000);
            
            i = 0;
            while (i < NO_BROADCASTS) {
                if (![ channel isDataEmpty ]) {
                    [ channel popData ];
                    ++i;
                } else {
                    [ channel checkForChannelError ];
                }
            }
        } else {
            printf("Usage: %s {receive|send}\n", argv[0]);
            return -1;
        }
        
        [ channel close ];
        [ channel release ];
    }
    @catch(NSException *e) {
        printf("Caught exception (i=%u): %s %s\n", i, [[ e name ] UTF8String ], [[ e reason ] UTF8String ]);
    }
    
    [ pool release ];
}
