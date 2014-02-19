//
//    URL.h
//    hydna-objc
//


@interface HYURL : NSObject {
    NSUInteger m_port;
    NSString *m_path;
    NSString *m_host;
    NSString *m_token;
    NSString *m_auth;
    NSString *m_protocol;
    NSString *m_error;
}

- (id)initWithExpr:(NSString *)expr;

@property (readonly, getter=port) NSUInteger m_port;
@property (readonly, getter=path) NSString *m_path;
@property (readonly, getter=host) NSString *m_host;
@property (readonly, getter=token) NSString *m_token;
@property (readonly, getter=auth) NSString *m_auth;
@property (readonly, getter=protocol) NSString *m_protocol;
@property (readonly, getter=error) NSString *m_error;

@end
