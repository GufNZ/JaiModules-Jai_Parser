// Limit negotiation and the reservation ledger (CACHE_CONTRACTS.md milestone 2 "Required Limit Negotiation", milestone 4 "Reservation Ledger").

Limit_Name :: enum u8 {
	VALUE_BYTES;
	SOURCE_BYTES;
	PATH_BYTES;
	KEY_BYTES;
	MESSAGE_BYTES;
	REQUEST_BYTES;
	BATCH_EVENTS;
	EDITS_PER_EVENT;
	CAPTURE_DOCUMENTS;
	RECORDS_PER_PAYLOAD;
	ELEMENTS_PER_LIST;
	NESTING_DEPTH;
	LIVE_HANDLES;
	PENDING_REGISTRATIONS;
	COMPLETION_RECORDS;
	RETAINED_SOURCE_BYTES;
	OWNED_BYTES;
	CONCURRENT_ACQUISITIONS;
	IN_FLIGHT_OPERATIONS;
}

LIMIT_COUNT :: #run enum_names(Limit_Name).count;

NO_CONFIGURED_QUOTA :: -1;

Limits :: struct {
	values: [LIMIT_COUNT] s64;
}

Limit_Request :: struct {
	values: [LIMIT_COUNT] s64 = #run no_quota_values();
}

#scope_file
no_quota_values :: () -> [LIMIT_COUNT] s64 {
	result: [LIMIT_COUNT] s64;
	for * result {
		it.* = NO_CONFIGURED_QUOTA;
	}

	return result;
}
#scope_export

Limit_Failure :: enum u8 {
	NONE;
	INVALID_ARGUMENT;
	LIMIT;
}

// `-1` selects the implementation ceiling; a configured value is clamped to the ceiling, and one below the safe minimum rejects rather than being raised.
negotiate_limits :: (request: Limit_Request, ceilings: Limits, minima: Limits) -> Limit_Failure, Limits, Limit_Name {
	effective: Limits;
	for request.values {
		name := it_index.(Limit_Name);
		if it < NO_CONFIGURED_QUOTA {
			return .INVALID_ARGUMENT, .{}, name;
		}


		if it == NO_CONFIGURED_QUOTA {
			effective.values[it_index] = ceilings.values[it_index];
			continue;
		}


		if it < minima.values[it_index] {
			return .LIMIT, .{}, name;
		}


		effective.values[it_index] = min(it, ceilings.values[it_index]);
	}


	return .NONE, effective, .VALUE_BYTES;
}

within_limit :: (limits: Limits, name: Limit_Name, value: s64) -> bool {
	return value >= 0 && value <= limits.values[name];
}

// Aggregate accounting: live + reserved + requested must stay within each effective limit.
Resource_Ledger :: struct {
	limits: Limits;
	live: [LIMIT_COUNT] s64;
	reserved: [LIMIT_COUNT] s64;
}

Ledger_Amount :: struct {
	name: Limit_Name;
	amount: s64;
}

// All-or-nothing: either every amount is reserved or none is.
reserve :: (ledger: *Resource_Ledger, amounts: .. Ledger_Amount) -> bool {
	pending: [LIMIT_COUNT] s64;
	for amounts {
		if it.amount < 0 || it.amount > S64_MAX - pending[it.name] {
			return false;
		}


		pending[it.name] += it.amount;
	}


	for pending {
		used := ledger.live[it_index] + ledger.reserved[it_index];
		if it > ledger.limits.values[it_index] - used {
			return false;
		}
	}


	for pending {
		ledger.reserved[it_index] += it;
	}

	return true;
}

commit_reserved :: (ledger: *Resource_Ledger, name: Limit_Name, amount: s64) {
	assert(amount >= 0 && amount <= ledger.reserved[name]);
	ledger.reserved[name] -= amount;
	ledger.live[name] += amount;
}

release_reserved :: (ledger: *Resource_Ledger, name: Limit_Name, amount: s64) {
	assert(amount >= 0 && amount <= ledger.reserved[name]);
	ledger.reserved[name] -= amount;
}

release_live :: (ledger: *Resource_Ledger, name: Limit_Name, amount: s64) {
	assert(amount >= 0 && amount <= ledger.live[name]);
	ledger.live[name] -= amount;
}
