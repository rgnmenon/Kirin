//
//  NativeContext.m
//  KirinKit
//
//  Created by James Hugman on 22/12/2011.
//  Copyright 2011 Future Platforms. All rights reserved.
//

#import "NativeContext.h"
#import "JSON.h"
#import "NativeObjectHolder.h"
#import <UIKit/UIApplication.h>

@interface NativeContext () 

@property(nonatomic, retain) NSMutableDictionary* nativeObjects;
    
@end


@implementation NativeContext

@synthesize nativeObjects = nativeObjects_;

- (id) init {
    return [self initWithDictionary: [NSMutableDictionary dictionary]]; 
}

- (id) initWithDictionary: (NSMutableDictionary*) nativeObjs {
    self = [super init];
    if (self) {
        self.nativeObjects = nativeObjs;
    }
    return self;
}

- (NSArray*) methodNamesFor: (NSString*) moduleName {
    NativeObjectHolder* holder = [self.nativeObjects objectForKey:moduleName];
    if (!holder) {
        [NSException raise:@"KirinNoSuchObjectException" format:@"There is no object registered called %@", moduleName];
    }
    return [holder methodNames];
}

- (void) registerNativeObject: (id) object asName: (NSString*) name {
    [self.nativeObjects setValue:[NativeObjectHolder holderForObject:object] forKey:name];
}

- (void) unregisterNativeObject: (NSString*) name {
    if (name) {
        [self.nativeObjects removeObjectForKey:name];
    }
}

- (void) endBackgroundTask: (UIBackgroundTaskIdentifier) taskId {
     [[UIApplication sharedApplication] endBackgroundTask:taskId];
}

- (void) executeCommandFromModule: (NSString*) host andMethod: (NSString*) fullMethodName andArgsList: (NSString*) query {
    NativeObjectHolder* holder = [self.nativeObjects objectForKey:host];
    id obj = holder ? holder.nativeObject : nil;
    
	SEL selector = [holder findSelectorFromString:fullMethodName];
	if (obj && [obj respondsToSelector:selector]) {

        dispatch_queue_t queue = holder.dispatchQueue;
        BOOL isOnMainThread = queue == nil;
        void (^block)(void) = ^{
            
            // we're going to want to have this running until completion. 
            // This is only sensible if extensions don't last very long for any given task.
            // TODO expose some API such the extension can do long running stuff without risking 
            // being run in the background.
            UIBackgroundTaskIdentifier taskId = UIBackgroundTaskInvalid;
            if (!isOnMainThread) {
                taskId = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{} ];
            }
            @try {
                NSString* argsJSON = [query stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
                
                NSArray* arguments = [argsJSON JSONValue];
                
                NSMethodSignature* sig = [[obj class] instanceMethodSignatureForSelector:selector];                
                NSInvocation* inv = [NSInvocation invocationWithMethodSignature:sig];
                inv.selector = selector;
                inv.target = obj;
                for (int i=0, max=[arguments count]; i<max; i++) {
                    NSObject* obj = [arguments objectAtIndex:i];
                    [inv setArgument:&obj atIndex:i + 2];
                }
                [inv invoke];

            } @catch (NSException* exception) {
                NSLog(@"Exception while executing %@.%@", host, fullMethodName);
                
                // Create a string based on the exception
                NSString *exceptionMessage = [NSString stringWithFormat:@"%@\nReason: %@\nUser Info: %@", [exception name], [exception reason], [exception userInfo]];
                
                // Always log to console for history
                NSLog(@"Exception raised:\n%@", exceptionMessage);
                NSLog(@"Backtrace: %@", [exception callStackSymbols]);
            }
            if (!isOnMainThread) {
                // we've completed. OR HAVE WE? Javascript callbacks may be running, triggering further background 
                // activity. Let's give JS one second to either launch another native call or close down.
                [self performSelector:@selector(endBackgroundTask:) withObject:[NSNumber numberWithInt:taskId] afterDelay:1];
            }
        };
        

        if (queue) {
            dispatch_async(queue, block);
        } else {
            block();
        }
	} else {                
        // There's no method to call, so throw an error.

         NSString* className = NSStringFromClass([obj class]);

        if (!className) {
            className = host;
        }
        NSLog(@"Class method '%@' not defined in class %@, called from module %@.js", fullMethodName, className, host);
        
        //[NSException raise:NSInternalInconsistencyException format:@"Class method '%@' not defined against class '%@'.", fullMethodName, className];
        
	}
}

- (void) dealloc {
    [self.nativeObjects removeAllObjects];
    self.nativeObjects = nil;
    
    [super dealloc];
}

@end
