//
//  AppDelegate.h
//  ULITwitchbot
//
//  Created by Uli Kusterer on 12.03.18.
//  Copyright © 2018 Uli Kusterer. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>

-(IBAction)	establishConnection:(nullable id)sender;
-(IBAction) openTokenPageURL: (nullable id)sender;

@end

