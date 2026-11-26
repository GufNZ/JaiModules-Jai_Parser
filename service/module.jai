// Cache service: the trivia-enabled parser plus the service foundations (CACHE_MIGRATION_PLAN.md phase 2 onwards).

/*
Storage and data flow:

1. `Provider_Model` stores document states and admitted syntax contexts.
	Each document keeps its overlay and disk branches separately; a disk observation can advance the disk branch without replacing the selected overlay.
	`Batch_Staging` holds proposed states and contexts until the entire batch validates.
	Commit transfers their storage to the provider and advances the frontier.

2. `World` stores the selected members of one capture, not a mutable view of the provider.
	Members retain the source backing they selected so replacing a provider branch cannot change input already handed to a task.
	The candidate key lets equivalent requests reuse a world or join its work; the head target separately records which candidate may replace the current head.

3. `Operation` tracks an update, query, or shutdown; `Task` tracks computation that can serve operations.
	`Mailbox` carries the selected task's output back to the coordinator.
	Delivery reconciles the output with current session state before it becomes visible.
	`Registration` connects a generation-checked handle to an operation, world, or result; those objects do not use the public slot as their storage identity.

4. The syntax owner holds the source and parser allocations.
	Token and node projections borrow from that owner; the declaration index borrows from the snapshot.
	IDs refer to positions in the corresponding projection tables, not to parser pointers.
	Release follows the reverse dependency order so borrowed bytes remain valid for the lifetime of the records that use them.

Source admission and publication are separate.
The provider stages a whole batch against an accepted frontier so a rejected edit cannot expose half a workspace.
The coordinator binds computation to a world at one frontier.
An accepted batch can invalidate pending work, but only the current head target can replace the head; completion order must not decide which world readers see.

Syntax work starts with an owned parse, then projects tokens, nodes, recovery, diagnostics, and declaration entries into schema records.
Projection retains explicit evidence of what the parser observed.
When a route cannot be correlated, partial coverage preserves what is known without claiming a successful reconstruction.
Canonical encodings bind identity to logical values rather than native layout, and context descriptors record which producer and inputs gave those values meaning.

A session gate serializes admission, publication, and reference changes.
Worker computation and recursive destruction happen outside it so expensive work or callbacks do not block access to session state.
Handles, pins, and retirement queues separate public visibility from storage lifetime: removing a handle or superseding a world does not make storage safe to free while a caller holds it.
*/

// `TEST_HOOKS` exposes deterministic execution and barriers; `REAL_WORKER` retains native execution in a hooks build.  Neither changes payload semantics.
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

#load "canonical.jai";		// digest: adapter
#load "context.jai";		// digest: adapter
#load "coordinator.jai";
#load "diagnostics.jai";	// digest: adapter
#load "digest.jai";			// digest: adapter
#load "epoch.jai";
#load "host.jai";
#load "identity.jai";
#load "index.jai";			// digest: adapter
#load "limits.jai";
#load "nodes.jai";			// digest: adapter
#load "ownership.jai";
#load "projection.jai";		// digest: adapter
#load "provider.jai";
#load "snapshot.jai";		// digest: adapter
#load "worker.jai";
