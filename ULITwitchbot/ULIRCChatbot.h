//
//  ULIRCChatbot.h
//  ULITwitchbot
//
//  Created by Uli Kusterer on 12.03.18.
//  Copyright © 2018 Uli Kusterer. All rights reserved.
//

#import <Foundation/Foundation.h>


typedef void (^ULIRCProtocolCommandHandler)(NSString *inCommandName, NSString *inNickname, NSArray<NSString *> *inParameters, NSString *inPrefix, NSDictionary *inTags);

typedef void (^ULIRCBotCommandHandler)(NSString *inCommandName, NSString *inNickname, NSString *inMessage, NSString *inPrefix, NSDictionary *inTags);


@interface ULIRCChatbot : NSObject

@property (copy) NSString *oauthToken;
@property (copy) NSString *nickname;
@property (copy) NSString *channelName;
@property (strong) NSURL *settingsFolderURL;

-(void) connectReturningError: (NSError **)outError;
-(void) disconnect;

-(void) sendChatMessage: (NSString *)text;

-(void) registerHandler: (ULIRCBotCommandHandler)inHandler forBotCommand: (NSString*)botCommand; // Custom command in a PRIVMSG chat message (like !dead or !addquote without the "!"). Register "*" if you want to receive all commands that don't have a handler.

-(void) registerHandler: (ULIRCProtocolCommandHandler)inHandler forProtocolCommand: (NSString *)inIRCCommandName; // Low-level IRC command. Register "*" if you want to receive all commands that don't have a handler.

@end
