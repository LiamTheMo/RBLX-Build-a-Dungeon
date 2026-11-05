-- One server at a time owns a profile. A lease names the owning server's JobId
-- and an expiry, and is renewed on every save.

local SessionLease = {}

SessionLease.DURATION_SECONDS = 120

export type Lease = { jobId: string, expiresAt: number }

-- A server may take a profile with no lease, its own lease, or an expired one.
function SessionLease.CanAcquire(lease: Lease?, jobId: string, now: number): boolean
	if lease == nil then
		return true
	end
	return lease.jobId == jobId or lease.expiresAt <= now
end

function SessionLease.IsHeldBy(lease: Lease?, jobId: string): boolean
	return lease ~= nil and lease.jobId == jobId
end

function SessionLease.New(jobId: string, now: number): Lease
	return { jobId = jobId, expiresAt = now + SessionLease.DURATION_SECONDS }
end

return SessionLease
