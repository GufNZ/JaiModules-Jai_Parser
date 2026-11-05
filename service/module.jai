// Cache service: the trivia-enabled parser plus the service foundations (CACHE_MIGRATION_PLAN.md phase 2 onwards).

Parser :: #import "Jai_Parser"(ENABLE_TRIVIA = true);

#import "Basic";
#import "Hash_Table";
#import "Pool";
#import "String";
#import "meow_hash";

#if OS == .WINDOWS {
	#import "Windows";
	#import "Windows_Utf8";
} else #if OS == .LINUX || OS == .MACOS {
	#import "POSIX";
}

#load "canonical.jai";
#load "diagnostics.jai";
#load "digest.jai";
#load "epoch.jai";
#load "identity.jai";
#load "index.jai";
#load "limits.jai";
#load "nodes.jai";
#load "projection.jai";
#load "snapshot.jai";
