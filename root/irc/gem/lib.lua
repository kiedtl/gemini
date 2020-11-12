local inspect = require('inspect')
local lib = {}

function lib.printf(fmt, ...)
	io.write(string.format(fmt, ...))
end

function lib.format_message(time, pref, msg)
	lib.printf("%s  %12s │ %s\n", time, pref, msg)
end

function lib.last_gmatch(s, pat)
	last = ""
	for i in string.gmatch(s, pat) do
		last = i
	end
	return last
end

function lib.begin_process_messages()
	lib.printf("```\n")
end

function lib.end_process_messages()
	lib.printf("```\n")
end

lib["last_date"] = ""
lib["last_user"] = ""

-- parse IRC messages and format them properly.
--
-- ported from the parse() function in:
-- https://github.com/dylanaraps/birch
--
-- example IRC message:
-- @time=2020-09-07T01:14:11Z :onisamot!~onisamot@reghog.pink PRIVMSG #meat :ahah
function lib.process_message(rawmsg, foldwidth)
	local field = {}
	local word = ""
	local from = ""
	local whom = ""
	local dest = ""

	-- grab the first "word" of the IRC message, as we know that
	-- will be the timestamp of the message
	local date, time = string.gmatch(rawmsg, "@time=([%d-]+)T([%d:]+)Z")()
	time = string.gmatch(time, "(%d+:%d+):.*")() -- trim seconds off
	rawmsg = rawmsg:gsub(".-%s", "", 1)

	-- if the next word in the raw IRC message contains ':', '@',
	-- or '!', split it and grab the sending user nick.
	if string.gmatch(rawmsg, "(.-)%s")():find("[:@!]") then
		whom = string.gmatch(rawmsg, ":?(%w+)!?.-%s")()
		rawmsg = rawmsg:gsub("^.-%s", "", 1)
	end

	-- Grab all the stuff before the next ':' and stuff it into
	-- a table for later. Anything after the ':' is the message.
	local fields = {}
	local data, msg = string.gmatch(rawmsg, "(.-):(.*)")()
	if not data then
		msg = ""
		data = string.gmatch(rawmsg, "(.*)")()
	end

	local ctr = 1
	for w in string.gmatch(data, "(.-)%s") do
		fields[ctr] = w
		ctr = ctr + 1
	end

	-- Fold message to width.
	local mesg = ""
	for w in string.gmatch(msg, "([^ ]+%s?)") do
		local last_line = lib.last_gmatch(mesg..w.."\n", "(.-)\n")
		if (last_line or mesg..w):len() >= foldwidth then
			mesg = mesg .. "\n"
		end
		mesg = mesg .. w
	end
	mesg = mesg:gsub("\n", "\n                    │ ");

	-- If the field after the typical dest is a channel, use
	-- it in place of the regular field. This correctly catches
	-- MOTD and join messages.
	if string.gmatch(fields[3] or "", "^[\\*#]") then
		fields[2] = fields[2]
	elseif string.gmatch(fields[3] or "", "^=") then
		fields[2] = fields[4]
	end

	dest = fields[2]

	-- If the message itself contains ACTION with surrounding '\001',
	-- we're dealing with CTCP /me. Simply set the type to 'ACTION' so
	-- we may specially deal with it below.
	if mesg:find("\001ACTION\001") then
		fields[1] = "ACTION"
		mesg = mesg:gsub("\001ACTION\001 ", "", 1)
	end

	-- If we're going into a new day, print a header.
	if not lib["last_date"] == date then
		lib.end_process_messages()
		lib.printf("\n\n## %s\n\n", date)
		lib.begin_process_messages()
		lib["last_date"] = date
	end

	-- The first element in the fields array points to the type of
	-- message we're dealing with.
	local actions = {
		[0] = function()
			lib.format_message(time, "--", mesg)
		end,
		["PRIVMSG"] = function ()
			local user = whom
			if not whom == lib["last_user"] then
				user = ""
			end
			lib.format_message(time, user, mesg)
			lib["last_user"] = whom
		end,
		["ACTION"] = function()
			lib.format_message(time, "*",
				whom .. " " .. mesg:gsub("\001", ""))
		end,
		["NOTICE"] = function()
			lib.format_message(time, "NOTE", mesg)
		end,
		["QUIT"] = function()
			lib.format_message(time, "<--",
				whom .. " has quit " .. (dest or ""))
		end,
		["PART"] = function()
			lib.format_message(time, "<--",
				whom .. " has left " .. dest)
		end,
		["JOIN"] = function()
			lib.format_message(time, "-->",
				whom .. " has joined " .. mesg)
		end,
		["NICK"] = function()
			lib.format_message(time, "--@",
				whom .. " is now known as " .. mesg)
		end
	}

	local action = actions[fields[1]]
	if action == nil then
		actions[0]()
	else
		action()
	end
end

function lib.capture(cmd)
  local f = assert(io.popen(cmd, 'r'))
  local s = assert(f:read('a'))
  f:close()
  return s
end
function lib.main()
	local out = lib.capture('/home/kiedtl/pub/gemini/src/gemlogs/scoop -d/home/kiedtl/pub/gemini/root/irc/gem/logs.db -firc -l22')
	for i in string.gmatch(out, "(.-)\n") do
		lib.process_message(i, 40)
	end
end
return lib
