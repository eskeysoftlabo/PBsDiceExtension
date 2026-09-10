-- Behavioural tests for PB's Dice Extension.
--
--   lua test/run.lua        (from the add-on folder; any Lua 5.1+)
--
-- What is worth testing here is everything the add-on decides on its own: how a spec is read,
-- what a roll is allowed to be, what the two lines it prints say, what goes in the chat box
-- and -- the one that would otherwise cost a console session -- that what goes in the chat box
-- is never allowed to replace something the player typed.
--
-- What cannot be tested here is the one thing this add-on is careful about: whether the
-- client refuses a private call from add-on code. That is what /pbdice probe is for.

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/") or ".")
ADDON_DIR = HERE .. "/.."
dofile(HERE .. "/harness.lua")

local failures = 0
local function check(label, got, want)
	local ok = got == want
	if not ok then failures = failures + 1 end
	print(string.format("%s %-58s got=%s want=%s", ok and "PASS" or "FAIL", label,
		tostring(got), tostring(want)))
end

local function checkContains(label, haystack, needle)
	local ok = type(haystack) == "string" and haystack:find(needle, 1, true) ~= nil
	if not ok then failures = failures + 1 end
	print(string.format("%s %-58s in=%s", ok and "PASS" or "FAIL", label, tostring(haystack)))
end

local function checkMissing(label, haystack, needle)
	local ok = type(haystack) == "string" and haystack:find(needle, 1, true) == nil
	if not ok then failures = failures + 1 end
	print(string.format("%s %-58s in=%s", ok and "PASS" or "FAIL", label, tostring(haystack)))
end

print("\n== 1. load ==")
Fire(EVENT_ADD_ON_LOADED, "PBsDiceExtension")
local addon = PBS_DICE
local dice = addon.dice

-- Not a literal: the version is read out of the manifest's Title line by the add-on and out
-- of its Version line by the test, so this also catches the release mistake of editing one of
-- those two adjacent lines and not the other.
check("version read from manifest", addon.version, ManifestLine("Version"))
check("and there is a version to read", (ManifestLine("Version") or ""):match("^%d"), "1")
check("slash command registered", type(SLASH_COMMANDS["/pbdice"]), "function")
check("/dice taken because it was free", type(SLASH_COMMANDS["/dice"]), "function")
check("and it knows it took it", addon.friendlySlashTaken, false)

print("\n== 2. shipped settings are the roll the game already does ==")
check("one die", addon:Count(), 1)
check("of a hundred sides", addon:Sides(), 100)
check("every die shown", addon:ShowEach(), true)
check("marked as local", addon:ShowLocalTag(), true)
check("chat box left alone", addon:Prefill(), false)

print("\n== 3. reading a spec ==")
local function parse(text)
	local count, sides, problem = dice:Parse(text, addon:Sides())
	if not count then return "!" .. tostring(problem) end
	return count .. "d" .. sides
end
check("3d20", parse("3d20"), "3d20")
check("d20 is one d20, as it is everywhere", parse("d20"), "1d20")
check("3d is three of yours", parse("3d"), "3d100")
check("a bare number is sides", parse("20"), "1d20")
check("whitespace and case", parse(" 2 D 8 "), "2d8")
check("a bare d is not a spec", parse("d"), "!spec")
check("words are not specs", parse("count"), "!spec")
check("the modifier the client takes, we do not", parse("3d20+5"), "!spec")
check("eleven dice is too many", parse("11d20"), "!count")
check("no dice is not a roll", parse("0d20"), "!count")
check("1001 sides is too many", parse("3d1001"), "!sides")
check("a one-sided die is not a die", parse("3d1"), "!sides")
check("ten dice is the limit and is allowed", parse("10d1000"), "10d1000")

print("\n== 4. the dice themselves ==")
local seen = {}
local worst, best = math.huge, -math.huge
for _ = 1, 2000 do
	local result = dice:Roll(3, 6)
	local sum = 0
	for _, value in ipairs(result.rolls) do
		sum = sum + value
		seen[value] = true
		if value < worst then worst = value end
		if value > best then best = value end
	end
	if #result.rolls ~= 3 then failures = failures + 1 end
	if sum ~= result.total then failures = failures + 1 end
end
check("three dice, three numbers, 2000 times", true, true)
check("no die under 1", worst, 1)
check("no die over 6", best, 6)
local distinct = 0
for _ in pairs(seen) do distinct = distinct + 1 end
check("all six faces come up", distinct, 6)

local clamped = dice:Roll(99, 99999)
check("a roll asked for out of range is clamped, not refused", clamped.count, 10)
check("and so are the sides", clamped.sides, 1000)

print("\n== 5. what it says ==")
ClearChat()
addon:RollAndPrint(1, 6)
check("one die is one line", #Chat, 1)
checkContains("the client's own sentence", PlainChat(1), "rolls")
checkContains("one die is a die, not dice", PlainChat(1), "-sided die.")
checkContains("says out loud that only you saw it", PlainChat(1), "(only you)")

ClearChat()
local result = addon:RollAndPrint(3, 6)
check("three dice is two lines", #Chat, 2)
checkContains("three of them are dice", PlainChat(1), "-sided dice.")
checkContains("and the breakdown adds up", PlainChat(2),
	result.rolls[1] .. " + " .. result.rolls[2] .. " + " .. result.rolls[3] .. " = " .. result.total)

addon:SetShowEach(false)
ClearChat()
addon:RollAndPrint(3, 6)
check("breakdown can be turned off", #Chat, 1)
addon:SetShowEach(true)

addon:SetShowLocalTag(false)
ClearChat()
addon:RollAndPrint(1, 6)
checkMissing("and so can the marker", PlainChat(1), "(only you)")
addon:SetShowLocalTag(true)

print("\n== 6. the command that rolls for real ==")
local text, wasClamped = dice:CommandText(3, 20)
check("the command", text, "/roll 3d20")
check("nothing to clamp", wasClamped, false)

SetClientRollLimits(5, 100)
local capped, cappedFlag, maxCount, maxSides = dice:CommandText(10, 1000)
check("clamped to what the client accepts", capped, "/roll 5d100")
check("and says it clamped", cappedFlag, true)
check("and what to", maxCount .. "d" .. maxSides, "5d100")
SetClientRollLimits(10, 1000)

print("\n== 7. commands ==")
local function run(args)
	ClearChat()
	SLASH_COMMANDS["/pbdice"](args)
end

run("")
check("bare /pbdice rolls", #Chat >= 1, true)

run("count 5")
check("count", addon:Count(), 5)
run("count 11")
check("out of range is refused", addon:Count(), 5)
checkContains("and says the range", LastChat(), "1 to 10")

run("sides 20")
check("sides", addon:Sides(), 20)
run("sides 1")
check("out of range is refused", addon:Sides(), 20)
checkContains("and says the range", LastChat(), "2 to 1000")

run("3d6")
check("a one-off does not change the count", addon:Count(), 5)
check("nor the sides", addon:Sides(), 20)
checkContains("it rolls three six-sided dice", PlainChat(1), "-sided dice.")

run("each off")
check("each off", addon:ShowEach(), false)
run("each on")
check("each on", addon:ShowEach(), true)
run("each maybe")
checkContains("on or off", LastChat(), "on or off")

run("tag off")
check("tag off", addon:ShowLocalTag(), false)
run("tag on")
check("tag on", addon:ShowLocalTag(), true)

run("prefill on")
check("prefill on", addon:Prefill(), true)
checkContains("and says what will be waiting", LastChat(), "/roll 5d20")

run("status")
checkContains("status: the dice", ChatContains("dice: 5d20"), "5d20")
checkContains("status: what to send for a real roll", ChatContains("/roll 5d20"), "/roll 5d20")

run("probe")
checkContains("probe reports the client's cap", ChatContains("RANDOM_ROLL_MAX_NUM_ROLLS"), "10")
checkContains("probe copes with the call not being there", ChatContains("nothing to try"), "nothing to try")

run("wobble")
checkContains("unknown commands say so", PlainChat(1), "no such command: wobble")
checkContains("and then help", ChatContains("/pbdice 3d20"), "3d20")

run("reset")
check("reset: count", addon:Count(), 1)
check("reset: sides", addon:Sides(), 100)
check("reset: prefill", addon:Prefill(), false)

print("\n== 8. the chat box ==")
Fire(EVENT_PLAYER_ACTIVATED)
check("prefill is available where the chat screen is", addon.prefillAvailable, true)

-- Measured on a PS5: R3 did nothing, because at this moment the screen has never been shown
-- and the table its keybinds live in has not been built yet. Anything that reads it here
-- reads nil, and an add-on that concludes "no chat screen" from that is wrong.
check("the keybind table does not exist yet", CHAT_MENU_GAMEPAD.textInputAreaKeybindDescriptor, nil)
check("so the button is pending, not missing", addon.chatKeybindState, addon.KEYBIND_PENDING)

ChatEdit:Clear()
OpenChatScreen(SCENE_SHOWING)
check("off: the box is left empty", ChatEdit:GetText(), "")

addon:SetPrefill(true)
addon:SetCount(3)
addon:SetSides(20)
ChatEdit:Clear()
OpenChatScreen(SCENE_SHOWING)
check("on: the box is ready to send", ChatEdit:GetText(), "/roll 3d20")

ChatEdit:SetText("hello there")
OpenChatScreen(SCENE_SHOWING)
check("what the player typed is never replaced", ChatEdit:GetText(), "hello there")

ChatEdit:Clear()
OpenChatScreen(SCENE_SHOWN)
check("only when the screen is opening, not once it is open", ChatEdit:GetText(), "")

-- The keyboard client, and any future where that screen is built differently: the setting has
-- to fail quietly rather than error, and status has to admit it.
local realScene = CHAT_MENU_GAMEPAD_SCENE
CHAT_MENU_GAMEPAD_SCENE = nil
check("no scene, no crash", addon:InitPrefill(), false)
check("and it says so", addon.prefillAvailable, false)
ClearChat()
addon:PrintStatus()
checkContains("status admits it", ChatContains("does nothing"), "does nothing")
CHAT_MENU_GAMEPAD_SCENE = realScene
addon.prefillAvailable = true

print("\n== 9. R3 in the chat screen ==")
-- Section 8 opened the chat screen, which is when the client builds the descriptor and when
-- the add-on gets its one chance to put a row in it.
check("opening the screen is what adds the button", addon.chatKeybindState, addon.KEYBIND_ADDED)
check("five rows where the client wrote four", KeybindRowCount(), 5)

-- The claim this section exists to prove is the negative one: the game's Random Roll on the
-- third button is the client's, and after all of this it is still the client's, byte for byte.
check("the game's roll button still has the game's callback",
	KeybindEntry("UI_SHORTCUT_TERTIARY").callback, ClientRandomRollCallback)

-- One row is all the strip will give a keybind, so the label has to say both things: what a
-- press does and what a hold does, and which of them the group can see.
addon:SetCount(3)
addon:SetSides(6)
checkContains("the button is named for the add-on", KeybindLabel(addon.ROLL_KEYBIND), "PB's Dice")
checkContains("a press is yours alone", KeybindLabel(addon.ROLL_KEYBIND), "only you")
checkContains("and a hold is everybody's", KeybindLabel(addon.ROLL_KEYBIND), "hold: everyone")

ClearChat()
check("pressing it works", PressKeybind(addon.ROLL_KEYBIND), "pressed")
checkContains("and it rolls your dice", PlainChat(1), "3 x 6-sided dice.")
check("without going anywhere near the game's roll", ClientRolls, 0)

addon:SetChatKeybind(false)
ClearChat()
check("off: the button is not there to press", PressKeybind(addon.ROLL_KEYBIND), "hidden")
check("and nothing was rolled", #Chat, 0)
addon:SetChatKeybind(true)
check("on again", PressKeybind(addon.ROLL_KEYBIND), "pressed")

print("\n== 9b. press and hold ==")
-- Short press rolls; long press stages the command the game will roll. The two have to be
-- told apart on the way up, so the row asks for key ups -- something an add-on may only do to
-- a row it owns. Doing it to the game's Random Roll row would roll twice per press.
check("our row asks for key ups", KeybindEntry(addon.ROLL_KEYBIND).handlesKeyUp, true)
check("the game's row does not, and we did not give it one",
	KeybindEntry("UI_SHORTCUT_TERTIARY").handlesKeyUp, nil)

addon:SetCount(3)
addon:SetSides(20)
addon:SetPrefill(false)

ClearChat()
ChatEdit:Clear()
check("a short press", PressKeybind(addon.ROLL_KEYBIND, 100), "pressed")
checkContains("rolls your dice", PlainChat(1), "3 x 20-sided dice.")
check("and leaves the chat box alone", ChatEdit:GetText(), "")

ClearChat()
ChatEdit:Clear()
check("a long press", PressKeybind(addon.ROLL_KEYBIND, 600), "pressed")
check("stages the command the group will see", ChatEdit:GetText(), "/roll 3d20")
check("and rolls nothing itself", #Chat, 0)

-- It does not consult the "fill the box when the screen opens" checkbox: somebody holding the
-- button is asking for it now.
check("staging does not need the prefill setting", addon:Prefill(), false)

ClearChat()
ChatEdit:SetText("hello there")
PressKeybind(addon.ROLL_KEYBIND, 600)
check("a half-typed message is never overwritten", ChatEdit:GetText(), "hello there")
checkContains("and the refusal is said out loud", PlainChat(1), "already has something in it")

-- The key going down must not roll on its own, or a hold would roll AND stage.
ClearChat()
ChatEdit:Clear()
check("down alone", PressKeybindDownOnly(addon.ROLL_KEYBIND), "down")
check("rolls nothing yet", #Chat, 0)
check("and stages nothing", ChatEdit:GetText(), "")

-- ...and a key up with no down under it -- the screen changed while it was held -- is read as
-- the short press, which is the one that cannot surprise anybody.
addon.rollKeyDownAt = nil
AdvanceGameTime(9000)
ClearChat()
KeybindEntry(addon.ROLL_KEYBIND).callback(true)
checkContains("an orphaned key up rolls rather than stages", PlainChat(1), "3 x 20-sided dice.")
check("and still stages nothing", ChatEdit:GetText(), "")

print("\n== 9c. opening it again ==")
-- Every later open runs it again, and every later open must find its own row and stop.
OpenChatScreen(SCENE_SHOWING)
OpenChatScreen(SCENE_SHOWING)
check("opening it again adds nothing", KeybindRowCount(), 5)
check("and the state still reads added", addon.chatKeybindState, addon.KEYBIND_ADDED)

-- Somebody else's R3. Leave it alone and say so, rather than adding a second row the strip
-- would have to choose between.
SetInputAreaDescriptor({
	{ name = "Something else", keybind = "UI_SHORTCUT_RIGHT_STICK", callback = function() end },
})
check("R3 already taken: we do not take it", addon:InitChatKeybind(), false)
check("and we know why", addon.chatKeybindState, addon.KEYBIND_TAKEN)
ClearChat()
addon:PrintStatus()
checkContains("status says so", ChatContains("claimed R3"), "claimed R3")

-- A client with no gamepad chat screen at all. Distinguishable from "not opened yet" only
-- because by now we have been called from the scene itself.
ForgetChatScreen()
check("no chat screen, no crash", addon:InitChatKeybind(), false)
check("and it says so", addon.chatKeybindState, addon.KEYBIND_UNAVAILABLE)
ClearChat()
addon:PrintStatus()
checkContains("status admits it", ChatContains("gamepad chat screen is not here"), "not here")

-- And opening the screen puts it all back, which is the path a player actually walks.
OpenChatScreen(SCENE_SHOWING)
check("opening the screen builds it again", addon.chatKeybindState, addon.KEYBIND_ADDED)
check("with our row in it", KeybindRowCount(), 5)
check("and it is pressable", PressKeybind(addon.ROLL_KEYBIND), "pressed")

print("\n== 10. the settings panel ==")
check("panel built", type(Panel), "table")
checkContains("titled with the version", Panel.title, addon.version)
local countRow = PanelRow(SI_PBSDICE_COUNT)
check("count is a slider", countRow.type, LibHarvensAddonSettings.ST_SLIDER)
check("from one die", countRow.min, 1)
check("to ten", countRow.max, 10)
local sidesRow = PanelRow(SI_PBSDICE_SIDES)
check("sides from two", sidesRow.min, 2)
check("to a thousand", sidesRow.max, 1000)
check("sides steps by one, so a d20 is reachable", sidesRow.step, 1)

countRow.setFunction(7)
check("the slider sets the count", addon:Count(), 7)
check("and reads it back", countRow.getFunction(), 7)

local keybindRow = PanelRow(SI_PBSDICE_KEYBIND)
check("R3 has a checkbox", keybindRow.type, LibHarvensAddonSettings.ST_CHECKBOX)
check("shipped on", keybindRow.default, true)
keybindRow.setFunction(false)
check("and the checkbox is the off switch", addon:ChatKeybind(), false)
check("which the button asks about every time it draws", PressKeybind(addon.ROLL_KEYBIND), "hidden")
keybindRow.setFunction(true)

ClearChat()
PanelRow(SI_PBSDICE_ROLL_NOW).clickHandler()
check("the roll button rolls", #Chat >= 1, true)

PanelRow(SI_PBSDICE_RESET).clickHandler()
check("the reset button resets", addon:Count(), 1)

print("\n== 11. the translation ==")
-- Both language files are read again, into tables of their own, and compared. Two things go
-- wrong with a translated string table and neither shows up until somebody is playing in that
-- language: a line that was never translated, and a line whose %d and %s came out in a
-- different order from the original -- which is not a wrong word, it is an error at the moment
-- the message is printed.
local function ReadStrings(file)
	local captured = {}
	local realCreate, realVersion = ZO_CreateStringId, SafeAddVersion
	ZO_CreateStringId = function(id, value) captured[id] = value end
	SafeAddVersion = function() end
	dofile(ADDON_DIR .. "/" .. file)
	ZO_CreateStringId, SafeAddVersion = realCreate, realVersion
	return captured
end

local function Specifiers(text)
	local found = {}
	for spec in tostring(text):gmatch("%%[%-%+ #0]*%d*%.?%d*[diouxXeEfgGqs]") do
		found[#found + 1] = spec
	end
	return table.concat(found, ",")
end

local english = ReadStrings("lang/strings.lua")
local japanese = ReadStrings("lang/jp.lua")

local missing, mismatched, extra = {}, {}, {}
for id, value in pairs(english) do
	if japanese[id] == nil then
		missing[#missing + 1] = id
	elseif Specifiers(japanese[id]) ~= Specifiers(value) then
		mismatched[#mismatched + 1] = id
	end
end
for id in pairs(japanese) do
	if english[id] == nil then
		extra[#extra + 1] = id
	end
end

table.sort(missing)
table.sort(mismatched)
table.sort(extra)

check("every English line has a Japanese one", table.concat(missing, " "), "")
check("and takes the same arguments in the same order", table.concat(mismatched, " "), "")
check("and Japanese invents none of its own", table.concat(extra, " "), "")

local counted = 0
for _ in pairs(english) do counted = counted + 1 end
check("there are strings to compare at all", counted > 40, true)

print("")
if failures == 0 then
	print("all passed")
else
	print(failures .. " FAILED")
end
os.exit(failures == 0 and 0 or 1)
