local lib = {}

-- local utility functions.
local function format_message(time, pref, msg)
	lib.printf("%s  %12s │ %s\n", time, pref:sub(1, 12), msg)
end

local function last_gmatch(s, pat)
	last = ""
	for i in string.gmatch(s, pat) do
		last = i
	end
	return last
end

-- Fold text to width, adding newlines between words. This is basically a /bin/fold
-- implementation in Lua.
local function fold(text, width)
	local res = ""
	for w in string.gmatch(text, "([^ ]+%s?)") do -- iterate over each word
		-- get the last line of the message.
		local last_line = last_gmatch(res..w.."\n", "(.-)\n")

		-- only append a newline if the line's width is greater than
		-- zero. This is to prevent situations where a long word (say,
		-- a URL) is put on its own line with nothing on the line
		-- above.
		if (last_line or res..w):len() >= width then
			if res:len() > 0 then
				res = res .. "\n"
			end
		end
		res = res .. w
	end
	return res
end

-- parse IRC messages and format them properly.
--
-- ported from the parse() function in:
-- https://github.com/dylanaraps/birch
--
-- example IRC message:
-- @time=2020-09-07T01:14:11Z :onisamot!~onisamot@reghog.pink PRIVMSG #meat :ahah
local function parse_irc(rawmsg)
	local fields = {}
	local whom = ""
	local dest = ""
	local date = ""
	local time = ""
	local msg  = ""

	-- Remove the trailing \r\n from the raw message.
	rawmsg = rawmsg:gsub("\r\n$", "")

	-- grab the first "word" of the IRC message, as we know that
	-- will be the timestamp of the message
	date, time = string.gmatch(rawmsg, "@time=([%d-]+)T([%d:]+)Z")()
	rawmsg = rawmsg:gsub(".-%s", "", 1)

	-- if the next word in the raw IRC message contains ':', '@',
	-- or '!', split it and grab the sending user nick.
	if string.gmatch(rawmsg, "(.-)%s")():find("[:@!]") then
	        whom = string.gmatch(rawmsg, ":?([%w%-_%[%]{}%^`%|]+)!?.-%s")()
	        rawmsg = rawmsg:gsub("^.-%s", "", 1)
	end

	-- Grab all the stuff before the next ':' and stuff it into
	-- a table for later. Anything after the ':' is the message.
	local data, msg = string.gmatch(rawmsg, "(.-):(.*)")()
	if not data then
	        msg = ""
	        data = string.gmatch(rawmsg, "(.*)")()
	end

	local ctr = 1
	for w in string.gmatch(data, "([^%s]+)%s?") do
	        fields[ctr] = w
	        ctr = ctr + 1
	end

	-- If the field after the typical dest is a channel, use
	-- it in place of the regular field. This correctly catches
	-- MOTD and join messages.
	if fields[3] and string.gmatch(fields[3], "^[\\*#]") then
		fields[2] = fields[3]
	elseif fields[3] and string.gmatch(fields[3], "^=") then
		fields[2] = fields[4]
	end

	dest = fields[2]

	-- If the message itself contains ACTION with surrounding '\001',
	-- we're dealing with CTCP /me. Simply set the type to 'ACTION' so
	-- we may specially deal with it below.
	if msg:find("\001ACTION\001") then
		fields[1] = "ACTION"
		msg = msg:gsub("\001ACTION\001 ", "", 1)
	end

	return fields, whom, dest, msg, date, time
end

local actions = {
	[0] = function(time, _whom, mesg, _dest)
		format_message(time, "--", mesg)
	end,
	["PRIVMSG"] = function (time, whom, mesg, _dest)
		local user = whom
		if whom == lib["last_user"] then
			user = ""
		end
		format_message(time, user, mesg)
	end,
	["ACTION"] = function(time, whom, mesg, _dest)
		format_message(time, "*",
			whom .. " " .. mesg:gsub("\001", ""))
	end,
	["NOTICE"] = function(time, _whom, mesg, _dest)
		format_message(time, "NOTE", mesg)
	end,
	["QUIT"] = function(time, whom, _mesg, dest)
		format_message(time, "<--",
			whom .. " has quit " .. (dest or ""))
	end,
	["PART"] = function(time, whom, mesg, dest)
		format_message(time, "<--",
			whom .. " has left " .. dest)
	end,
	["JOIN"] = function(time, whom, mesg, _dest)
		format_message(time, "-->",
			whom .. " has joined " .. mesg)
	end,
	["NICK"] = function(time, whom, mesg, _dest)
		format_message(time, "--@",
			whom .. " is now known as " .. mesg)
	end
}

-- exported stuff
function lib.printf(fmt, ...)
	io.write(string.format(fmt, ...))
end

function lib.begin_process_messages()
	lib.printf("```\n")
end

function lib.end_process_messages()
	lib.printf("```\n")
end

lib["last_date"] = ""
lib["last_user"] = ""

function lib.process_message(rawmsg, foldwidth)
	local fields, whom, dest, msg, date, time = parse_irc(rawmsg)

	-- trim seconds off of time
	time = string.gmatch(time, "(%d+:%d+):.*")()

	-- fold message to width
	local mesg = (fold(msg, foldwidth)):gsub("\n", "\n                    │ ")

	-- If we're going into a new day, print a header.
	if not (lib["last_date"] == date) then
		lib.end_process_messages()
		lib.printf("\n\n## %s\n\n", date)
		lib.begin_process_messages()
		lib["last_date"] = date
		lib["last_user"] = ""
	end

	-- The first element in the fields array points to the type of
	-- message we're dealing with.
	local action = actions[fields[1]]
	if action == nil then
		actions[0](time, whom, mesg, dest)
	else
		action(time, whom, mesg, dest)
	end

	lib["last_user"] = whom

	-- if messages are "interrupted" by joins, quits, etc., then
	-- show the nickname for the next message anyway
	if not (fields[1] == "PRIVMSG") then
		lib["last_user"] = ""
	end
end

-- unit tests.
-- TODO: test search.gmi's query parsing functions

local failed = 0
local passed = 0

local function assert_eq(left, right)
	if left == right then
		passed = passed + 1
		print(string.format("\x1b[32m✔\x1b[0m | '%s' == '%s'",
			left, right))
	else
		failed = failed + 1
		print(string.format("\x1b[31m✖\x1b[0m | '%s' != '%s'",
			left, right))
	end
end

local function test_last_gmatch()
	local cases = {
		{ "a b c d e f g h i j k l m n o p", "(%w)", "p" },
		{ "This test. This is another test1.", "(%w-[%p%s])", "test1." },
	}

	for c = 1, #cases do
		assert_eq(last_gmatch(cases[c][1], cases[c][2]), cases[c][3])
	end
end

local function test_parse_irc()
	local cases = {
		{
			"@time=2020-11-05T22:26:13Z :team.tilde.chat NOTICE * :*** Looking up your ident...",
			{
				{ "NOTICE", "*" }, "team", "*",
				"*** Looking up your ident...", "2020-11-05", "22:26:13"
			},
		},
		{
			"@time=2020-11-05T22:26:14Z :VI-A!test@tilde.team JOIN #gemini",
			{
				{ "JOIN", "#gemini" }, "VI-A", "#gemini",
				"", "2020-11-05", "22:26:14"
			},
		},
		{
			"@time=2020-11-05T22:33:33Z :__restrict!spacehare@tilde.town PRIVMSG #gemini :hm",
			{
				{ "PRIVMSG", "#gemini" }, "__restrict", "#gemini",
				"hm", "2020-11-05", "22:33:33",
			},
		},
	}

	for c = 1, #cases do
		local fields, whom, dest, msg, date, time = parse_irc(cases[c][1])
		assert_eq(table.concat(fields), table.concat(cases[c][2][1]))
		assert_eq(whom, cases[c][2][2])
		assert_eq(dest, cases[c][2][3])
		assert_eq(msg, cases[c][2][4])
		assert_eq(date, cases[c][2][5])
		assert_eq(time, cases[c][2][6])
	end
end

function lib.tests()
	local tests = {
		[test_last_gmatch] = "test_last_gmatch",
		[test_parse_irc] = "test_parse_irc",
	}

	for testf, testname in pairs(tests) do
		print("\x1b[33m->\x1b[0m testing " .. testname)
		testf()
		print()
	end

	print()
	print(string.format("%d tests completed. %d passed, %d failed.",
		passed + failed, passed, failed))
end

return lib
