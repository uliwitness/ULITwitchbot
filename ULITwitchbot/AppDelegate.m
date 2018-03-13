//
//  AppDelegate.m
//  ULITwitchbot
//
//  Created by Uli Kusterer on 12.03.18.
//  Copyright © 2018 Uli Kusterer. All rights reserved.
//

#import "AppDelegate.h"
#import "ULIRCChatbot.h"


@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
@property (weak) IBOutlet NSTextField *messageField;
@property (strong) ULIRCChatbot *chatbot;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	self.chatbot = [ULIRCChatbot new];
	self.chatbot.settingsFolderURL = [NSURL fileURLWithPath: [@"~/Library/Application Support/ULITwitchbot/" stringByExpandingTildeInPath]];
	self.chatbot.oauthToken = @"oauth:gctvy5ean6qwtqrwx0lvrluc8si1bv";
	self.chatbot.nickname = @"uliwitness";
	self.chatbot.channelName = @"uliwitness";
	
	NSLog(@"Settings folder: %@", self.chatbot.settingsFolderURL);
	
	[self.chatbot registerHandler:^(NSString *inCommandName, NSString *inNickname, NSString *inMessage, NSString *inPrefix) {
		NSLog(@"%@ BOT COMMAND TRIGGERED", inCommandName);
	} forBotCommand:@"*"];
	
	[self.chatbot registerHandler:^(NSString *inCommandName, NSString *inNickname, NSArray<NSString *> *inParameters, NSString *inPrefix) {
		NSLog(@"[%@] %@: %@", (inParameters.count > 0) ? inParameters[0] : @"", inNickname, (inParameters.count > 1) ? inParameters[1] : @"");
	} forProtocolCommand: @"PRIVMSG"];

	NSError * err = nil;
	[self.chatbot connectReturningError:&err];
	if (err) NSLog(@"%@", err);
}


-(IBAction) sendAMessage: (nullable id)sender
{
	[self.chatbot sendChatMessage: self.messageField.stringValue];
}

@end
