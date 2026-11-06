// Cache service: the trivia-enabled parser plus the service foundations (CACHE_MIGRATION_PLAN.md phase 2 onwards).

// `TEST_HOOKS` exposes deterministic execution and barriers; `REAL_WORKER` retains native execution in a hooks build. Neither changes payload semantics.
#module_parameters(TEST_HOOKS := false, REAL_WORKER := false);

#add_context cache_service_output_allocator: Allocator;

Parser :: #import "Jai_Parser"(ENABLE_TRIVIA = true);

#import "Basic";
#import "Atomics";
#import "File";
#import "File_Utilities";
#import "Hash_Table";
#import "Pool";
#import "String";
#import "Thread"(LOAD_THREAD_GROUP = false);
#import "meow_hash";

#if OS == .WINDOWS {
	#import "Windows";
	#import "Windows_Utf8";
} else #if OS == .LINUX || OS == .MACOS {
	#import "POSIX";
}

#load "canonical.jai";
#load "context.jai";
#load "coordinator.jai";
#load "diagnostics.jai";
#load "digest.jai";
#load "epoch.jai";
#load "host.jai";
#load "identity.jai";
#load "index.jai";
#load "limits.jai";
#load "nodes.jai";
#load "ownership.jai";
#load "projection.jai";
#load "provider.jai";
#load "snapshot.jai";
#load "worker.jai";
