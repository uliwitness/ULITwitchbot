# ULITwitchbot

## What is it?

A simple application that will "listen" to the chat in a Twitch channel and react to certain keywords. or periodically do things.

## How do I use it?

Launch the app, enter your account and channel's name and your Twitch OAuth token. Then click "Connect".
The bot now listens to the chat as if it was you, and will post its replies as your account.

The commands it understands are defined in the Application Support folder. Bot commands follow
the Twitch convention of having to be one word prefixed with an exclamation mark (like "!dead").

*Note:* It is considered rude to install a bot on someone else's channel without their permission, and could lead to undesired interactions if they already have a bot listening for the same commands. The option to listen to a channel that is not that of your account is intended for people who create a dedicated account for their own channel's bot and make it a moderator.

### What command types are currently supported?

Currently, the chatbot can create counters that increment each time their command is triggered, periodically post text or trigger commands, and handle commands that pick and post a random line of text from a text file and post it (e.g. for quotes), and allow users to add lines of text to that file.

### Commands in General

Commands are defined by adding a folder with the name of the command to `~/Library/Application Support/ULITwitchbot/Commands/` and placing an Info.plist file in a subfolder of it that contains the settings for the command. Every command has at the least a type, specified using the `ULIRCCommandType` key.

#### Commands of type "counter"

A counter command will increment a count, which is saved across bot restarts, in `~/Library/Application Support/ULITwitchbot/Counters.plist`. A counter starts at 0, and increments by 1 each time the command is triggered.

A counter also implements a second command that can be used to just query the counter value without incrementing it.

`ULIRCQueryCommandName` - Specify the name of the command here that should be used to query the counter without incrementing it. If this key is missing, the command name is used, with "count" appended. So if you named your command "dead", the query command will be named "deadcount".

`ULIRCCommandMessage` - The message to display when either command is triggered. If you do not provide a message, a default message of "%CHANNEL% has a %COMMANDNAME% count of %COUNT%." will be used. If you use any or all of the three placeholders `%CHANNEL%`, `%COMMANDNAME%` or `%COUNT%`. They will automatically be replaced with the requisite values.

#### Commands of type "quote"

A quote command looks for a text file named the same as the command and randomly displays lines from this file. So for example, if you named the command's folder "joke", it will look for a file named `~/Library/Application Support/ULITwitchbot/Quotes/joke.txt` and display a random line from that whenever a user types "!joke". If you specify a number after the command, e.g. "!joke 5", it will display the fifth line from that file instead.

`ULIRCEditable` - Specify a boolean (either YES or NO) under this name in the command's Info.plist file to also add an "add"-command for the command, which chatters can use to add additional lines to this text file. If you name your command "joke", this option will add both a "joke" command and an "addjoke" command.

#### Commands of type "message"

A message command posts a certain message, filling in placeholders, if desired periodically. This is useful for command aliases, shortcuts, periodic reminders or announcements, or for triggering commands in both ULITwitchbot or another, external bot.

`ULIRCMessage` - The message to post. This can be any text the bot's user can type in chat. If the message uses the placeholders `%COUNT%`, `%COMMANDNAME`, `%CHANNEL%`, `%LASTUSETIME%` or `%LASTUSEINTERVAL%`, those will work just like with the "counter" command above, except that `%COUNT%` will automatically increment the given counter, and will use the name of this command as the counter name (i.e. the name of the command's folder). You can also specify `%1%`, `%2%` etc. to have any parameter given to the command inserted in its place.

`ULIRCInterval` - An interval (in seconds) at which the message will be posted. So if you specify `3600` here, the message will be repeatedly posted, once every hour. `1800` means every half hour etc. If this is missing or 0, the message will only be posted once after the initial interval has elapsed, if an initial interval > 0  has been given. Or of course, when a user types in the command name.

`ULIRCInitialInterval` - An interval that has to elapse after the bot starts up before this message is sent the first time. If your message is posted periodically (see `ULIRCInterval`), you can use this to stagger different messages, e.g. if you want a message every half hour, and you have three different messages, you can use an interval of 1.5 hours (`5400`) for each, and have the second with an initial interval of `1800`, the third by `3600`. If the message does not repeat, the message will simply be posted once, after this delay. You can use this to e.g. remind yourself and viewers to drink, or take a break, or whatever, at a fixed time into your stream.

`ULIRCQuietly` - If you are using the `message` command trigger another command in ULITwitchBot, you can set this property to the boolean `YES` to have ULITwitchbot just process the given message internally without actually posting it. This way, you can define an alternate name for an existing command, or define a number of "internal" commands whose purpose is just to be triggered periodically by a message, but users don't see the internal command names. Of course, if a user, or another bot is *supposed* to see this message, you want to not set this key, or specify `NO`.


## License

Copyright 2018 by Uli Kusterer.

This software is provided 'as-is', without any express or implied
warranty. In no event will the authors be held liable for any damages
arising from the use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it
freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not
claim that you wrote the original software. If you use this software
in a product, an acknowledgment in the product documentation would be
appreciated but is not required.

2. Altered source versions must be plainly marked as such, and must not be
misrepresented as being the original software.

3. This notice may not be removed or altered from any source
distribution.



