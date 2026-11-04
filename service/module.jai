// Cache service: the trivia-enabled parser plus the service foundations (CACHE_MIGRATION_PLAN.md phase 2 onwards).

Parser :: #import "Jai_Parser"(ENABLE_TRIVIA = true);

#import "Basic";
#import "String";
#import "meow_hash";

#if OS == .WINDOWS {
	#import "Windows";
	#import "Windows_Utf8";
}

#load "canonical.jai";
#load "digest.jai";
#load "identity.jai";
#load "limits.jai";
#load "epoch.jai";
