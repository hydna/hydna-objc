//
//  ChannelError.m
//  hydna-objc
//
//  Created by Emanuel Dahlberg on 2/23/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "ChannelError.h"
#import "Packet.h"

@implementation ChannelError

+ (NSString*) fromHandshakeError:(NSInteger)flag
{
    NSString *msg = @"";
    
    switch (flag) {
        case HANDSHAKE_SERVER_BUSY:
            msg = @"Handshake failed, server is busy";
            break;
        case HANDSHAKE_BADFORMAT:
            msg = @"Handshake failed, bad format sent by client";
            break;
        case HANDSHAKE_HOSTNAME:
            msg = @"Handshake failed, invalid hostname";
            break;
        case HANDSHAKE_PROTOCOL:
            msg = @"Handshake failed, protocol not allowed";
            break;
        case HANDSHAKE_SERVER_ERROR:
            msg = @"Handshake failed, server error";
            break;
			
		default:
		case HANDSHAKE_UNKNOWN:
            msg = @"Unknown handshake error";
            break;
    }
    
    return msg;
}

+ (NSString*) fromOpenError:(NSInteger)flag data:(NSString*)data
{
    NSString *msg;
    
    if (data != @"" || [ data length ] != 0) {
        msg = data;
    } else {
        switch (flag) {
            case OPEN_FAIL_NA:
                msg = @"Failed to open channel, not available";
                break;
            case OPEN_FAIL_MODE:
                msg = @"Not allowed to open channel with specified mode";
                break;
            case OPEN_FAIL_PROTOCOL:
                msg = @"Not allowed to open channel with specified protocol";
                break;
            case OPEN_FAIL_HOST:
                msg = @"Not allowed to open channel from host";
                break;
            case OPEN_FAIL_AUTH:
                msg = @"Not allowed to open channel with credentials";
                break;
            case OPEN_FAIL_SERVICE_NA:
                msg = @"Failed to open channel, service is not available";
                break;
            case OPEN_FAIL_SERVICE_ERR:
                msg = @"Failed to open channel, service error";
                break;
                
            default:
            case OPEN_FAIL_OTHER:
                msg = @"Failed to open channel, unknown error";
                break;
        }
    }
    
    return msg;
}
    
+ (NSString*) fromSigError:(NSInteger)flag data:(NSString*)data
{
    NSString *msg;
    
    if (data != @"" || [ data length ] != 0) {
        msg = data;
    } else {
        switch (flag) {
            case SIG_ERR_PROTOCOL:
                msg = @"Protocol error";
                break;
            case SIG_ERR_OPERATION:
                msg = @"Operational error";
                break;
            case SIG_ERR_LIMIT:
                msg = @"Limit error";
                break;
            case SIG_ERR_SERVER:
                msg = @"Server error";
                break;
            case SIG_ERR_VIOLATION:
                msg = @"Violation error";
                break;
                
            default:
            case SIG_ERR_OTHER:
                msg = @"Unknown error";
                break;
        }
    }
    
    return msg;
}

@end