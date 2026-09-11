-- Run C item 32 (throwaway fixture): one iMessage from a launchd-started process.
-- Deleted at close-out.
on run
	try
		tell application "Messages"
			set targetService to 1st account whose service type = iMessage
			set targetBuddy to participant "<redacted — the phone number used in the trial>" of targetService
			send "Baton trial: escalation channel test, sent from a launchd job." to targetBuddy
		end tell
		return "SENT: participant form succeeded"
	on error errMsg number errNum
		return "FAILED: " & errNum & " :: " & errMsg
	end try
end run
