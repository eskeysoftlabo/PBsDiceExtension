-- Stub of just enough ESO client to exercise PB's Dice Extension.
--
-- The add-on runs on a console, where one real test costs a whole session: build, upload, boot
-- the PS5, log in. What this add-on decides is a spec, a range and a sentence, and all three
-- can be decided here instead. What is stubbed is only what the add-on actually touches.
--
-- Two of the stubs matter more than the rest:
--
--   * the CLIENT'S OWN STRINGS. SI_RANDOM_ROLL_DICE_RESULT and SI_SLASH_ROLL are registered
--     here with the text the live client really ships, so the tests check the sentence the
--     player will actually read rather than one this file invented.
--   * the GAMEPAD CHAT SCREEN. A scene with a callback list and an edit box with a text
--     property is the whole of what Prefill.lua touches, so the whole of Prefill.lua can be
--     tested -- including the rule that it must never overwrite what the player typed.
local DIR = ADDON_DIR

-- ---- string table -------------------------------------------------------------------
local stringValues = {}
local nextId = 1
function ZO_CreateStringId(id, value)
	if not _G[id] then _G[id] = nextId; nextId = nextId + 1 end
	stringValues[_G[id]] = value
end
function SafeAddVersion() end
function GetString(id) return stringValues[id] or ("<missing " .. tostring(id) .. ">") end

-- The client's own strings, copied from esoui/lang/en_client.lua. If the client ever changes
-- them, this file is where the tests find out.
ZO_CreateStringId("SI_RANDOM_ROLL_DICE_RESULT", "<<1>> rolls <<2>> with <<3>> x <<4>>-sided <<3[die/dice]>>.")
ZO_CreateStringId("SI_SLASH_ROLL", "/roll")

-- ---- formatting ---------------------------------------------------------------------
-- Enough of zo_strformat for the one sentence this add-on borrows: numbered parameters and
-- the <<n[singular/plural]>> form, which is the part a string table of our own would not have.
function zo_strformat(id, ...)
	local template = type(id) == "number" and GetString(id) or tostring(id)
	local args = { ... }
	template = template:gsub("<<(%d+)%[(.-)%]>>", function(index, forms)
		-- The colour markup comes off FIRST. "|cC5C29E1|r" has four digits in it and only
		-- the last one is the number; a stub that counted them all would report that one die
		-- is dice, which is exactly the bug this line exists to not have.
		local raw = tostring(args[tonumber(index)] or "")
		raw = raw:gsub("|c%x%x%x%x%x%x", ""):gsub("|r", "")
		local number = tonumber((raw:gsub("[^%d]", ""))) or 0
		local singular, plural = forms:match("^(.-)/(.*)$")
		return number == 1 and singular or plural
	end)
	template = template:gsub("<<(%d+)>>", function(index)
		return tostring(args[tonumber(index)] or "")
	end)
	return template
end

function zo_iconFormat(path, width, height)
	return string.format("|t%s:%s:%s|t", tostring(width), tostring(height), path)
end

ZO_SELECTED_TEXT = {
	Colorize = function(_, value) return "|cC5C29E" .. tostring(value) .. "|r" end,
}

-- ---- chat ---------------------------------------------------------------------------
Chat = {}
CHAT_ROUTER = { AddSystemMessage = function(_, t) Chat[#Chat + 1] = t end }
function d(t) print("[d] " .. tostring(t)) end
SLASH_COMMANDS = {}

function ClearChat() Chat = {} end

-- Chat lines with the colour and icon markup taken back off, which is what the assertions
-- want to read.
function PlainChat(index)
	local line = Chat[index]
	if not line then return nil end
	line = line:gsub("|c%x%x%x%x%x%x", ""):gsub("|r", "")
	line = line:gsub("|t.-|t", "")
	return (line:gsub("^%s+", ""))
end

function LastChat()
	return PlainChat(#Chat)
end

function ChatContains(needle)
	for index = 1, #Chat do
		local line = PlainChat(index)
		if line and line:find(needle, 1, true) then return line end
	end
	return nil
end

-- ---- who ----------------------------------------------------------------------------
local characterName = "Bosmer Bunbun"
local displayName = "@PinkBanther"

function GetUnitName(unit) return unit == "player" and characterName or "" end
function GetDisplayName() return displayName end
function ZO_GetPrimaryPlayerName(_, character) return character end

-- ---- clocks -------------------------------------------------------------------------
function GetTimeStamp() return 20706 * 86400 + 12 * 3600 end

-- Advanceable, because the difference between a press and a hold is a number of milliseconds
-- and there is no other way to hold a button down in a test.
local gameTimeMs = 1234567
function GetGameTimeMilliseconds() return gameTimeMs end
function AdvanceGameTime(ms) gameTimeMs = gameTimeMs + ms end

-- ---- the client's roll --------------------------------------------------------------
-- The real numbers off a live client are not knowable from here, so these are placeholders
-- big enough not to clamp; the clamping test sets them itself.
RANDOM_ROLL_MAX_NUM_ROLLS = 10
RANDOM_ROLL_MAX_RESULT = 1000
RANDOM_ROLL_MIN_RESULT = -1000
RANDOM_ROLL_RESULT_SUCCESS = 0

function SetClientRollLimits(maxRolls, maxResult)
	RANDOM_ROLL_MAX_NUM_ROLLS = maxRolls
	RANDOM_ROLL_MAX_RESULT = maxResult
end

-- Absent by default, exactly as it is for add-on code that is refused: the probe has to cope
-- with both, and the shipped assumption is that it cannot be called.
RandomDiceRoll = nil

-- ---- manifest -----------------------------------------------------------------------
-- Read rather than copied: a test that carries its own idea of the version stops testing the
-- release step the moment somebody edits the manifest and not the harness.
function ManifestLine(field)
	local file = io.open(DIR .. "/PBsDiceExtension.addon", "r")
	if not file then return nil end
	local found
	for line in file:lines() do
		found = found or line:match("^## " .. field .. ":%s*(.-)%s*$")
	end
	file:close()
	return found
end

function GetAddOnManager()
	return {
		GetNumAddOns = function() return 1 end,
		GetAddOnInfo = function(_, i)
			return "PBsDiceExtension", ManifestLine("Title")
		end,
	}
end

-- ---- events -------------------------------------------------------------------------
EVENT_ADD_ON_LOADED = "EVENT_ADD_ON_LOADED"
EVENT_PLAYER_ACTIVATED = "EVENT_PLAYER_ACTIVATED"

local handlers = {}
EVENT_MANAGER = {
	RegisterForEvent = function(_, namespace, event, fn)
		handlers[event] = handlers[event] or {}
		handlers[event][namespace] = fn
	end,
	UnregisterForEvent = function(_, namespace, event)
		if handlers[event] then handlers[event][namespace] = nil end
	end,
}

function Fire(event, ...)
	for _, fn in pairs(handlers[event] or {}) do
		fn(event, ...)
	end
end

-- ---- saved variables ----------------------------------------------------------------
SavedVars = nil

local function DeepCopy(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for k, v in pairs(value) do copy[k] = DeepCopy(v) end
	return copy
end

ZO_SavedVars = {
	NewAccountWide = function(_, name, version, namespace, defaults)
		SavedVars = DeepCopy(defaults or {})
		return SavedVars
	end,
}

-- ---- the gamepad chat screen --------------------------------------------------------
SCENE_SHOWING = "showing"
SCENE_SHOWN = "shown"
SCENE_HIDDEN = "hidden"

ChatEdit = {
	text = "",
	SetText = function(self, value) self.text = value end,
	GetText = function(self) return self.text end,
	Clear = function(self) self.text = "" end,
}

-- No keybind descriptor. That is not an omission: the real screen does not have one either
-- until it has been shown once, and an add-on that assumed otherwise is exactly the bug this
-- harness now reproduces.
CHAT_MENU_GAMEPAD = { textEdit = ChatEdit }

CHAT_MENU_GAMEPAD_SCENE = {
	callbacks = {},
	RegisterCallback = function(self, name, fn)
		self.callbacks[name] = self.callbacks[name] or {}
		table.insert(self.callbacks[name], fn)
	end,
}

-- The four rows the client puts in the chat screen's text input area, close enough for the
-- add-on to find its way around: what matters is that the third one is the game's Random Roll
-- and that it belongs to the client, so a test can prove we did not touch it.
ClientRandomRollCallback = function() ClientRolls = (ClientRolls or 0) + 1 end
ClientRolls = 0

local function NewInputAreaDescriptor()
	return {
		{ name = "Back", keybind = "UI_SHORTCUT_NEGATIVE", callback = function() end },
		{ name = "Select", keybind = "UI_SHORTCUT_PRIMARY", callback = function() end },
		{ name = "Send", keybind = "UI_SHORTCUT_SECONDARY", callback = function() end },
		{ name = "Random Roll", keybind = "UI_SHORTCUT_TERTIARY", callback = ClientRandomRollCallback },
	}
end

-- The client's own StateChange callback, registered here -- before the add-on is loaded at the
-- bottom of this file -- because that is when the real one is registered, and the ordering
-- between the two is the whole reason the add-on's row lands in the right place.
-- ZO_Gamepad_ParametricList_Screen:OnStateChanged runs PerformDeferredInitialize on SHOWING,
-- and that is what builds the descriptor.
local deferredInitialized = false
CHAT_MENU_GAMEPAD_SCENE:RegisterCallback("StateChange", function(_, newState)
	if newState == SCENE_SHOWING and not deferredInitialized then
		deferredInitialized = true
		CHAT_MENU_GAMEPAD.textInputAreaKeybindDescriptor = NewInputAreaDescriptor()
	end
end)

-- Back to a client that has never shown its chat screen.
function ForgetChatScreen()
	deferredInitialized = false
	CHAT_MENU_GAMEPAD.textInputAreaKeybindDescriptor = nil
end

function SetInputAreaDescriptor(entries)
	CHAT_MENU_GAMEPAD.textInputAreaKeybindDescriptor = entries
	return entries
end

function KeybindEntry(keybind)
	for _, entry in ipairs(CHAT_MENU_GAMEPAD.textInputAreaKeybindDescriptor or {}) do
		if entry.keybind == keybind then return entry end
	end
	return nil
end

function KeybindRowCount()
	return #(CHAT_MENU_GAMEPAD.textInputAreaKeybindDescriptor or {})
end

-- Pressing a button on the keybind strip, as far as a descriptor can tell: a hidden row is
-- not pressable, which is how the strip turns a "visible" predicate into an off switch.
--
-- The strip calls callback(DOWN) on the way down and, only if handlesKeyUp is set,
-- callback(UP) on the way back -- the false/true the real one passes. holdMs is how long the
-- button stays down.
function PressKeybind(keybind, holdMs)
	local entry = KeybindEntry(keybind)
	if not entry then return "no such keybind" end
	if entry.visible and not entry.visible(entry) then return "hidden" end
	entry.callback(false)
	if entry.handlesKeyUp then
		AdvanceGameTime(holdMs or 0)
		entry.callback(true)
	end
	return "pressed"
end

-- Half a press: the key went down and the strip never told anybody it came up, which is what
-- a screen change under a held button looks like from here.
function PressKeybindDownOnly(keybind)
	local entry = KeybindEntry(keybind)
	if not entry then return "no such keybind" end
	entry.callback(false)
	return "down"
end

function KeybindLabel(keybind)
	local entry = KeybindEntry(keybind)
	if not entry then return nil end
	local name = entry.name
	if type(name) == "function" then return name(entry) end
	return name
end

-- Opening the chat screen: the state change the client publishes, and nothing else. If the
-- add-on ever needs more than this to work, it is doing more than it should.
function OpenChatScreen(state)
	for _, fn in ipairs(CHAT_MENU_GAMEPAD_SCENE.callbacks["StateChange"] or {}) do
		fn(SCENE_HIDDEN, state or SCENE_SHOWING)
	end
end

-- ---- settings library ---------------------------------------------------------------
-- Present so InitSettings runs and its closures are exercised; the rows are recorded by label
-- so a test can move a slider or press a button.
Panel = nil
LibHarvensAddonSettings = {
	ST_LABEL = 1, ST_SECTION = 2, ST_CHECKBOX = 3, ST_SLIDER = 4, ST_DROPDOWN = 5, ST_BUTTON = 6,
	AddAddon = function(_, title)
		Panel = {
			title = title,
			rows = {},
			byLabel = {},
			AddSetting = function(self, row)
				self.rows[#self.rows + 1] = row
				if row.label then self.byLabel[row.label] = row end
			end,
			UpdateControls = function(self) self.updates = (self.updates or 0) + 1 end,
		}
		return Panel
	end,
}

function PanelRow(stringId)
	return Panel and Panel.byLabel[GetString(stringId)]
end

-- ---- load the add-on ----------------------------------------------------------------
dofile(DIR .. "/lang/strings.lua")
dofile(DIR .. "/Main.lua")
dofile(DIR .. "/Dice.lua")
dofile(DIR .. "/Keybind.lua")
dofile(DIR .. "/Prefill.lua")
dofile(DIR .. "/Settings.lua")
