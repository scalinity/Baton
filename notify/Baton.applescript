-- notify/Baton.applescript — the notifier applet, compiled by install.sh into $BATON_HOME/bin/Baton.app.
-- It posts the Mac message under its own name, with Claude's icon, and opens the session a message is
-- about when the message is clicked (REQ-ESC-02).
--
-- `notify` writes each message to $BATON_HOME/notify/spool/ as three lines — title, body, target — and
-- launches the applet. A launch that finds messages spooled posts them; a launch that finds none was a
-- click on one of them, because macOS relaunches the applet that posted a notification when it is
-- clicked, and a `display notification` carries no data to say which. So a click opens the target of
-- the newest message posted, or Claude.app's own "needs input" view when that message named no session,
-- and clears every Baton message from Notification Center, since the clicked one alone cannot be named.
--
-- Every field is read with `do shell script` as a value and never spliced into script source, so
-- nothing a message says is parsed as AppleScript.
use framework "Foundation"
use scripting additions

on run
	if not post_spooled() then open_newest()
end run

-- A launch that reaches the applet while it is still running arrives as a reopen, not a run; it may
-- carry a message spooled after the last listing, so it posts too. The tick's `notify_flush` covers a
-- launch that reached the applet too late for either.
on reopen
	post_spooled()
end reopen

-- The applet sits at $BATON_HOME/bin/Baton.app, so the home is two directories up from it.
on baton_home()
	return do shell script "cd " & quoted form of (POSIX path of (path to me)) & "/../.. && pwd"
end baton_home

-- Posts every spooled message, oldest first, until the spool is empty, and says whether it posted any. A
-- message spooled while this launch is posting does not relaunch a running applet, and left behind it
-- would be posted by the next click instead of opening a session.
--
-- A message that cannot be read or removed is not an error a person should see: an applet shows an
-- uncaught error as a dialog. So each message is handled inside `try`, and a pass that hit a failure
-- ends the loop, because the file it could not remove would otherwise be listed and posted again
-- forever; the next launch tries it again. The target is written aside and renamed, so a click never
-- reads it half-written.
on post_spooled()
	set spool to baton_home() & "/notify/spool"
	set target_file to baton_home() & "/notify/target"
	set posted to false
	repeat
		set names to paragraphs of (do shell script "ls " & quoted form of spool & " 2>/dev/null || true")
		if (count of names) is 0 then exit repeat
		set failed to false
		repeat with n in names
			set f to spool & "/" & n
			try
				set t to do shell script "sed -n 1p " & quoted form of f
				set b to do shell script "sed -n 2p " & quoted form of f
				if t is not "" then
					display notification b with title t
					do shell script "sed -n 3p " & quoted form of f & " > " & quoted form of (target_file & ".tmp") & " && mv " & quoted form of (target_file & ".tmp") & " " & quoted form of target_file
					set posted to true
				end if
				do shell script "rm " & quoted form of f
			on error
				set failed to true
			end try
		end repeat
		if failed then exit repeat
	end repeat
	return posted
end post_spooled

-- A click: clear Baton's messages and open the newest one's session. A failed open — Claude.app not
-- installed — ends quietly rather than in a dialog.
on open_newest()
	current application's NSUserNotificationCenter's defaultUserNotificationCenter()'s removeAllDeliveredNotifications()
	set target to do shell script "cat " & quoted form of (baton_home() & "/notify/target") & " 2>/dev/null || true"
	-- Only a link into Claude.app is opened; `notify` writes nothing else, and the check keeps it so. The
	-- comparison considers case, because AppleScript's text comparisons ignore it by default and
	-- `session_url` accepts exactly this spelling.
	considering case
		set is_session to target starts with "claude://claude.ai/code/session_"
	end considering
	if not is_session then set target to "claude://code/needs-input"
	try
		do shell script "open " & quoted form of target
	end try
end open_newest
