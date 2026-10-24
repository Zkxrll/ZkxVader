-- ZkxVader - a fork of Vaderhaxx (https://github.com/i77lhm/Libraries/tree/main/Vaderhaxx) by i77lhm, MIT licensed (see LICENSE).
-- Changes: Obsidian-style API (Toggles/Options objects, groupboxes, tabboxes, dependency boxes, dialogs, search, viewport), collapsible sections,
-- scrolling tab strip with a gliding underline, page/window/notification transitions, text effects (scramble, shimmer, glitch, wave, rainbow),
-- inset-aware popups, theme registry that really re-themes, clean unload, font fallback when the pixel font cannot be downloaded.
return (function()
-- ==== 00_core.lua ====
-- ZkxVader core: a fork of Vaderhaxx (ImInsane-1337/Libraries, discontinued 2024) extended with an Obsidian-style API.
-- This chunk defines everything the other fork files share: services, palette + theme registry, font, tween helper, signals, the Library table.
-- Joined with the other fork files by build_fork.py; the whole thing is one function body that returns Library.

local cloneref = (cloneref or clonereference or function(instance) return instance end)
local function svc(name) return cloneref(game:GetService(name)) end

local UserInputService = svc('UserInputService')
local Players = svc('Players')
local RunService = svc('RunService')
local TweenService = svc('TweenService')
local TextService = svc('TextService')
local HttpService = svc('HttpService')
local GuiService = svc('GuiService')
local CoreGui = svc('CoreGui')

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer and LocalPlayer:GetMouse()

local rgb, hsv, dim2, dim, vec2 = Color3.fromRGB, Color3.fromHSV, UDim2.new, UDim.new, Vector2.new
local floor, clamp, max, min, abs, sin = math.floor, math.clamp, math.max, math.min, math.abs, math.sin

--// Library table (the Obsidian-shaped surface lives here) \\--
local Library = {
	Version = 'ZkxVader 1.0 (Vaderhaxx fork)',
	Toggles = {},
	Options = {},
	Labels = {},
	Buttons = {},
	Tabs = {},
	Signals = {},
	UnloadSignals = {},
	OnUnload = nil, -- function Library:OnUnload(fn)
	Unloaded = false,
	Toggled = false,
	ShowCustomCursor = true,
	NotifyOnError = false,
	NotifySide = 'Left',
	CornerRadius = 0,
	ActiveLoading = nil,
	Window = nil,
	ScreenGui = nil,
	KeybindFrame = nil,
	ToggleKeybind = nil,
	Animations = { Enabled = true, Time = 0.18 },
	ThemeFade = true,
	DPIScale = 100,
	TextSize = 12,
	IsMobile = false,
	DependencyBoxes = {},
	Registry = setmetatable({}, { __mode = 'k' }), -- instance -> { Property = paletteKey }
}
Library.__index = Library

--// Palette (Vaderhaxx defaults). a..g are the layered grays of the original, accent is its yellow. \\--
local DefaultPalette = {
	accent = rgb(255, 200, 69),
	text = rgb(255, 255, 255),
	a = rgb(0, 0, 0),
	b = rgb(56, 56, 56),
	c = rgb(46, 46, 46),
	d = rgb(12, 12, 12),
	e = rgb(21, 21, 21),
	f = rgb(84, 84, 84),
	g = rgb(54, 54, 54),
	risky = rgb(255, 80, 80),
	dim = rgb(150, 150, 150),
}
local Palette = {}
for key, value in pairs(DefaultPalette) do Palette[key] = value end
Library.Palette = Palette

-- Obsidian's five-colour Scheme maps onto the palette (ThemeManager edits Scheme, then calls UpdateColorsUsingRegistry)
Library.Scheme = {
	BackgroundColor = DefaultPalette.e,
	MainColor = DefaultPalette.c,
	AccentColor = DefaultPalette.accent,
	OutlineColor = DefaultPalette.b,
	FontColor = DefaultPalette.text,
	DarkColor = DefaultPalette.d,
	RedColor = DefaultPalette.risky,
	WhiteColor = rgb(255, 255, 255),
	Font = nil, -- filled in below once the font exists
}

--// Font: ProggyClean (the Vaderhaxx pixel font). Cached next to the hub's other files, falls back to a monospace stock font. \\--
local FONT_URL = 'https://github.com/i77lhm/storage/raw/refs/heads/main/fonts/ProggyClean.ttf'
local FONT_DIR = 'ZkxVader'
local function loadPixelFont()
	local canFile = type(isfile) == 'function' and type(writefile) == 'function' and type(getcustomasset) == 'function'
	if not canFile then return nil end
	local okFont, font = pcall(function()
		if type(isfolder) == 'function' and type(makefolder) == 'function' then
			if not isfolder(FONT_DIR) then makefolder(FONT_DIR) end
		end
		local ttf, family = FONT_DIR .. '/ProggyClean.ttf', FONT_DIR .. '/ProggyClean.json'
		if not isfile(ttf) then
			local data = game:HttpGet(FONT_URL)
			if type(data) ~= 'string' or #data < 1000 then error('font download failed') end
			writefile(ttf, data)
		end
		if not isfile(family) then
			writefile(
				family,
				HttpService:JSONEncode({
					name = 'ProggyClean',
					faces = { { name = 'Regular', weight = 400, style = 'normal', assetId = getcustomasset(ttf) } },
				})
			)
		end
		return Font.new(getcustomasset(family), Enum.FontWeight.Regular)
	end)
	if okFont then return font end
	return nil
end
Library.PixelFont = loadPixelFont()
Library.Font = Library.PixelFont or Font.fromEnum(Enum.Font.Code)
Library.Scheme.Font = Library.Font

--// Registries: themed properties and text objects \\--
local TextObjects = setmetatable({}, { __mode = 'k' })
local TEXT_CLASSES = { TextLabel = true, TextButton = true, TextBox = true }

local function ThemeSet(instance, property, key)
	local entry = Library.Registry[instance]
	if not entry then
		entry = {}
		Library.Registry[instance] = entry
	end
	entry[property] = key
	instance[property] = Palette[key]
end
Library.Theme = ThemeSet

--// Tweens (never delay a value, only its look) \\--
local function Animating() return Library.Animations.Enabled and not Library.Unloaded end
local function Tween(instance, properties, time, style, direction)
	if not Animating() or not instance or not instance.Parent then
		for property, value in pairs(properties) do pcall(function() instance[property] = value end) end
		return nil
	end
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(time or Library.Animations.Time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		properties
	)
	tween:Play()
	return tween
end
Library.Tween = Tween

--// Instance factory: New(class, props, themed) \\--
local function New(class, props, themed)
	local instance = Instance.new(class)
	local parent = nil
	for property, value in pairs(props or {}) do
		if property == 'Parent' then
			parent = value
		else
			instance[property] = value
		end
	end
	if TEXT_CLASSES[class] then
		TextObjects[instance] = true
		if not (props and props.FontFace) then instance.FontFace = Library.Font end
		if not (props and props.TextSize) then instance.TextSize = Library.TextSize end
		if not (props and props.TextColor3) and not (themed and themed.TextColor3) then ThemeSet(instance, 'TextColor3', 'text') end
		if instance.ClassName ~= 'TextBox' then instance.TextWrapped = props and props.TextWrapped or false end
	end
	if class == 'Frame' or class == 'TextButton' or class == 'ImageButton' or class == 'ScrollingFrame' or class == 'TextLabel' then
		if not (props and props.BorderSizePixel) then instance.BorderSizePixel = 0 end
	end
	if themed then
		for property, key in pairs(themed) do
			ThemeSet(instance, property, key)
		end
	end
	if parent then instance.Parent = parent end
	return instance
end
Library.New = New

--// Signals / unload \\--
function Library:GiveSignal(signal)
	table.insert(Library.Signals, signal)
	return signal
end
local function Connect(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(Library.Signals, connection)
	return connection
end
function Library:OnUnload(callback) table.insert(Library.UnloadSignals, callback) end

function Library:SafeCallback(callback, ...)
	if type(callback) ~= 'function' then return nil end
	local results = table.pack(xpcall(callback, function(err) return debug.traceback(tostring(err), 2) end, ...))
	if results[1] then return table.unpack(results, 2, results.n) end
	if Library.NotifyOnError and Library.Notify then pcall(Library.Notify, Library, 'Callback error: ' .. tostring(results[2]):sub(1, 140)) end
	warn('[ZkxVader] callback error: ' .. tostring(results[2]))
	return nil
end
local SafeCallback = function(...) return Library:SafeCallback(...) end

--// Small helpers shared by every widget \\--
local function TextWidth(text, size, font)
	local ok, bounds = pcall(function()
		local params = Instance.new('GetTextBoundsParams')
		params.Text = text
		params.Font = font or Library.Font
		params.Size = size or Library.TextSize
		params.Width = 10000
		return TextService:GetTextBoundsAsync(params)
	end)
	if ok and bounds then return bounds.X end
	return #tostring(text) * 6
end

local function Round(number, step)
	step = step or 1
	if step == 0 then return number end
	local inverse = 1 / step
	return floor(number * inverse + 0.5) / inverse
end

-- mouse position in the same space as GuiObject.AbsolutePosition (AbsolutePosition is offset by the top-bar inset, GetMouseLocation is not)
local function MouseAbs() return UserInputService:GetMouseLocation() - GuiService:GetGuiInset() end
Library.MouseAbs = MouseAbs

local function IsMouseOver(gui)
	local position = MouseAbs()
	local corner, size = gui.AbsolutePosition, gui.AbsoluteSize
	return position.X >= corner.X and position.X <= corner.X + size.X and position.Y >= corner.Y and position.Y <= corner.Y + size.Y
end

local function UIParent()
	if type(gethui) == 'function' then
		local ok, holder = pcall(gethui)
		if ok and holder then return holder end
	end
	return CoreGui
end

-- Window-level bookkeeping the widgets need
Library.Popup = nil -- the one open popup (dropdown list / colour picker / key menu); opening another closes it
function Library:ClosePopup()
	local popup = Library.Popup
	Library.Popup = nil
	if popup and popup.Close then popup.Close() end
end
function Library:OpenPopup(popup)
	if Library.Popup and Library.Popup ~= popup then Library:ClosePopup() end
	Library.Popup = popup
end

-- Shared class tables (each later file is a do-block, so top-level locals stay far below Luau's 200 limit; cross-file things live here)
local Classes = { Window = {}, Tab = {}, Groupbox = {}, Tabbox = {}, Container = {}, Dialog = {} }
for _, class in pairs(Classes) do class.__index = class end
Library.Classes = Classes

-- nested 1px outlines (the Vaderhaxx look): Panel(parent, {'a','c','e'}, { Size = ..., Position = ..., Auto = true })
-- returns the outermost and the innermost frame; content goes into the innermost one
local function Panel(parent, keys, props)
	props = props or {}
	local outer, current = nil, parent
	for index, key in ipairs(keys) do
		local frame = New('Frame', {
			Size = (index == 1 and props.Size) or (props.Auto and dim2(1, 0, 0, 0) or dim2(1, 0, 1, 0)),
			Position = index == 1 and props.Position or nil,
			AnchorPoint = index == 1 and props.AnchorPoint or nil,
			AutomaticSize = props.Auto and Enum.AutomaticSize.Y or Enum.AutomaticSize.None,
			BackgroundTransparency = (index == #keys and props.InnerTransparency) or 0,
			ClipsDescendants = (index == #keys) and props.Clip or false,
			Parent = current,
		}, { BackgroundColor3 = key })
		if index < #keys then New('UIPadding', { PaddingTop = dim(0, 1), PaddingBottom = dim(0, 1), PaddingLeft = dim(0, 1), PaddingRight = dim(0, 1), Parent = frame }) end
		outer = outer or frame
		current = frame
	end
	return outer, current
end
Library.Panel = Panel

-- ==== 10_fx.lua ====
-- ZkxVader FX: the "crazy text". One shared Heartbeat drives every looping effect; one-shots (scramble, typewriter, glitch) run on their own short threads.
-- Rules: the value/text is final first, the effect only decorates; at rest the label shows its plain text; nothing here changes layout size;
-- everything stops when animations are off, the menu is closed, or the label is gone.

local FX = { Loops = {}, Count = 0 }
Library.FX = FX

local SCRAMBLE_GLYPHS = '!<>-_\\/[]{}=+*^?#%&$@01'
local loopConnection = nil

local function alive(label) return label and label.Parent ~= nil and not Library.Unloaded end

-- a looping effect only ticks while its label is on screen and the menu is open (or the effect is flagged always-on, e.g. notifications)
local function visible(item)
	local label = item.label
	if not alive(label) then return false end
	if not item.always and not Library.Toggled then return false end
	return label.AbsoluteSize.X > 0
end

local function startLoop()
	if loopConnection then return end
	loopConnection = RunService.Heartbeat:Connect(function(dt)
		if Library.Unloaded then return end
		local now = os.clock()
		for id, item in pairs(FX.Loops) do
			if not alive(item.label) then
				FX.Loops[id] = nil
				FX.Count -= 1
			elseif Animating() and visible(item) then
				if not item.rate or now - (item.last or 0) >= item.rate then
					item.last = now
					item.step(now, dt)
				end
			end
		end
	end)
	table.insert(Library.Signals, loopConnection)
end

local nextId = 0
local function addLoop(label, step, options)
	options = options or {}
	nextId += 1
	local id = nextId
	FX.Loops[id] = { label = label, step = step, rate = options.rate, always = options.always }
	FX.Count += 1
	startLoop()
	local handle = {}
	function handle.Stop()
		if FX.Loops[id] then
			FX.Loops[id] = nil
			FX.Count -= 1
		end
		if options.restore then pcall(options.restore) end
	end
	return handle
end

local function rainbowSequence(offset)
	local keys = {}
	for index = 0, 6 do
		table.insert(keys, ColorSequenceKeypoint.new(index / 6, hsv((offset + index / 6) % 1, 1, 1)))
	end
	return ColorSequence.new(keys)
end

-- moving rainbow gradient over the text (title, watermark). Speed 0.2 = a full cycle in 5 seconds.
function FX.Rainbow(label, options)
	options = options or {}
	local speed = options.speed or 0.2
	local gradient = New('UIGradient', { Color = rainbowSequence(0), Parent = label })
	Library.Registry[label] = nil
	label.TextColor3 = rgb(255, 255, 255)
	gradient.Color = rainbowSequence(0)
	return addLoop(label, function(now) gradient.Color = rainbowSequence(now * speed) end, {
		always = options.always,
		rate = 1 / 30,
		restore = function()
			gradient:Destroy()
			ThemeSet(label, 'TextColor3', 'text')
		end,
	})
end

-- a bright band sweeps over accent coloured text every few seconds
function FX.Shimmer(label, options)
	options = options or {}
	local every, length = options.every or 6, options.length or 0.9
	-- UIGradient multiplies the text colour, so the base is white and the gradient itself carries accent -> white -> accent
	Library.Registry[label] = nil
	label.TextColor3 = rgb(255, 255, 255)
	local function sequence()
		local accent, white = Palette.accent, rgb(255, 255, 255)
		return ColorSequence.new({
			ColorSequenceKeypoint.new(0, accent),
			ColorSequenceKeypoint.new(0.4, accent),
			ColorSequenceKeypoint.new(0.5, white),
			ColorSequenceKeypoint.new(0.6, accent),
			ColorSequenceKeypoint.new(1, accent),
		})
	end
	local gradient = New('UIGradient', { Color = sequence(), Offset = vec2(-1.2, 0), Parent = label })
	return addLoop(label, function(now)
		local phase = (now % every) / length
		gradient.Offset = vec2(phase < 1 and (-1.2 + phase * 2.4) or 1.2, 0)
		gradient.Color = sequence() -- follows theme changes
	end, {
		always = options.always,
		rate = 1 / 30,
		restore = function()
			gradient:Destroy()
			ThemeSet(label, 'TextColor3', 'text')
		end,
	})
end

-- per-character colour wave (RichText). Fine for short strings only.
function FX.Wave(label, options)
	options = options or {}
	local text = options.text or label.Text
	local speed, spread = options.speed or 0.6, options.spread or 0.07
	local base = text
	label.RichText = true
	local function hex(color)
		return string.format('#%02x%02x%02x', floor(color.R * 255), floor(color.G * 255), floor(color.B * 255))
	end
	return addLoop(label, function(now)
		local parts = table.create(#base)
		for index = 1, #base do
			local char = base:sub(index, index)
			if char:match('%s') then
				parts[index] = char
			else
				parts[index] = '<font color="' .. hex(hsv((now * speed + index * spread) % 1, 0.75, 1)) .. '">' .. char .. '</font>'
			end
		end
		label.Text = table.concat(parts)
	end, {
		always = options.always,
		rate = 1 / 20,
		restore = function()
			label.RichText = false
			label.Text = base
		end,
	})
end

-- slow breathing of the text transparency (used for "Risky" and status lines)
function FX.Pulse(label, options)
	options = options or {}
	local depth, speed = options.depth or 0.45, options.speed or 3
	return addLoop(label, function(now) label.TextTransparency = (sin(now * speed) * 0.5 + 0.5) * depth end, {
		always = options.always,
		rate = 1 / 30,
		restore = function() label.TextTransparency = 0 end,
	})
end

--// one-shots \\--
local function oneShot(label, text, duration, frame)
	if not Animating() or not duration or duration <= 0 then
		label.Text = text
		return
	end
	local token = (label:GetAttribute('FXToken') or 0) + 1
	label:SetAttribute('FXToken', token)
	task.spawn(function()
		local started = os.clock()
		while alive(label) and label:GetAttribute('FXToken') == token do
			local alpha = clamp((os.clock() - started) / duration, 0, 1)
			if alpha >= 1 then break end
			label.Text = frame(alpha)
			RunService.Heartbeat:Wait()
		end
		if alive(label) and label:GetAttribute('FXToken') == token then label.Text = text end
	end)
end

-- random glyphs that settle left to right into the real text
function FX.Scramble(label, text, duration)
	text = text or label.Text
	oneShot(label, text, duration or 0.35, function(alpha)
		local settled = floor(alpha * #text)
		local out = table.create(#text)
		for index = 1, #text do
			local char = text:sub(index, index)
			if index <= settled or char:match('%s') then
				out[index] = char
			else
				local pick = math.random(1, #SCRAMBLE_GLYPHS)
				out[index] = SCRAMBLE_GLYPHS:sub(pick, pick)
			end
		end
		return table.concat(out)
	end)
end

-- characters appear one by one
function FX.Typewriter(label, text, charactersPerSecond)
	text = text or label.Text
	local rate = charactersPerSecond or 35
	oneShot(label, text, #text / rate, function(alpha) return text:sub(1, floor(alpha * #text)) end)
end

-- two coloured ghosts jitter behind the text for a moment
function FX.Glitch(label, duration)
	if not Animating() or not alive(label) then return end
	duration = duration or 0.22
	local ghosts = {}
	for index, tint in ipairs({ rgb(255, 40, 80), rgb(40, 220, 255) }) do
		local ghost = New('TextLabel', {
			Text = label.Text,
			TextColor3 = tint,
			TextTransparency = 0.45,
			TextSize = label.TextSize,
			FontFace = label.FontFace,
			BackgroundTransparency = 1,
			TextXAlignment = label.TextXAlignment,
			TextYAlignment = label.TextYAlignment,
			Size = dim2(1, 0, 1, 0),
			ZIndex = label.ZIndex + (index == 1 and -1 or 0),
			Parent = label,
		})
		ghost.TextColor3 = tint
		table.insert(ghosts, ghost)
	end
	task.spawn(function()
		local started = os.clock()
		while alive(label) and os.clock() - started < duration do
			for index, ghost in ipairs(ghosts) do
				ghost.Position = dim2(0, math.random(-2, 2) * (index == 1 and 1 or -1), 0, math.random(-1, 1))
			end
			RunService.Heartbeat:Wait()
		end
		for _, ghost in ipairs(ghosts) do ghost:Destroy() end
	end)
end

function FX.Stop(handle)
	if handle and handle.Stop then handle.Stop() end
end

-- ==== 20_window.lua ====
-- ZkxVader window: screen gui, layered panel, header, scrolling tab strip with a gliding underline, pages, drag/resize, theme + DPI, keybind list.
do
	local Window, Tab = Classes.Window, Classes.Tab
	local Scalers = {}

	local function GetScale() return Library.DPIScale / 100 end
	Library.GetScale = GetScale

	--// drag / resize \\--
	local function MakeDraggable(frame, handle, onMoved)
		handle = handle or frame
		local dragging, startMouse, startPosition = false, nil, nil
		Connect(handle.InputBegan, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging, startMouse, startPosition = true, input.Position, frame.Position
				Library:ClosePopup()
			end
		end)
		Connect(UserInputService.InputChanged, function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				local delta = (input.Position - startMouse) / GetScale()
				frame.Position = UDim2.new(
					startPosition.X.Scale,
					startPosition.X.Offset + delta.X,
					startPosition.Y.Scale,
					startPosition.Y.Offset + delta.Y
				)
				if onMoved then onMoved() end
			end
		end)
		Connect(UserInputService.InputEnded, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
		end)
	end
	Library.MakeDraggable = MakeDraggable

	local function MakeResizable(frame, grip, minimum)
		local resizing, startMouse, startSize = false, nil, nil
		Connect(grip.InputBegan, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				resizing, startMouse, startSize = true, input.Position, frame.AbsoluteSize / GetScale()
				Library:ClosePopup()
			end
		end)
		Connect(UserInputService.InputChanged, function(input)
			if resizing and input.UserInputType == Enum.UserInputType.MouseMovement then
				local delta = (input.Position - startMouse) / GetScale()
				frame.Size = UDim2.fromOffset(max(minimum.X, startSize.X + delta.X), max(minimum.Y, startSize.Y + delta.Y))
			end
		end)
		Connect(UserInputService.InputEnded, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then resizing = false end
		end)
	end

	--// theme \\--
	function Library:UpdateColorsUsingRegistry()
		local scheme = Library.Scheme
		local e, c, b = scheme.BackgroundColor, scheme.MainColor, scheme.OutlineColor
		Palette.accent, Palette.text, Palette.e, Palette.c, Palette.b = scheme.AccentColor, scheme.FontColor, e, c, b
		Palette.d = Color3.new(e.R * 0.57, e.G * 0.57, e.B * 0.57)
		Palette.f = b:Lerp(rgb(255, 255, 255), 0.14)
		Palette.g = c:Lerp(b, 0.8)
		Palette.dim = scheme.FontColor:Lerp(e, 0.45)
		Palette.risky = scheme.RedColor or DefaultPalette.risky
		local fade = Library.ThemeFade and Animating()
		for instance, properties in pairs(Library.Registry) do
			if instance.Parent then
				for property, key in pairs(properties) do
					local color = Palette[key]
					if fade and instance:IsA('GuiObject') and instance.AbsoluteSize.X > 0 then
						TweenService:Create(instance, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { [property] = color }):Play()
					else
						instance[property] = color
					end
				end
			end
		end
		if Library.OnThemeChanged then pcall(Library.OnThemeChanged) end
	end

	function Library:SetFont(font)
		local face = font
		if typeof(font) == 'EnumItem' then face = Font.fromEnum(font) end
		if typeof(face) ~= 'Font' then return end
		Library.Font = face
		Library.Scheme.Font = face
		for instance in pairs(TextObjects) do
			pcall(function() instance.FontFace = face end)
		end
	end

	function Library:SetDPIScale(percent)
		percent = tonumber(percent) or 100
		Library.DPIScale = clamp(percent, 40, 250)
		for _, scaler in ipairs(Scalers) do
			scaler.Scale = GetScale()
		end
		if Library.Main then Library.Main.Size = UDim2.fromScale(1 / GetScale(), 1 / GetScale()) end
	end

	function Library:SetBackgroundImage(image)
		local window = Library.Window
		if not (window and window.BackgroundImage) then return end
		image = tostring(image or '')
		window.BackgroundImage.Image = image
		window.BackgroundImage.Visible = image ~= ''
	end

	function Library:GetCustomIcon() return nil end -- the Vaderhaxx look has no tab icons

	--// open / close \\--
	function Library:Toggle(value)
		local window = Library.Window
		if not window or Library.Unloaded then return end
		local target
		if typeof(value) == 'boolean' then
			target = value
		else
			target = not Library.Toggled
		end
		if target == Library.Toggled then return end
		Library.Toggled = target
		local root, curtain = window.Root, window.Curtain
		window.OpenToken = (window.OpenToken or 0) + 1
		local token = window.OpenToken
		if target then
			local home = window.HomePosition or root.Position
			window.HomePosition = nil
			root.Visible = true
			if Animating() then
				root.Position = UDim2.new(home.X.Scale, home.X.Offset, home.Y.Scale, home.Y.Offset + 12)
				curtain.BackgroundTransparency = 0
				Tween(root, { Position = home }, 0.26, Enum.EasingStyle.Quint)
				Tween(curtain, { BackgroundTransparency = 1 }, 0.28, Enum.EasingStyle.Quad)
			else
				root.Position, curtain.BackgroundTransparency = home, 1
			end
			if not window.Introduced then
				window.Introduced = true
				FX.Scramble(window.TitleLabel, window.TitleText, 0.55)
			end
		else
			Library:ClosePopup()
			local home = root.Position
			if Animating() then
				window.HomePosition = home
				Tween(root, { Position = UDim2.new(home.X.Scale, home.X.Offset, home.Y.Scale, home.Y.Offset + 10) }, 0.16, Enum.EasingStyle.Quad)
				Tween(curtain, { BackgroundTransparency = 0 }, 0.16, Enum.EasingStyle.Quad)
				task.delay(0.17, function()
					if window.OpenToken == token and not Library.Toggled then
						root.Visible = false
						root.Position = home
						window.HomePosition = nil
					end
				end)
			else
				root.Visible = false
			end
		end
		if Library.OnToggled then pcall(Library.OnToggled, target) end
	end

	-- the screen gui, the scaled main frame and the popup overlay; made on demand (Notify may run before any window exists)
	function Library:EnsureGui()
		if Library.ScreenGui and Library.ScreenGui.Parent then return Library.ScreenGui end
		local gui = New('ScreenGui', {
			Name = 'ZkxVader',
			ResetOnSpawn = false,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			IgnoreGuiInset = true,
			DisplayOrder = 1000,
		})
		gui.Parent = UIParent()
		Library.ScreenGui = gui
		local main = New('Frame', { Name = 'Main', BackgroundTransparency = 1, Size = UDim2.fromScale(1 / GetScale(), 1 / GetScale()), Parent = gui })
		Library.Main = main
		table.insert(Scalers, New('UIScale', { Scale = GetScale(), Parent = main }))
		Library.Overlay = New('Frame', { Name = 'Overlay', BackgroundTransparency = 1, Size = dim2(1, 0, 1, 0), ZIndex = 100, Parent = main })
		return gui
	end

	--// window \\--
	function Library:CreateWindow(info)
		info = info or {}
		if Library.Window then return Library.Window end
		local self = setmetatable({ Tabs = {}, Library = Library, Info = info }, Window)
		Library.Window = self
		Library.CornerRadius = info.CornerRadius or Library.CornerRadius
		Library.NotifySide = info.NotifySide or Library.NotifySide
		if info.ShowCustomCursor ~= nil then Library.ShowCustomCursor = info.ShowCustomCursor end
		if info.Font then Library:SetFont(info.Font) end

		Library:EnsureGui()
		local main = Library.Main

		-- the window: black > gray > dark gray > dark gray > gray > translucent black, like upstream
		local size = info.Size or UDim2.fromOffset(920, 640)
		local position = info.Position
		if info.Center ~= false and (info.Center == true or position == nil) then
			position = UDim2.new(0.5, -size.X.Offset / 2, 0.5, -size.Y.Offset / 2)
		end
		local root, body = Panel(main, { 'a', 'b', 'c', 'c', 'b', 'a' }, { Size = size, Position = position or UDim2.fromOffset(60, 60), InnerTransparency = 0.35 })
		root.Name = 'Window'
		root.Visible = false
		self.Root, self.Body = root, body

		-- image behind the content (ThemeManager "Background Image")
		self.BackgroundImage = New('ImageLabel', {
			BackgroundTransparency = 1, ImageTransparency = 0.8, Size = dim2(1, 0, 1, 0), ScaleType = Enum.ScaleType.Crop, Visible = false, ZIndex = 0, Parent = body,
		})
		-- lets the mouse go free while the menu is open (first person games lock it)
		New('TextButton', { Text = '', Modal = true, BackgroundTransparency = 1, Size = dim2(0, 0, 0, 0), Parent = root })

		-- header: logo, shimmering title, footer on the right
		local header = New('Frame', { Name = 'Header', BackgroundTransparency = 1, Position = dim2(0, 14, 0, 8), Size = dim2(1, -28, 0, 24), Active = true, Parent = body })
		local textLeft = 0
		if info.Icon then
			self.IconLabel = New('ImageLabel', {
				BackgroundTransparency = 1, Image = tostring(info.Icon), Size = info.IconSize or UDim2.fromOffset(22, 22), Position = dim2(0, 0, 0.5, 0), AnchorPoint = vec2(0, 0.5), Parent = header,
			})
			textLeft = (info.IconSize and info.IconSize.X.Offset or 22) + 8
		end
		self.TitleHolder = header
		self.TitleText = tostring(info.Title or 'ZkxVader')
		self.TitleLabel = New('TextLabel', {
			Text = self.TitleText, BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left, AutomaticSize = Enum.AutomaticSize.X,
			Size = dim2(0, 0, 1, 0), Position = dim2(0, textLeft, 0, 0), TextSize = 14, ZIndex = 2, Parent = header,
		})
		FX.Shimmer(self.TitleLabel, { every = 6 })
		self.FooterLabel = New('TextLabel', {
			Text = tostring(info.Footer or ''), BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Right, Size = dim2(0.5, 0, 1, 0),
			Position = dim2(0.5, 0, 0, 0), TextSize = 12, ZIndex = 2, Parent = header,
		}, { TextColor3 = 'dim' })
		MakeDraggable(root, header)
		MakeDraggable(root, root)

		-- tab strip: scrolls sideways when the tabs do not fit, accent underline glides under the active tab
		local bar = New('Frame', { Name = 'TabBar', BackgroundTransparency = 1, Position = dim2(0, 14, 0, 38), Size = dim2(1, -28, 0, 28), ClipsDescendants = true, Parent = body })
		New('Frame', { Name = 'Baseline', AnchorPoint = vec2(0, 1), Position = dim2(0, 0, 1, 0), Size = dim2(1, 0, 0, 2), Parent = bar }, { BackgroundColor3 = 'f' })
		local strip = New('ScrollingFrame', {
			Name = 'Strip', BackgroundTransparency = 1, Size = dim2(1, 0, 1, 0), ScrollBarThickness = 0, ScrollingDirection = Enum.ScrollingDirection.X,
			AutomaticCanvasSize = Enum.AutomaticSize.X, CanvasSize = dim2(0, 0, 0, 0), Parent = bar,
		})
		New('UIListLayout', { FillDirection = Enum.FillDirection.Horizontal, Padding = dim(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = strip })
		local underline = New('Frame', { Name = 'Underline', AnchorPoint = vec2(0, 1), Position = dim2(0, 0, 1, 0), Size = dim2(0, 0, 0, 3), ZIndex = 3, Parent = bar }, { BackgroundColor3 = 'accent' })
		New('Frame', { Size = dim2(1, 0, 0, 1), BackgroundColor3 = rgb(255, 255, 255), BackgroundTransparency = 0.7, ZIndex = 4, Parent = underline })
		self.TabBar, self.Strip, self.Underline = bar, strip, underline
		-- wheel scrolls the strip sideways
		Connect(bar.InputChanged, function(input)
			if input.UserInputType == Enum.UserInputType.MouseWheel then
				strip.CanvasPosition = Vector2.new(max(0, strip.CanvasPosition.X - input.Position.Z * 60), 0)
			end
		end)

		-- page area
		local holder, pages = Panel(body, { 'a', 'c', 'e' }, { Position = dim2(0, 14, 0, 70), Size = dim2(1, -28, 1, -84), Clip = true })
		holder.Name = 'Pages'
		self.PageHolder, self.Pages = holder, pages

		-- the window curtain: fades the whole window in and out (cheaper than a CanvasGroup)
		self.Curtain = New('Frame', { Name = 'Curtain', BackgroundTransparency = 1, Size = dim2(1, 0, 1, 0), ZIndex = 60, Active = false, Parent = body }, { BackgroundColor3 = 'a' })

		-- resize grip
		local grip = New('TextButton', { Text = '', BackgroundTransparency = 1, AnchorPoint = vec2(1, 1), Position = dim2(1, -2, 1, -2), Size = dim2(0, 14, 0, 14), ZIndex = 70, Parent = body })
		for index = 1, 3 do
			New('Frame', { AnchorPoint = vec2(1, 1), Position = dim2(1, -2, 1, -2 - (index - 1) * 3), Size = dim2(0, index * 3, 0, 1), BackgroundTransparency = 0.4, ZIndex = 71, Parent = grip }, { BackgroundColor3 = 'f' })
		end
		MakeResizable(root, grip, Vector2.new(560, 380))

		-- keybind list (a draggable panel; Library.KeybindFrame.Visible / .Position are what SaveManager saves)
		local keybindFrame, keybindInner = Panel(main, { 'a', 'b', 'e' }, { Position = dim2(0, 14, 0.45, 0), Size = dim2(0, 190, 0, 0), Auto = true })
		keybindFrame.Name = 'Keybinds'
		keybindFrame.Visible = false
		keybindFrame.ZIndex = 40
		local keybindTitle = New('TextLabel', {
			Text = 'keybinds', BackgroundTransparency = 1, Size = dim2(1, 0, 0, 18), TextSize = 12, Active = true, Parent = keybindInner,
		}, { TextColor3 = 'accent' })
		New('UIListLayout', { SortOrder = Enum.SortOrder.LayoutOrder, Parent = keybindInner })
		local keybindList = New('Frame', { BackgroundTransparency = 1, Size = dim2(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Parent = keybindInner })
		New('UIListLayout', { SortOrder = Enum.SortOrder.LayoutOrder, Parent = keybindList })
		New('UIPadding', { PaddingLeft = dim(0, 6), PaddingRight = dim(0, 6), PaddingBottom = dim(0, 4), Parent = keybindList })
		MakeDraggable(keybindFrame, keybindTitle)
		Library.KeybindFrame, Library.KeybindContainer = keybindFrame, keybindList

		-- menu key (Library.ToggleKeybind is Enum.KeyCode by default, the hub replaces it with its MenuKeybind key picker)
		Library.ToggleKeybind = info.ToggleKeybind or Enum.KeyCode.RightControl
		Connect(UserInputService.InputBegan, function(input, processed)
			if processed or Library.Unloaded then return end
			local bind = Library.ToggleKeybind
			if typeof(bind) == 'EnumItem' then
				if input.KeyCode == bind then Library:Toggle() end
			elseif typeof(bind) == 'table' and bind.Type == 'KeyPicker' then
				-- the key picker itself calls Library:Toggle when it fires (see the key picker); nothing to do here
			end
		end)

		if info.DisableSearch ~= true and self.BuildSearch then self:BuildSearch() end
		self:WatchResize()
		task.defer(function()
			if Library.Unloaded then return end
			if info.AutoShow ~= false and info.AutoShow ~= nil then Library:Toggle(true) end
		end)
		return self
	end

	--// tabs \\--
	function Window:SetAnimations(map, time, offset)
		Library.Animations.Enabled = true
		if type(map) == 'table' then
			local any = false
			for _, enabled in pairs(map) do any = any or enabled == true end
			Library.Animations.Enabled = any
		end
		if tonumber(time) then Library.Animations.Time = clamp(tonumber(time), 0.08, 0.6) end
	end

	local function placeUnderline(window, tab, instant)
		local button, bar, underline = tab.Button, window.TabBar, window.Underline
		local scale = GetScale()
		local x = (button.AbsolutePosition.X - bar.AbsolutePosition.X) / scale
		local width = button.AbsoluteSize.X / scale
		local target = { Position = dim2(0, x, 1, 0), Size = dim2(0, width, 0, 3) }
		if instant or not Animating() or underline.Size.X.Offset == 0 then
			underline.Position, underline.Size = target.Position, target.Size
		else
			Tween(underline, target, 0.24, Enum.EasingStyle.Quint)
		end
	end
	Window.PlaceUnderline = placeUnderline

	function Window:AddTab(name, icon, description)
		name = tostring(name)
		local tab = setmetatable({ Window = self, Library = Library, Name = name, Groupboxes = {}, Tabboxes = {}, Description = description }, Tab)
		tab.Button = New('TextButton', {
			Text = name:lower(), AutoButtonColor = false, BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X, Size = dim2(0, 0, 1, -2),
			LayoutOrder = #self.Tabs + 1, TextSize = 12, Parent = self.Strip,
		}, { TextColor3 = 'dim' })
		New('UIPadding', { PaddingLeft = dim(0, 12), PaddingRight = dim(0, 12), Parent = tab.Button })
		Connect(tab.Button:GetPropertyChangedSignal('AbsoluteSize'), function()
			if self.ActiveTab == tab then placeUnderline(self, tab, true) end
		end)
		Connect(tab.Button.MouseEnter, function()
			if self.ActiveTab ~= tab then Tween(tab.Button, { TextColor3 = Palette.text }, 0.12) end
		end)
		Connect(tab.Button.MouseLeave, function()
			if self.ActiveTab ~= tab then Tween(tab.Button, { TextColor3 = Palette.dim }, 0.12) end
		end)

		tab.Page = New('Frame', { Name = name, BackgroundTransparency = 1, Size = dim2(1, 0, 1, 0), Visible = false, Parent = self.Pages })
		local function column(side)
			local scroller = New('ScrollingFrame', {
				Name = side, BackgroundTransparency = 1, ScrollBarThickness = 2, ScrollBarImageTransparency = 0.2, AutomaticCanvasSize = Enum.AutomaticSize.Y,
				CanvasSize = dim2(0, 0, 0, 0), ScrollingDirection = Enum.ScrollingDirection.Y, Active = true,
				Position = side == 'Left' and dim2(0, 12, 0, 12) or dim2(0.5, 6, 0, 12), Size = dim2(0.5, -18, 1, -24), Parent = tab.Page,
			})
			Library.Theme(scroller, 'ScrollBarImageColor3', 'accent')
			New('UIListLayout', { Padding = dim(0, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroller })
			New('UIPadding', { PaddingTop = dim(0, 10), PaddingRight = dim(0, 6), PaddingBottom = dim(0, 4), Parent = scroller })
			-- intro curtain (fakes a fade of the column from the page colour)
			local curtain = New('Frame', { BackgroundTransparency = 1, Position = scroller.Position, Size = scroller.Size, ZIndex = 20, Active = false, Parent = tab.Page }, { BackgroundColor3 = 'e' })
			return scroller, curtain
		end
		tab.Left, tab.LeftCurtain = column('Left')
		tab.Right, tab.RightCurtain = column('Right')
		tab.Sides = { tab.Left, tab.Right } -- the ESP preview freezes the columns' scrolling while its model is orbited

		Connect(tab.Button.MouseButton1Click, function() tab:Show() end)
		table.insert(self.Tabs, tab)
		Library.Tabs[name] = tab
		task.defer(function()
			if self.ActiveTab == tab then placeUnderline(self, tab, true) end
		end)
		if not self.ActiveTab then tab:Show(true) end
		return tab
	end

	function Tab:Show(instant)
		local window = self.Window
		local previous = window.ActiveTab
		if previous == self and not instant then return end
		Library:ClosePopup()
		if previous and previous ~= self then
			previous.Page.Visible = false
			ThemeSet(previous.Button, 'TextColor3', 'dim')
		end
		self.Page.Visible = true
		window.ActiveTab = self
		ThemeSet(self.Button, 'TextColor3', 'text')
		task.defer(function() placeUnderline(window, self, instant == true) end)
		-- keep the active tab inside the visible part of the strip
		task.defer(function()
			local strip, button = window.Strip, self.Button
			local left = button.AbsolutePosition.X - strip.AbsolutePosition.X + strip.CanvasPosition.X
			local right = left + button.AbsoluteSize.X
			if left < strip.CanvasPosition.X then
				strip.CanvasPosition = Vector2.new(max(0, left - 20), 0)
			elseif right > strip.CanvasPosition.X + strip.AbsoluteSize.X then
				strip.CanvasPosition = Vector2.new(right - strip.AbsoluteSize.X + 20, 0)
			end
		end)
		if instant ~= true and Animating() then
			-- columns slide up 14px while a page-coloured curtain fades off; the right column lags by 60 ms
			for index, pair in ipairs({ { self.Left, self.LeftCurtain }, { self.Right, self.RightCurtain } }) do
				local scroller, curtain = pair[1], pair[2]
				local home = scroller.Position
				curtain.BackgroundTransparency = 0
				scroller.Position = UDim2.new(home.X.Scale, home.X.Offset, home.Y.Scale, home.Y.Offset + 14)
				task.delay((index - 1) * 0.06, function()
					if not scroller.Parent then return end
					Tween(scroller, { Position = home }, 0.3, Enum.EasingStyle.Quint)
					Tween(curtain, { BackgroundTransparency = 1 }, 0.3, Enum.EasingStyle.Quad)
				end)
			end
			FX.Scramble(self.Button, self.Name:lower(), 0.3)
		else
			self.LeftCurtain.BackgroundTransparency, self.RightCurtain.BackgroundTransparency = 1, 1
		end
		if Library.OnTabChanged then pcall(Library.OnTabChanged, self) end
	end

	-- tabs created later than the window's first layout need their underline re-aimed when the strip resizes
	local lastSizeSignal = nil
	function Window:WatchResize()
		if lastSizeSignal then return end
		lastSizeSignal = Connect(self.Root:GetPropertyChangedSignal('AbsoluteSize'), function()
			local active = self.ActiveTab
			if active then placeUnderline(self, active, true) end
		end)
	end

	--// unload \\--
	function Library:Unload()
		if Library.Unloaded then return end
		Library.Unloaded = true
		for index = #Library.Signals, 1, -1 do
			local signal = table.remove(Library.Signals, index)
			pcall(function()
				if typeof(signal) == 'RBXScriptConnection' and signal.Connected then signal:Disconnect() end
			end)
		end
		for _, callback in ipairs(Library.UnloadSignals) do
			Library:SafeCallback(callback)
		end
		if Library.ScreenGui then
			pcall(function() Library.ScreenGui:Destroy() end)
			Library.ScreenGui = nil
		end
		if Library.ActiveLoading then
			pcall(function() Library.ActiveLoading:Destroy() end)
			Library.ActiveLoading = nil
		end
		Library.Window = nil
		pcall(function()
			local env = (type(getgenv) == 'function' and getgenv()) or _G
			if env.Library == Library then env.Library = nil end
		end)
	end
end

-- ==== 30_container.lua ====
-- ZkxVader containers: groupbox (collapsible), tabbox, dependency box. Every container shares the Add* mixin (Classes.Container), which the
-- widget files extend. A container owns a `Container` frame (vertical list) that its element rows are parented to.
do
	local Groupbox, Tabbox, Container, Tab = Classes.Groupbox, Classes.Tabbox, Classes.Container, Classes.Tab
	for _, class in ipairs({ Groupbox, Tabbox, Classes.Dialog }) do
		setmetatable(class, { __index = Container })
	end

	function Container:Resize() end -- layouts are automatic; kept for Obsidian API compatibility
	function Container:NextOrder()
		self.Order = (self.Order or 0) + 1
		return self.Order
	end

	--// Reveal: a clipped wrapper whose height eases between 0 and its content (dependency boxes, collapsing groupboxes) \\--
	local function Reveal(parent, layoutOrder, padding)
		local wrapper = New('Frame', { BackgroundTransparency = 1, ClipsDescendants = true, Size = dim2(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = layoutOrder or 0, Parent = parent })
		local content = New('Frame', { BackgroundTransparency = 1, Size = dim2(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = wrapper })
		New('UIListLayout', { Padding = dim(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content })
		if padding then
			New('UIPadding', { PaddingTop = dim(0, padding.Top or 0), PaddingBottom = dim(0, padding.Bottom or 0), PaddingLeft = dim(0, padding.Left or 0), PaddingRight = dim(0, padding.Right or 0), Parent = content })
		end
		local reveal = { Wrapper = wrapper, Content = content, Open = true }
		local token = 0
		function reveal.Set(open, instant)
			if reveal.Open == open and not instant then return end
			reveal.Open = open
			token += 1
			local mine = token
			if instant or not Animating() then
				wrapper.Visible = open
				wrapper.AutomaticSize = open and Enum.AutomaticSize.Y or Enum.AutomaticSize.None
				wrapper.Size = open and dim2(1, 0, 0, 0) or dim2(1, 0, 0, 0)
				return
			end
			if open then
				wrapper.AutomaticSize = Enum.AutomaticSize.None
				wrapper.Size = dim2(1, 0, 0, 0)
				wrapper.Visible = true
				task.defer(function()
					if token ~= mine then return end
					RunService.Heartbeat:Wait() -- one frame so the content has been laid out
					if token ~= mine then return end
					local height = content.AbsoluteSize.Y / max(Library.GetScale(), 0.01)
					Tween(wrapper, { Size = dim2(1, 0, 0, height) }, 0.2, Enum.EasingStyle.Quint)
					task.delay(0.22, function()
						if token == mine and reveal.Open then
							wrapper.AutomaticSize = Enum.AutomaticSize.Y -- hand the height back to the layout
						end
					end)
				end)
			else
				local height = wrapper.AbsoluteSize.Y / max(Library.GetScale(), 0.01)
				wrapper.AutomaticSize = Enum.AutomaticSize.None
				wrapper.Size = dim2(1, 0, 0, height)
				Tween(wrapper, { Size = dim2(1, 0, 0, 0) }, 0.18, Enum.EasingStyle.Quint)
				task.delay(0.2, function()
					if token == mine and not reveal.Open then wrapper.Visible = false end
				end)
			end
		end
		return reveal
	end
	Library.Reveal = Reveal

	--// groupbox: the Vaderhaxx section (title notched into the border), collapsible by clicking the title \\--
	local function newGroupbox(tab, side, name)
		local column = side == 'Left' and tab.Left or tab.Right
		local outer, inner = Panel(column, { 'a', 'c', 'e' }, { Size = dim2(1, 0, 0, 0), Auto = true })
		outer.LayoutOrder = #column:GetChildren()
		local text = tostring(name):lower()
		-- a page-coloured strip behind the title hides the two border lines
		New('Frame', { Size = dim2(0, TextWidth(text, 12) + 12, 0, 3), Position = dim2(0, 5, 0, -2), ZIndex = 4, Parent = inner }, { BackgroundColor3 = 'e' })
		local title = New('TextButton', {
			Text = text, AutoButtonColor = false, BackgroundTransparency = 1, Size = dim2(0, TextWidth(text, 12) + 12, 0, 16), Position = dim2(0, 5, 0, -8),
			TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5, Parent = inner,
		})
		New('UIPadding', { PaddingLeft = dim(0, 6), Parent = title })
		local arrow = New('TextLabel', { Text = '-', BackgroundTransparency = 1, AnchorPoint = vec2(1, 0), Position = dim2(1, -6, 0, -8), Size = dim2(0, 14, 0, 16), TextSize = 12, ZIndex = 5, Parent = inner }, { TextColor3 = 'dim' })
		local reveal = Reveal(inner, 1, { Top = 12, Bottom = 8, Left = 8, Right = 8 })
		local box = setmetatable({
			Tab = tab, Library = Library, Name = name, Side = side, Holder = outer, Container = reveal.Content, Elements = {}, Collapsed = false, Type = 'Groupbox', Reveal = reveal,
		}, Groupbox)
		box.Root = box
		function box:SetCollapsed(collapsed)
			collapsed = collapsed == true
			if box.Collapsed == collapsed then return end
			box.Collapsed = collapsed
			Library:ClosePopup()
			arrow.Text = collapsed and '+' or '-'
			reveal.Set(not collapsed)
		end
		function box:SetVisible(visible) outer.Visible = visible end
		Connect(title.MouseButton1Click, function() box:SetCollapsed(not box.Collapsed) end)
		Connect(title.MouseEnter, function() Tween(title, { TextColor3 = Palette.accent }, 0.12) end)
		Connect(title.MouseLeave, function() Tween(title, { TextColor3 = Palette.text }, 0.12) end)
		tab.Groupboxes[name] = box
		return box
	end
	function Tab:AddLeftGroupbox(name) return newGroupbox(self, 'Left', name) end
	function Tab:AddRightGroupbox(name) return newGroupbox(self, 'Right', name) end
	function Tab:AddGroupbox(info)
		info = info or {}
		return newGroupbox(self, info.Side == 2 and 'Right' or 'Left', info.Name or 'Groupbox')
	end

	--// tabbox: one panel with sub tabs \\--
	local function newTabbox(tab, side, name)
		local column = side == 'Left' and tab.Left or tab.Right
		local outer, inner = Panel(column, { 'a', 'c', 'e' }, { Size = dim2(1, 0, 0, 0), Auto = true })
		outer.LayoutOrder = #column:GetChildren()
		New('UIListLayout', { SortOrder = Enum.SortOrder.LayoutOrder, Parent = inner })
		local strip = New('Frame', { BackgroundTransparency = 1, Size = dim2(1, 0, 0, 22), LayoutOrder = 0, Parent = inner })
		New('UIListLayout', { FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder, Parent = strip })
		local body = New('Frame', { BackgroundTransparency = 1, Size = dim2(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = inner })
		local box = setmetatable({ Tab = tab, Library = Library, Name = name, Side = side, Holder = outer, Strip = strip, Body = body, Tabs = {}, Type = 'Tabbox' }, Tabbox)
		function box:SetVisible(visible) outer.Visible = visible end
		tab.Tabboxes[name or (#tab.Tabboxes + 1)] = box
		return box
	end
	function Tab:AddLeftTabbox(name) return newTabbox(self, 'Left', name) end
	function Tab:AddRightTabbox(name) return newTabbox(self, 'Right', name) end

	function Tabbox:AddTab(name)
		local parentBox = self
		local page = New('Frame', { BackgroundTransparency = 1, Size = dim2(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Visible = false, Parent = self.Body })
		New('UIListLayout', { Padding = dim(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = page })
		New('UIPadding', { PaddingTop = dim(0, 8), PaddingBottom = dim(0, 8), PaddingLeft = dim(0, 8), PaddingRight = dim(0, 8), Parent = page })
		local button = New('TextButton', {
			Text = tostring(name):lower(), AutoButtonColor = false, BackgroundTransparency = 1, Size = dim2(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
			TextSize = 12, LayoutOrder = #self.Tabs + 1, Parent = self.Strip,
		}, { TextColor3 = 'dim' })
		New('UIPadding', { PaddingLeft = dim(0, 10), PaddingRight = dim(0, 10), Parent = button })
		local bar = New('Frame', { AnchorPoint = vec2(0, 1), Position = dim2(0, 0, 1, 0), Size = dim2(1, 0, 0, 2), Visible = false, ZIndex = 3, Parent = button }, { BackgroundColor3 = 'accent' })
		local sub = setmetatable({ Tab = self.Tab, Library = Library, Name = name, Container = page, Elements = {}, Page = page, Button = button, Bar = bar, Type = 'TabboxTab', Tabbox = parentBox }, Container)
		sub.Root = sub
		function sub:Show()
			local previous = parentBox.Active
			if previous == sub then return end
			if previous then
				previous.Page.Visible = false
				previous.Bar.Visible = false
				ThemeSet(previous.Button, 'TextColor3', 'dim')
			end
			parentBox.Active = sub
			page.Visible = true
			bar.Visible = true
			ThemeSet(button, 'TextColor3', 'text')
			Library:ClosePopup()
		end
		function sub:SetVisible(visible) button.Visible = visible end
		Connect(button.MouseButton1Click, function() sub:Show() end)
		table.insert(self.Tabs, sub)
		if not self.Active then sub:Show() end
		return sub
	end

	--// dependency box: its children show only while every condition holds \\--
	function Container:AddDependencyBox()
		local reveal = Reveal(self.Container, self:NextOrder())
		local box = setmetatable({
			Tab = self.Tab, Library = Library, Container = reveal.Content, Holder = reveal.Wrapper, Elements = {}, Dependencies = {}, Type = 'DependencyBox', Reveal = reveal,
		}, Container)
		reveal.Set(false, true)
		function box:SetupDependencies(dependencies)
			box.Dependencies = dependencies or {}
			box:Update(true)
		end
		function box:Update(instant)
			local show = #box.Dependencies > 0
			for _, dependency in ipairs(box.Dependencies) do
				local object, wanted = dependency[1], dependency[2]
				if object == nil then
					show = false
					break
				end
				local value = object.Value
				local matches
				if object.Type == 'Dropdown' and object.Multi then
					matches = type(value) == 'table' and value[wanted] == true
				else
					matches = value == wanted
				end
				if not matches then
					show = false
					break
				end
			end
			reveal.Set(show, instant)
		end
		box.Root, box.Name = self.Root or self, (self.Root or self).Name
		table.insert(self.Elements, box)
		table.insert(Library.DependencyBoxes, box)
		return box
	end

	function Library:UpdateDependencyBoxes()
		for index = #Library.DependencyBoxes, 1, -1 do
			local box = Library.DependencyBoxes[index]
			if box.Holder and box.Holder.Parent then
				box:Update(false)
			else
				table.remove(Library.DependencyBoxes, index)
			end
		end
	end
end

-- ==== 40_elements.lua ====
-- ZkxVader elements (1/2): tooltip, label, divider, toggle, button (+sub buttons), slider, input.
-- Every element keeps Obsidian's object contract: Type, Value, SetValue, OnChanged/Changed, Callback, RunChanged, SetText, SetVisible, SetDisabled, Addons.
do
	local Container = Classes.Container
	local Addons = {}
	Classes.Addons = Addons
	local function noop() end

	local Templates = {
		Toggle = { Text = 'Toggle', Default = false, Callback = noop, Changed = noop, Risky = false, Disabled = false, Visible = true },
		Input = {
			Text = 'Input', Default = '', Finished = false, Numeric = false, ClearTextOnFocus = true, ClearTextOnBlur = false, Placeholder = '', AllowEmpty = true,
			EmptyReset = '---', Callback = noop, Changed = noop, Disabled = false, Visible = true,
		},
		Slider = {
			Text = 'Slider', Default = 0, Min = 0, Max = 100, Rounding = 0, Prefix = '', Suffix = '', Callback = noop, Changed = noop, Disabled = false, Visible = true,
			AllowRightClickInput = true,
		},
		Dropdown = { Values = {}, DisabledValues = {}, Multi = false, MaxVisibleDropdownItems = 8, Callback = noop, Changed = noop, Disabled = false, Visible = true },
		KeyPicker = {
			Text = 'KeyPicker', Default = 'None', DefaultModifiers = {}, Blacklisted = {}, BlacklistedModifiers = {}, Whitelisted = {}, WhitelistedModifiers = {},
			Mode = 'Toggle', Modes = { 'Always', 'Toggle', 'Hold' }, SyncToggleState = false, Callback = noop, ChangedCallback = noop, Changed = noop, Clicked = noop,
		},
		ColorPicker = { Default = Color3.new(1, 1, 1), Callback = noop, Changed = noop },
	}
	Library.Templates = Templates
	local function Validate(info, template)
		local out = {}
		for key, value in pairs(template) do out[key] = value end
		if type(info) == 'table' then
			for key, value in pairs(info) do out[key] = value end
		end
		return out
	end
	Library.Validate = function(_, info, template) return Validate(info, template) end

	--// tooltip: one shared panel, shown after a short hover \\--
	local tooltipFrame, tooltipLabel
	local tooltipToken = 0
	local function showTooltip(text)
		if not tooltipFrame then
			tooltipFrame = Panel(Library.Overlay, { 'a', 'b', 'e' }, { Size = dim2(0, 0, 0, 0), Auto = true })
			tooltipFrame.AutomaticSize = Enum.AutomaticSize.XY
			tooltipFrame.ZIndex = 90
			tooltipFrame.Visible = false
			tooltipFrame.Name = 'Tooltip'
			local inner = tooltipFrame:FindFirstChildWhichIsA('Frame', true)
			while inner and inner:FindFirstChildWhichIsA('Frame') do inner = inner:FindFirstChildWhichIsA('Frame') end
			inner.AutomaticSize = Enum.AutomaticSize.XY
			tooltipLabel = New('TextLabel', {
				Text = '', BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.XY, Size = dim2(0, 0, 0, 0), TextSize = 12, ZIndex = 91, TextWrapped = false, Parent = inner,
			})
			New('UIPadding', { PaddingLeft = dim(0, 6), PaddingRight = dim(0, 6), PaddingTop = dim(0, 3), PaddingBottom = dim(0, 4), Parent = inner })
		end
		tooltipLabel.Text = text
		tooltipFrame.Visible = true
	end
	local function hideTooltip()
		tooltipToken += 1
		if tooltipFrame then tooltipFrame.Visible = false end
	end
	Library.HideTooltip = hideTooltip
	Connect(RunService.RenderStepped, function()
		if tooltipFrame and tooltipFrame.Visible then
			local mouse = UserInputService:GetMouseLocation() / Library.GetScale()
			local size = tooltipFrame.AbsoluteSize / Library.GetScale()
			local view = Library.Main.AbsoluteSize / Library.GetScale()
			tooltipFrame.Position = dim2(0, clamp(mouse.X + 14, 0, max(0, view.X - size.X - 4)), 0, clamp(mouse.Y + 16, 0, max(0, view.Y - size.Y - 4)))
		end
	end)

	function Library:AddTooltip(info, disabledInfo, hover)
		local tooltip = { Disabled = false, Info = info, DisabledInfo = disabledInfo }
		if typeof(hover) ~= 'Instance' then return tooltip end
		local function text() return tooltip.Disabled and (tooltip.DisabledInfo or tooltip.Info) or tooltip.Info end
		Connect(hover.MouseEnter, function()
			local current = text()
			if type(current) ~= 'string' or current == '' then return end
			tooltipToken += 1
			local mine = tooltipToken
			task.delay(0.45, function()
				if mine == tooltipToken and not Library.Popup and Library.Toggled and hover.Parent and IsMouseOver(hover) then showTooltip(current) end
			end)
		end)
		Connect(hover.MouseLeave, hideTooltip)
		function tooltip:Destroy() end
		return tooltip
	end
	local function attachTooltip(object, hover)
		if type(object.Tooltip) == 'string' or type(object.DisabledTooltip) == 'string' then
			object.TooltipTable = Library:AddTooltip(object.Tooltip, object.DisabledTooltip, hover)
			object.TooltipTable.Disabled = object.Disabled == true
		end
	end

	--// shared row pieces \\--
	local function newRow(owner, height)
		return New('Frame', { BackgroundTransparency = 1, Size = dim2(1, 0, 0, height), LayoutOrder = owner:NextOrder(), Parent = owner.Container })
	end
	local function newRightHolder(row)
		local holder = New('Frame', { BackgroundTransparency = 1, AnchorPoint = vec2(1, 0), Position = dim2(1, 0, 0, 0), Size = dim2(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 3, Parent = row })
		New('UIListLayout', { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = dim(0, 5), SortOrder = Enum.SortOrder.LayoutOrder, Parent = holder })
		return holder
	end
	local function register(kind, idx, object)
		object.Idx = idx
		if idx ~= nil then Library[kind][idx] = object end
	end
	local function runChanged(object)
		Library:SafeCallback(object.Callback, object.Value)
		Library:SafeCallback(object.Changed, object.Value)
	end
	local function destroyable(owner, object, row, registry, idx)
		function object:Destroy()
			object.Destroyed = true
			if row then row:Destroy() end
			for index = #(object.Addons or {}), 1, -1 do
				local addon = table.remove(object.Addons, index)
				if addon and addon.Destroy then addon:Destroy() end
			end
			if registry and idx ~= nil and Library[registry][idx] == object then Library[registry][idx] = nil end
			local at = table.find(owner.Elements, object)
			if at then table.remove(owner.Elements, at) end
		end
	end

	--// label \\--
	function Container:AddLabel(...)
		local first, second = select(1, ...), select(2, ...)
		local data = {}
		if type(first) == 'table' or type(second) == 'table' then
			local params = type(first) == 'table' and first or second
			data.Text, data.DoesWrap, data.Size = params.Text or '', params.DoesWrap or params.Wrap or false, params.Size or Library.TextSize
			data.Visible = params.Visible ~= false
			data.Idx = type(second) == 'table' and first or nil
		else
			data.Text, data.DoesWrap, data.Size, data.Visible, data.Idx = first or '', second or false, Library.TextSize, true, select(3, ...)
		end
		local label = { Text = data.Text, DoesWrap = data.DoesWrap, Addons = {}, Visible = data.Visible, Type = 'Label', Library = Library }
		local row = New('Frame', { BackgroundTransparency = 1, Size = dim2(1, 0, 0, 14), AutomaticSize = data.DoesWrap and Enum.AutomaticSize.Y or Enum.AutomaticSize.None, LayoutOrder = self:NextOrder(), Visible = data.Visible, Parent = self.Container })
		local text = New('TextLabel', {
			Text = data.Text, BackgroundTransparency = 1, Size = data.DoesWrap and dim2(1, 0, 0, 0) or dim2(1, 0, 1, 0), AutomaticSize = data.DoesWrap and Enum.AutomaticSize.Y or Enum.AutomaticSize.None,
			TextSize = data.Size, TextWrapped = data.DoesWrap, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, RichText = true, Parent = row,
		})
		label.TextLabel, label.Holder, label.Container = text, row, self.Container
		label.RightHolder = (not data.DoesWrap) and newRightHolder(row) or nil
		function label:SetText(value)
			label.Text = tostring(value)
			text.Text = label.Text
		end
		function label:SetVisible(visible)
			label.Visible = visible
			row.Visible = visible
		end
		destroyable(self, label, row, 'Labels', data.Idx)
		if not data.DoesWrap then setmetatable(label, { __index = Addons }) end
		table.insert(self.Elements, label)
		if data.Idx ~= nil then Library.Labels[data.Idx] = label else table.insert(Library.Labels, label) end
		return label
	end

	--// divider \\--
	function Container:AddDivider(...)
		local params = select(1, ...)
		local text, top, bottom = nil, 0, 0
		if type(params) == 'table' then
			text, top, bottom = params.Text, params.MarginTop or params.Margin or 0, params.MarginBottom or params.Margin or 0
		elseif type(params) == 'string' then
			text = params
		end
		local divider = { Type = 'Divider', Visible = true }
		local row = New('Frame', { BackgroundTransparency = 1, Size = dim2(1, 0, 0, 10 + top + bottom), LayoutOrder = self:NextOrder(), Parent = self.Container })
		if text and text ~= '' then
			local width = TextWidth(text, 12) + 14
			New('Frame', { AnchorPoint = vec2(0, 0.5), Position = dim2(0, 0, 0.5, (top - bottom) / 2), Size = dim2(0.5, -width / 2, 0, 1), Parent = row }, { BackgroundColor3 = 'b' })
			New('Frame', { AnchorPoint = vec2(1, 0.5), Position = dim2(1, 0, 0.5, (top - bottom) / 2), Size = dim2(0.5, -width / 2, 0, 1), Parent = row }, { BackgroundColor3 = 'b' })
			New('TextLabel', { Text = text, BackgroundTransparency = 1, AnchorPoint = vec2(0.5, 0.5), Position = dim2(0.5, 0, 0.5, (top - bottom) / 2), Size = dim2(0, width, 0, 12), TextSize = 12, Parent = row }, { TextColor3 = 'dim' })
		else
			New('Frame', { AnchorPoint = vec2(0, 0.5), Position = dim2(0, 0, 0.5, (top - bottom) / 2), Size = dim2(1, 0, 0, 1), Parent = row }, { BackgroundColor3 = 'b' })
		end
		function divider:SetVisible(visible) row.Visible = visible end
		function divider:Destroy() row:Destroy() end
		return divider
	end
	function Container:AddBlank(height)
		New('Frame', { BackgroundTransparency = 1, Size = dim2(1, 0, 0, height or 8), LayoutOrder = self:NextOrder(), Parent = self.Container })
	end

	--// toggle (a Vaderhaxx checkbox) \\--
	function Container:AddToggle(idx, info)
		info = Validate(info, Templates.Toggle)
		local toggle = {
			Text = info.Text, Value = info.Default == true, Tooltip = info.Tooltip, DisabledTooltip = info.DisabledTooltip, Callback = info.Callback, Changed = info.Changed,
			Risky = info.Risky, Disabled = info.Disabled, Visible = info.Visible, Addons = {}, AnyKeyPickerPicking = false, Variant = 'Checkbox', Type = 'Toggle', Library = Library,
		}
		local row = New('TextButton', { Text = '', AutoButtonColor = false, BackgroundTransparency = 1, Size = dim2(1, 0, 0, 16), LayoutOrder = self:NextOrder(), Visible = toggle.Visible, Active = not toggle.Disabled, Parent = self.Container })
		local box, fill = Panel(row, { 'd', 'f' }, { Size = UDim2.fromOffset(11, 11), Position = dim2(0, 0, 0.5, 0), AnchorPoint = vec2(0, 0.5) })
		local label = New('TextLabel', { Text = toggle.Text, BackgroundTransparency = 1, Position = dim2(0, 19, 0, 0), Size = dim2(1, -60, 1, 0), TextSize = Library.TextSize, TextXAlignment = Enum.TextXAlignment.Left, RichText = true, Parent = row })
		local right = newRightHolder(row)
		toggle.Holder, toggle.TextLabel, toggle.Container, toggle.RightHolder = row, label, self.Container, right
		attachTooltip(toggle, row)

		local hovering = false
		local function labelKey()
			if toggle.Disabled then return 'dim' end
			if toggle.Risky and toggle.Value then return 'risky' end
			return (hovering and 'accent') or 'text'
		end
		function toggle:Display(animate)
			if Library.Unloaded then return end
			local fillKey = toggle.Value and (toggle.Risky and 'risky' or 'accent') or 'f'
			Library.Registry[fill] = Library.Registry[fill] or {}
			Library.Registry[fill].BackgroundColor3 = fillKey
			Library.Registry[label] = Library.Registry[label] or {}
			Library.Registry[label].TextColor3 = labelKey()
			if animate ~= false and Animating() then
				Tween(fill, { BackgroundColor3 = Palette[fillKey] }, 0.12)
				Tween(label, { TextColor3 = Palette[labelKey()] }, 0.1)
				if toggle.Value then
					box.Size = UDim2.fromOffset(13, 13)
					Tween(box, { Size = UDim2.fromOffset(11, 11) }, 0.18, Enum.EasingStyle.Back)
				end
			else
				fill.BackgroundColor3, label.TextColor3 = Palette[fillKey], Palette[labelKey()]
			end
			label.TextTransparency = toggle.Disabled and 0.5 or 0
			box.BackgroundTransparency = toggle.Disabled and 0.6 or 0
		end
		function toggle:OnChanged(callback) toggle.Changed = callback end
		function toggle:RunChanged() runChanged(toggle) end
		function toggle:SetValue(value)
			if toggle.Disabled then return end
			toggle.Value = value == true
			toggle:Display()
			for _, addon in ipairs(toggle.Addons) do
				if addon.Type == 'KeyPicker' and (addon.SyncToggleState or addon.Mode == 'Toggle') then
					addon.Toggled = toggle.Value
					addon:Update()
				end
			end
			Library:UpdateDependencyBoxes()
			if not toggle.AnyKeyPickerPicking then toggle:RunChanged() end
			if toggle.Risky and toggle.Value and Animating() then FX.Glitch(label, 0.18) end
		end
		function toggle:SetDisabled(disabled)
			toggle.Disabled = disabled
			row.Active = not disabled
			if toggle.TooltipTable then toggle.TooltipTable.Disabled = disabled end
			for _, addon in ipairs(toggle.Addons) do
				if addon.Type == 'KeyPicker' then addon:Update() end
			end
			toggle:Display(false)
		end
		function toggle:SetVisible(visible)
			toggle.Visible = visible
			row.Visible = visible
			for _, addon in ipairs(toggle.Addons) do
				if addon.Type == 'KeyPicker' then addon:Update() elseif addon.Refresh then addon:Refresh() end
			end
		end
		function toggle:SetText(text)
			toggle.Text = text
			label.Text = text
		end
		Connect(row.MouseButton1Click, function()
			if toggle.Disabled then return end
			toggle:SetValue(not toggle.Value)
		end)
		Connect(row.MouseEnter, function()
			hovering = true
			if not toggle.Disabled then Tween(label, { TextColor3 = Palette[labelKey()] }, 0.08) end
		end)
		Connect(row.MouseLeave, function()
			hovering = false
			Tween(label, { TextColor3 = Palette[labelKey()] }, 0.1)
		end)
		toggle:Display(false)
		toggle.Default = toggle.Value
		destroyable(self, toggle, row, 'Toggles', idx)
		setmetatable(toggle, { __index = Addons })
		table.insert(self.Elements, toggle)
		register('Toggles', idx, toggle)
		return toggle
	end
	Container.AddCheckbox = Container.AddToggle

	--// button (+ sub buttons in the same row) \\--
	local function buttonInfo(...)
		local first, second = select(1, ...), select(2, ...)
		local info = {}
		if type(first) == 'table' or type(second) == 'table' then
			local params = type(first) == 'table' and first or second
			info.Text, info.Func = params.Text or '', params.Func or params.Callback or noop
			info.DoubleClick, info.Tooltip, info.DisabledTooltip = params.DoubleClick, params.Tooltip, params.DisabledTooltip
			info.Risky, info.Disabled, info.Visible = params.Risky or false, params.Disabled or false, params.Visible ~= false
			info.Idx = type(second) == 'table' and first or nil
		else
			info.Text, info.Func, info.Idx = first or '', second or noop, select(3, ...)
			info.DoubleClick, info.Risky, info.Disabled, info.Visible = false, false, false, true
		end
		return info
	end

	local function makeButton(owner, holder, info, parentButton)
		local button = {
			Text = info.Text, Func = info.Func, DoubleClick = info.DoubleClick, Tooltip = info.Tooltip, DisabledTooltip = info.DisabledTooltip, Risky = info.Risky,
			Disabled = info.Disabled, Visible = info.Visible, Addons = {}, Type = parentButton and 'SubButton' or 'Button', Library = Library,
		}
		local outer, inner = Panel(holder, { 'a', 'c' }, { Size = dim2(1, 0, 1, 0) })
		outer.LayoutOrder = #holder:GetChildren()
		local face = New('TextButton', { Text = button.Text, AutoButtonColor = false, BackgroundTransparency = 1, Size = dim2(1, 0, 1, 0), TextSize = Library.TextSize, RichText = true, Active = not button.Disabled, Parent = inner })
		button.Base, button.Holder, button.TextLabel = face, outer, face
		local armed = false
		attachTooltip(button, face)
		local function baseKey() return button.Risky and 'risky' or 'text' end
		function button:UpdateColors()
			face.TextColor3 = button.Disabled and Palette.dim or Palette[baseKey()]
			face.TextTransparency = button.Disabled and 0.4 or 0
		end
		function button:SetText(text)
			button.Text = text
			face.Text = text
		end
		function button:SetDisabled(disabled)
			button.Disabled = disabled
			face.Active = not disabled
			if button.TooltipTable then button.TooltipTable.Disabled = disabled end
			button:UpdateColors()
		end
		function button:SetVisible(visible)
			button.Visible = visible
			outer.Visible = visible
		end
		function button:Destroy()
			button.Destroyed = true
			outer:Destroy()
		end
		local function fire()
			if button.Disabled then return end
			Library:SafeCallback(button.Func)
			Tween(inner, { BackgroundColor3 = Palette.accent }, 0.04)
			task.delay(0.06, function() if inner.Parent then Tween(inner, { BackgroundColor3 = Palette.c }, 0.25) end end)
		end
		Connect(face.MouseButton1Click, function()
			if button.Disabled then return end
			if button.DoubleClick then
				if armed then
					armed = false
					face.Text = button.Text
					fire()
				else
					armed = true
					face.Text = 'click again'
					face.TextColor3 = Palette.accent
					task.delay(2, function()
						if armed and face.Parent then
							armed = false
							face.Text = button.Text
							button:UpdateColors()
						end
					end)
				end
			else
				fire()
			end
		end)
		Connect(face.MouseEnter, function() if not button.Disabled then Tween(inner, { BackgroundColor3 = Palette.g }, 0.1) end end)
		Connect(face.MouseLeave, function() Tween(inner, { BackgroundColor3 = Palette.c }, 0.15) end)
		button:UpdateColors()
		outer.Visible = button.Visible
		return button
	end

	function Container:AddButton(...)
		local info = buttonInfo(...)
		local row = New('Frame', { BackgroundTransparency = 1, Size = dim2(1, 0, 0, 20), LayoutOrder = self:NextOrder(), Parent = self.Container })
		New('UIListLayout', { FillDirection = Enum.FillDirection.Horizontal, HorizontalFlex = Enum.UIFlexAlignment.Fill, Padding = dim(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = row })
		local button = makeButton(self, row, info, nil)
		button.Row, button.Container = row, self.Container
		function button:AddButton(...)
			local sub = makeButton(self, row, buttonInfo(...), button)
			table.insert(self.Elements or {}, sub)
			return sub
		end
		setmetatable(button, { __index = Addons })
		table.insert(self.Elements, button)
		if info.Idx ~= nil then Library.Buttons[info.Idx] = button else table.insert(Library.Buttons, button) end
		local base = button.Destroy
		function button:Destroy()
			base(self)
			row:Destroy()
		end
		return button
	end

	--// slider \\--
	function Container:AddSlider(idx, info)
		info = Validate(info, Templates.Slider)
		local slider = {
			Text = info.Text, Value = info.Default, Min = info.Min, Max = info.Max, Prefix = info.Prefix, Suffix = info.Suffix, Compact = info.Compact, Rounding = info.Rounding,
			HideMax = info.HideMax, Tooltip = info.Tooltip, DisabledTooltip = info.DisabledTooltip, Callback = info.Callback, Changed = info.Changed, Disabled = info.Disabled,
			Visible = info.Visible, AllowRightClickInput = info.AllowRightClickInput, Type = 'Slider', Library = Library,
		}
		local row = New('Frame', { BackgroundTransparency = 1, Size = dim2(1, 0, 0, info.Compact and 20 or 32), LayoutOrder = self:NextOrder(), Visible = slider.Visible, Parent = self.Container })
		local title = (not info.Compact) and New('TextLabel', { Text = slider.Text or '', BackgroundTransparency = 1, Size = dim2(0.6, 0, 0, 14), TextSize = Library.TextSize, TextXAlignment = Enum.TextXAlignment.Left, RichText = true, Parent = row }) or nil
		local readout = New('TextLabel', {
			Text = '', BackgroundTransparency = 1, AnchorPoint = vec2(1, 0), Position = dim2(1, 0, 0, 0), Size = dim2(0.5, 0, 0, 14), TextSize = Library.TextSize, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3, Parent = row,
		}, { TextColor3 = 'dim' })
		local barY, barHeight = info.Compact and 0 or 17, info.Compact and 20 or 12
		local bar = New('TextButton', { Text = '', AutoButtonColor = false, BackgroundTransparency = 1, Position = dim2(0, 0, 0, barY), Size = dim2(1, 0, 0, barHeight), Active = true, Parent = row })
		local outline, track = Panel(bar, { 'd', 'b' }, { Size = dim2(1, 0, 1, 0) })
		outline.Name = 'Track'
		local fillFrame = New('Frame', { Size = dim2(0, 0, 1, 0), ZIndex = 2, Parent = track }, { BackgroundColor3 = 'accent' })
		if info.Compact then
			readout.AnchorPoint, readout.Position, readout.Size, readout.TextXAlignment = vec2(0.5, 0.5), dim2(0.5, 0, 0.5, 0), dim2(1, 0, 1, 0), Enum.TextXAlignment.Center
			readout.ZIndex = 5
			Library.Registry[readout] = { TextColor3 = 'text' }
			readout.TextColor3 = Palette.text
			readout.Parent = bar
		end
		slider.Holder, slider.Bar, slider.Fill, slider.Container = row, bar, fillFrame, self.Container
		attachTooltip(slider, bar)

		local function formatNumber(value)
			if slider.Rounding and slider.Rounding > 0 then
				local text = string.format('%.' .. slider.Rounding .. 'f', value)
				return (text:gsub('(%..-)0+$', '%1'):gsub('%.$', ''))
			end
			return tostring(value)
		end
		function slider:Display()
			if Library.Unloaded then return end
			local custom = info.FormatDisplayValue and info.FormatDisplayValue(slider, slider.Value)
			if custom then
				readout.Text = tostring(custom)
			elseif info.Compact then
				readout.Text = string.format('%s: %s%s%s', slider.Text or '', slider.Prefix, formatNumber(slider.Value), slider.Suffix)
			elseif info.HideMax then
				readout.Text = string.format('%s%s%s', slider.Prefix, formatNumber(slider.Value), slider.Suffix)
			else
				readout.Text = string.format('%s%s%s/%s%s%s', slider.Prefix, formatNumber(slider.Value), slider.Suffix, slider.Prefix, formatNumber(slider.Max), slider.Suffix)
			end
			local alpha = slider.Max ~= slider.Min and clamp((slider.Value - slider.Min) / (slider.Max - slider.Min), 0, 1) or 0
			if Animating() and fillFrame.AbsoluteSize.X > 0 then
				Tween(fillFrame, { Size = dim2(alpha, 0, 1, 0) }, 0.08, Enum.EasingStyle.Quad)
			else
				fillFrame.Size = dim2(alpha, 0, 1, 0)
			end
			readout.TextTransparency, fillFrame.BackgroundTransparency = slider.Disabled and 0.5 or 0, slider.Disabled and 0.6 or 0
			if title then title.TextTransparency = slider.Disabled and 0.5 or 0 end
		end
		function slider:OnChanged(callback) slider.Changed = callback end
		function slider:RunChanged() runChanged(slider) end
		function slider:SetValue(raw)
			if slider.Disabled then return end
			local number = tonumber(raw)
			if not number or number == slider.Value then return end
			slider.Value = clamp(number, slider.Min, slider.Max)
			slider:Display()
			slider:RunChanged()
		end
		function slider:SetMax(value)
			slider.Max = value
			slider:SetValue(clamp(slider.Value, slider.Min, value))
			slider:Display()
		end
		function slider:SetMin(value)
			slider.Min = value
			slider:SetValue(clamp(slider.Value, value, slider.Max))
			slider:Display()
		end
		function slider:SetPrefix(prefix) slider.Prefix = prefix slider:Display() end
		function slider:SetSuffix(suffix) slider.Suffix = suffix slider:Display() end
		function slider:SetText(text)
			slider.Text = text
			if title then title.Text = text end
			slider:Display()
		end
		function slider:SetDisabled(disabled)
			slider.Disabled = disabled
			if slider.TooltipTable then slider.TooltipTable.Disabled = disabled end
			slider:Display()
		end
		function slider:SetVisible(visible)
			slider.Visible = visible
			row.Visible = visible
		end

		-- dragging
		local dragging = false
		local function fromMouse()
			local x = (MouseAbs().X - bar.AbsolutePosition.X) / max(bar.AbsoluteSize.X, 1)
			local value = slider.Min + (slider.Max - slider.Min) * clamp(x, 0, 1)
			value = Round(value, 10 ^ -(slider.Rounding or 0))
			slider:SetValue(clamp(value, slider.Min, slider.Max))
		end
		Connect(bar.InputBegan, function(input)
			if slider.Disabled then return end
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				fromMouse()
			end
		end)
		Connect(UserInputService.InputChanged, function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then fromMouse() end
		end)
		Connect(UserInputService.InputEnded, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
		end)
		-- right click: type a value
		if slider.AllowRightClickInput then
			local typing = New('TextBox', {
				Text = '', BackgroundTransparency = 1, Size = dim2(1, 0, 1, 0), ZIndex = 8, TextSize = Library.TextSize, ClearTextOnFocus = false, Visible = false, Parent = bar,
			})
			Library.Registry[typing] = { TextColor3 = 'accent' }
			typing.TextColor3 = Palette.accent
			Connect(bar.MouseButton2Click, function()
				if slider.Disabled then return end
				typing.Visible, typing.Text = true, tostring(slider.Value)
				typing:CaptureFocus()
			end)
			Connect(typing.FocusLost, function()
				local number = tonumber(typing.Text)
				typing.Visible = false
				if number then
					if slider.Rounding == 0 then number = Round(number, 1) end
					slider:SetValue(clamp(number, slider.Min, slider.Max))
				end
			end)
		end
		slider:Display()
		slider.Default = slider.Value
		destroyable(self, slider, row, 'Options', idx)
		table.insert(self.Elements, slider)
		register('Options', idx, slider)
		return slider
	end

	--// input \\--
	function Container:AddInput(idx, info)
		info = Validate(info, Templates.Input)
		if type(info.VerifyValue) == 'function' and info.Finished ~= true then info.Finished = true end
		local input = {
			Text = info.Text, Value = info.Default, Finished = info.Finished, Numeric = info.Numeric, ClearTextOnFocus = info.ClearTextOnFocus, ClearTextOnBlur = info.ClearTextOnBlur,
			Placeholder = info.Placeholder, AllowEmpty = info.AllowEmpty, EmptyReset = info.EmptyReset, Tooltip = info.Tooltip, DisabledTooltip = info.DisabledTooltip,
			Callback = info.Callback, Changed = info.Changed, VerifyValue = info.VerifyValue, Disabled = info.Disabled, Visible = info.Visible, Type = 'Input', Library = Library,
		}
		local hasLabel = type(info.Text) == 'string' and info.Text ~= ''
		local row = New('Frame', { BackgroundTransparency = 1, Size = dim2(1, 0, 0, hasLabel and 36 or 20), LayoutOrder = self:NextOrder(), Visible = input.Visible, Parent = self.Container })
		local title = New('TextLabel', { Text = input.Text or '', BackgroundTransparency = 1, Size = dim2(1, 0, 0, 14), TextSize = Library.TextSize, TextXAlignment = Enum.TextXAlignment.Left, RichText = true, Visible = hasLabel, Parent = row })
		local frame = New('Frame', { BackgroundTransparency = 1, AnchorPoint = vec2(0, 1), Position = dim2(0, 0, 1, 0), Size = dim2(1, 0, 0, 20), Parent = row })
		local _, field = Panel(frame, { 'd', 'b' }, { Size = dim2(1, 0, 1, 0) })
		local box = New('TextBox', {
			Text = tostring(input.Value or ''), PlaceholderText = input.Placeholder, BackgroundTransparency = 1, Size = dim2(1, -8, 1, 0), Position = dim2(0, 5, 0, 0), TextSize = Library.TextSize,
			TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = input.ClearTextOnFocus, TextEditable = not input.Disabled, Parent = field,
		})
		box.PlaceholderColor3 = Palette.dim
		input.Holder, input.Box, input.Container = row, box, self.Container
		attachTooltip(input, frame)
		local internal = false
		local function accept(text)
			if input.Numeric and text ~= '' and not tonumber(text) and text ~= '-' and text ~= '.' then return false end
			return true
		end
		function input:OnChanged(callback) input.Changed = callback end
		function input:RunChanged() runChanged(input) end
		function input:SetValue(text)
			text = text == nil and '' or tostring(text)
			if input.Numeric and text ~= '' and not tonumber(text) then return end
			if type(input.VerifyValue) == 'function' and text ~= input.EmptyReset and input.VerifyValue(text) ~= true then return end
			input.Value = text
			internal = true
			box.Text = text
			internal = false
			input:RunChanged()
		end
		function input:SetDisabled(disabled)
			input.Disabled = disabled
			box.TextEditable = not disabled
			box.TextTransparency = disabled and 0.5 or 0
			if input.TooltipTable then input.TooltipTable.Disabled = disabled end
		end
		function input:SetVisible(visible)
			input.Visible = visible
			row.Visible = visible
		end
		function input:SetText(text)
			input.Text = text
			title.Text = text or ''
			title.Visible = text ~= nil and text ~= ''
		end
		Connect(box:GetPropertyChangedSignal('Text'), function()
			if internal or input.Finished then return end
			if input.Numeric and not accept(box.Text) then
				internal = true
				box.Text = input.Value or ''
				internal = false
				return
			end
			input:SetValue(box.Text)
		end)
		Connect(box.FocusLost, function()
			if box.Text == '' and not input.AllowEmpty then
				input:SetValue(input.EmptyReset)
			elseif input.Finished then
				input:SetValue(box.Text)
			end
			if input.ClearTextOnBlur then
				internal = true
				box.Text = ''
				internal = false
			end
			Tween(field, { BackgroundColor3 = Palette.b }, 0.15)
		end)
		Connect(box.Focused, function() Tween(field, { BackgroundColor3 = Palette.g }, 0.1) end)
		input.Default = input.Value
		destroyable(self, input, row, 'Options', idx)
		table.insert(self.Elements, input)
		register('Options', idx, input)
		return input
	end
end

-- ==== 41_popups.lua ====
-- ZkxVader elements (2/2): dropdown, colour picker, key picker. Popups live on Library.Overlay (never clipped by a scrolling section).
do
	local Container, Addons = Classes.Container, Classes.Addons
	local Templates, Validate = Library.Templates, function(info, template) return Library.Validate(Library, info, template) end

	--// popup plumbing: one open at a time, closed by an outside click, a tab change or the menu closing \\--
	local function placePopup(frame, anchor, width, height, preferBelow)
		local scale = Library.GetScale()
		-- popups are positioned inside the overlay, whose own AbsolutePosition carries the top-bar inset
		local abs, size = (anchor.AbsolutePosition - Library.Overlay.AbsolutePosition) / scale, anchor.AbsoluteSize / scale
		local view = Library.Main.AbsoluteSize / scale
		local x = clamp(abs.X, 2, max(2, view.X - width - 2))
		local y = abs.Y + size.Y + 2
		if preferBelow == false or y + height > view.Y - 4 then
			local above = abs.Y - height - 2
			if above >= 4 or y + height > view.Y - 4 then y = max(4, above) end
		end
		frame.Position = UDim2.fromOffset(x, y)
		frame.Size = UDim2.fromOffset(width, height)
	end
	local function popupPanel(width, height)
		local frame, inner = Panel(Library.Overlay, { 'a', 'b', 'e' }, { Size = UDim2.fromOffset(width, height), Clip = false })
		frame.ZIndex = 100
		frame.Active = true
		frame.Visible = false
		return frame, inner
	end
	Connect(UserInputService.InputBegan, function(input)
		local kind = input.UserInputType
		if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.MouseButton2 and kind ~= Enum.UserInputType.Touch then return end
		local popup = Library.Popup
		if popup and popup.Frame and popup.Frame.Visible and not IsMouseOver(popup.Frame) and not (popup.Anchor and IsMouseOver(popup.Anchor)) then
			Library:ClosePopup()
		end
	end)
	Library.OnToggled = function(open) if not open then Library:ClosePopup() end end

	--// dropdown \\--
	local function playersList(excludeSelf)
		local list = {}
		for _, player in ipairs(Players:GetPlayers()) do
			if not (excludeSelf and player == LocalPlayer) then table.insert(list, player.Name) end
		end
		table.sort(list)
		return list
	end
	local function teamsList()
		local list = {}
		for _, team in ipairs(svc('Teams'):GetTeams()) do table.insert(list, team.Name) end
		table.sort(list)
		return list
	end

	function Container:AddDropdown(idx, info)
		local owner = self
		info = Validate(info, Templates.Dropdown)
		if info.SpecialType == 'Player' then
			info.Values, info.AllowNull = playersList(info.ExcludeLocalPlayer), true
		elseif info.SpecialType == 'Team' then
			info.Values, info.AllowNull = teamsList(), true
		end
		local dropdown = {
			Text = type(info.Text) == 'string' and info.Text or nil, Value = info.Multi and {} or nil, Values = info.Values, DisabledValues = info.DisabledValues, Multi = info.Multi,
			SpecialType = info.SpecialType, ExcludeLocalPlayer = info.ExcludeLocalPlayer, Tooltip = info.Tooltip, DisabledTooltip = info.DisabledTooltip, Callback = info.Callback,
			Changed = info.Changed, Disabled = info.Disabled, Visible = info.Visible, Type = 'Dropdown', Library = Library,
		}
		local hasLabel = dropdown.Text ~= nil
		local row = New('Frame', { BackgroundTransparency = 1, Size = dim2(1, 0, 0, hasLabel and 38 or 22), LayoutOrder = self:NextOrder(), Visible = dropdown.Visible, Parent = self.Container })
		local title = New('TextLabel', { Text = dropdown.Text or '', BackgroundTransparency = 1, Size = dim2(1, 0, 0, 14), TextSize = Library.TextSize, TextXAlignment = Enum.TextXAlignment.Left, RichText = true, Visible = hasLabel, Parent = row })
		local frame = New('Frame', { BackgroundTransparency = 1, AnchorPoint = vec2(0, 1), Position = dim2(0, 0, 1, 0), Size = dim2(1, 0, 0, 20), Parent = row })
		local _, field = Panel(frame, { 'd', 'b' }, { Size = dim2(1, 0, 1, 0) })
		local display = New('TextButton', { Text = '---', AutoButtonColor = false, BackgroundTransparency = 1, Size = dim2(1, -18, 1, 0), Position = dim2(0, 6, 0, 0), TextSize = Library.TextSize, TextXAlignment = Enum.TextXAlignment.Left, Parent = field })
		local arrow = New('TextLabel', { Text = 'v', BackgroundTransparency = 1, AnchorPoint = vec2(1, 0), Position = dim2(1, -5, 0, 0), Size = dim2(0, 10, 1, 0), TextSize = Library.TextSize, Parent = field }, { TextColor3 = 'dim' })
		dropdown.Holder, dropdown.Container = row, self.Container
		local tooltipHost = display
		if type(dropdown.Tooltip) == 'string' or type(dropdown.DisabledTooltip) == 'string' then
			dropdown.TooltipTable = Library:AddTooltip(dropdown.Tooltip, dropdown.DisabledTooltip, tooltipHost)
			dropdown.TooltipTable.Disabled = dropdown.Disabled == true
		end

		-- popup
		local itemHeight = 18
		local popup, popupInner = popupPanel(100, 40)
		local searchBox
		local list = New('ScrollingFrame', {
			BackgroundTransparency = 1, ScrollBarThickness = 2, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = dim2(0, 0, 0, 0), Size = dim2(1, 0, 1, 0), Active = true, ZIndex = 101, Parent = popupInner,
		})
		Library.Theme(list, 'ScrollBarImageColor3', 'accent')
		New('UIListLayout', { SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
		if info.Searchable then
			local searchRow = New('Frame', { BackgroundTransparency = 1, Size = dim2(1, 0, 0, 20), ZIndex = 102, Parent = popupInner })
			local _, searchField = Panel(searchRow, { 'd', 'b' }, { Size = dim2(1, -4, 1, -4), Position = dim2(0, 2, 0, 2) })
			searchBox = New('TextBox', { Text = '', PlaceholderText = 'search', BackgroundTransparency = 1, Size = dim2(1, -8, 1, 0), Position = dim2(0, 4, 0, 0), TextSize = Library.TextSize, TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false, ZIndex = 103, Parent = searchField })
			searchBox.PlaceholderColor3 = Palette.dim
			list.Position, list.Size = dim2(0, 0, 0, 20), dim2(1, 0, 1, -20)
		end
		local buttons = {}
		local isOpen = false

		local function active() return dropdown.Multi and dropdown.Value or (dropdown.Value and { [dropdown.Value] = true } or {}) end
		local function activeCount()
			local count = 0
			for _ in pairs(active()) do count += 1 end
			return count
		end
		function dropdown:GetActiveValues(returnCount)
			local out = {}
			for value in pairs(active()) do table.insert(out, value) end
			return returnCount == true and #out or out
		end
		function dropdown:Display()
			if Library.Unloaded then return end
			local text = ''
			if dropdown.Multi then
				local parts = {}
				for _, value in ipairs(dropdown.Values) do
					if dropdown.Value[value] then table.insert(parts, info.FormatDisplayValue and tostring(info.FormatDisplayValue(value)) or tostring(value)) end
				end
				text = table.concat(parts, ', ')
			else
				text = dropdown.Value and tostring(dropdown.Value) or ''
				if text ~= '' and info.FormatDisplayValue then text = tostring(info.FormatDisplayValue(text)) end
			end
			if #text > 30 then text = text:sub(1, 27) .. '...' end
			display.Text = text == '' and '---' or text
			display.TextColor3 = (text == '' or dropdown.Disabled) and Palette.dim or Palette.text
		end
		local function refreshButtons()
			local chosen = active()
			for _, entry in ipairs(buttons) do
				local selected = chosen[entry.Value] == true
				entry.Selected = selected
				local key = entry.Disabled and 'dim' or (selected and 'accent' or 'text')
				Library.Registry[entry.Button] = { TextColor3 = key }
				entry.Button.TextColor3 = Palette[key]
				entry.Mark.Visible = selected
			end
		end
		local function heightFor(count) return min(max(count, 1), info.MaxVisibleDropdownItems or 8) * itemHeight + 2 + (searchBox and 20 or 0) end
		function dropdown:BuildDropdownList()
			for _, entry in ipairs(buttons) do entry.Holder:Destroy() end
			table.clear(buttons)
			local needle = searchBox and searchBox.Text:lower() or ''
			local shown = 0
			for _, value in ipairs(dropdown.Values) do
				local text = tostring(info.FormatListValue and info.FormatListValue(value) or value)
				if needle == '' or text:lower():find(needle, 1, true) then
					shown += 1
					local disabled = table.find(dropdown.DisabledValues or {}, value) ~= nil
					local holder = New('Frame', { BackgroundTransparency = 1, Size = dim2(1, 0, 0, itemHeight), LayoutOrder = disabled and 1 or 0, ZIndex = 101, Parent = list })
					local mark = New('Frame', { Size = dim2(0, 2, 1, -4), Position = dim2(0, 2, 0, 2), ZIndex = 103, Visible = false, Parent = holder }, { BackgroundColor3 = 'accent' })
					local button = New('TextButton', { Text = text, AutoButtonColor = false, BackgroundTransparency = 1, Size = dim2(1, 0, 1, 0), TextSize = Library.TextSize, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 102, Parent = holder })
					New('UIPadding', { PaddingLeft = dim(0, 8), Parent = button })
					local entry = { Value = value, Button = button, Mark = mark, Holder = holder, Disabled = disabled }
					table.insert(buttons, entry)
					Connect(button.MouseEnter, function() if not disabled then Tween(holder, { BackgroundTransparency = 0.82 }, 0.08) end holder.BackgroundColor3 = Palette.g end)
					Connect(button.MouseLeave, function() Tween(holder, { BackgroundTransparency = 1 }, 0.1) end)
					if not disabled then
						Connect(button.MouseButton1Click, function()
							local selected = active()[value] == true
							local try = not selected
							if activeCount() == 1 and not try and not info.AllowNull then
								-- the last selected value stays selected
							elseif dropdown.Multi then
								dropdown.Value[value] = try and true or nil
							else
								dropdown.Value = try and value or nil
							end
							dropdown:Display()
							refreshButtons()
							Library:UpdateDependencyBoxes()
							dropdown:RunChanged()
							if not dropdown.Multi then Library:ClosePopup() end
						end)
					end
				end
			end
			refreshButtons()
			if isOpen then
				local current = popup.Size
				popup.Size = UDim2.fromOffset(current.X.Offset, heightFor(shown))
			end
			return shown
		end
		function dropdown:RunChanged()
			Library:SafeCallback(dropdown.Callback, dropdown.Value)
			Library:SafeCallback(dropdown.Changed, dropdown.Value)
		end
		function dropdown:OnChanged(callback) dropdown.Changed = callback end
		function dropdown:SetValue(value)
			if dropdown.Multi then
				local map = {}
				for key, on in pairs(value or {}) do
					if type(on) ~= 'boolean' then
						map[on] = true
					elseif on and table.find(dropdown.Values, key) then
						map[key] = true
					end
				end
				dropdown.Value = map
			else
				if table.find(dropdown.Values, value) then
					dropdown.Value = value
				elseif not value then
					dropdown.Value = nil
				end
			end
			dropdown:Display()
			refreshButtons()
			if not dropdown.Disabled then
				Library:UpdateDependencyBoxes()
				dropdown:RunChanged()
			end
		end
		function dropdown:SetValues(values)
			dropdown.Values = values
			dropdown:BuildDropdownList()
			dropdown:Display()
		end
		function dropdown:AddValues(values)
			if type(values) == 'table' then
				for _, value in ipairs(values) do table.insert(dropdown.Values, value) end
			elseif type(values) == 'string' then
				table.insert(dropdown.Values, values)
			else
				return
			end
			dropdown:BuildDropdownList()
		end
		function dropdown:SetDisabledValues(values)
			dropdown.DisabledValues = values
			dropdown:BuildDropdownList()
		end
		function dropdown:AddDisabledValues(values)
			if type(values) == 'table' then
				for _, value in ipairs(values) do table.insert(dropdown.DisabledValues, value) end
			elseif type(values) == 'string' then
				table.insert(dropdown.DisabledValues, values)
			end
			dropdown:BuildDropdownList()
		end
		function dropdown:SetDisabled(disabled)
			dropdown.Disabled = disabled
			if dropdown.TooltipTable then dropdown.TooltipTable.Disabled = disabled end
			Library:ClosePopup()
			dropdown:Display()
			title.TextTransparency = disabled and 0.5 or 0
		end
		function dropdown:SetVisible(visible)
			dropdown.Visible = visible
			row.Visible = visible
		end
		function dropdown:SetText(text)
			dropdown.Text = text
			title.Text = text or ''
			title.Visible = text ~= nil
			row.Size = dim2(1, 0, 0, text and 38 or 22)
		end

		local function close()
			isOpen = false
			arrow.Text = 'v'
			Tween(popup, { Size = UDim2.fromOffset(popup.Size.X.Offset, 0) }, 0.1)
			task.delay(0.11, function()
				if not isOpen then popup.Visible = false end
			end)
			if searchBox then searchBox.Text = '' end
		end
		local handle = { Frame = popup, Anchor = frame, Close = close }
		local function open()
			if dropdown.Disabled then return end
			if info.SpecialType == 'Player' then dropdown.Values = playersList(info.ExcludeLocalPlayer) elseif info.SpecialType == 'Team' then dropdown.Values = teamsList() end
			local shown = dropdown:BuildDropdownList()
			Library:OpenPopup(handle)
			isOpen = true
			arrow.Text = '^'
			local width = frame.AbsoluteSize.X / Library.GetScale()
			local height = heightFor(shown)
			placePopup(popup, frame, width, height, true)
			popup.Visible = true
			if Animating() then
				popup.Size = UDim2.fromOffset(width, 0)
				Tween(popup, { Size = UDim2.fromOffset(width, height) }, 0.14, Enum.EasingStyle.Quint)
			end
			if searchBox then searchBox:CaptureFocus() end
		end
		Connect(display.MouseButton1Click, function()
			if Library.Popup == handle and isOpen then Library:ClosePopup() else open() end
		end)
		dropdown.Open = function() if not (Library.Popup == handle and isOpen) then open() end end
		dropdown.Close = function() Library:ClosePopup() end
		if searchBox then Connect(searchBox:GetPropertyChangedSignal('Text'), function() dropdown:BuildDropdownList() end) end
		Library:OnUnload(function() popup:Destroy() end)

		-- defaults: a value, a list of values, or an index into Values
		local defaults = {}
		if type(info.Default) == 'string' then
			local at = table.find(dropdown.Values, info.Default)
			if at then table.insert(defaults, at) end
		elseif type(info.Default) == 'table' then
			for _, value in pairs(info.Default) do
				local at = table.find(dropdown.Values, value)
				if at then table.insert(defaults, at) end
			end
		elseif info.Default ~= nil and dropdown.Values[info.Default] ~= nil then
			table.insert(defaults, info.Default)
		end
		for _, at in ipairs(defaults) do
			if dropdown.Multi then dropdown.Value[dropdown.Values[at]] = true else
				dropdown.Value = dropdown.Values[at]
				break
			end
		end
		dropdown:Display()
		dropdown:BuildDropdownList()
		dropdown.Default, dropdown.DefaultValues = defaults, dropdown.Values
		if dropdown.Disabled then dropdown:SetDisabled(true) end
		function dropdown:Destroy()
			dropdown.Destroyed = true
			popup:Destroy()
			row:Destroy()
			if Library.Options[idx] == dropdown then Library.Options[idx] = nil end
			local at = table.find(owner.Elements or {}, dropdown)
			if at then table.remove(owner.Elements, at) end
		end
		table.insert(self.Elements, dropdown)
		if idx ~= nil then Library.Options[idx] = dropdown end
		return dropdown
	end

	--// colour picker (addon) \\--
	local HUE_KEYS = {}
	for index = 0, 6 do table.insert(HUE_KEYS, ColorSequenceKeypoint.new(index / 6, hsv(index / 6, 1, 1))) end
	local HUE_SEQUENCE = ColorSequence.new(HUE_KEYS)

	function Addons:AddColorPicker(idx, info)
		info = Validate(info, Templates.ColorPicker)
		local parent = self
		local host = parent.RightHolder
		if not host then return parent end
		local picker = {
			Value = info.Default, Transparency = type(info.Transparency) == 'number' and info.Transparency or 0, Title = info.Title, Callback = info.Callback, Changed = info.Changed,
			Type = 'ColorPicker', Library = Library, HasAlpha = info.Transparency ~= nil and info.Transparency ~= false,
		}
		picker.Hue, picker.Sat, picker.Vib = info.Default:ToHSV()
		local swatchOuter, swatch = Panel(host, { 'a', 'g' }, { Size = UDim2.fromOffset(20, 10) })
		swatchOuter.LayoutOrder = 10 + #parent.Addons
		Library.Registry[swatch] = nil -- the swatch shows the picked colour; the theme registry must not repaint it
		local swatchButton = New('TextButton', { Text = '', AutoButtonColor = false, BackgroundTransparency = 1, Size = dim2(1, 0, 1, 0), ZIndex = 4, Parent = swatch })
		swatch.BackgroundColor3 = picker.Value

		local width, svH = 190, 110
		local popup, inner = popupPanel(width, svH + 76 + (picker.HasAlpha and 16 or 0))
		New('UIPadding', { PaddingTop = dim(0, 6), PaddingLeft = dim(0, 6), PaddingRight = dim(0, 6), PaddingBottom = dim(0, 6), Parent = inner })
		local heading = New('TextLabel', { Text = (picker.Title or 'color'):lower(), BackgroundTransparency = 1, Size = dim2(1, 0, 0, 14), TextSize = Library.TextSize, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 102, Parent = inner }, { TextColor3 = 'dim' })
		local svOuter, svBase = Panel(inner, { 'd' }, { Size = UDim2.fromOffset(width - 12 - 22, svH), Position = dim2(0, 0, 0, 18) })
		svOuter.ZIndex = 101
		local sv = New('TextButton', { Text = '', AutoButtonColor = false, Size = dim2(1, 0, 1, 0), BackgroundColor3 = hsv(picker.Hue, 1, 1), ZIndex = 102, Parent = svBase })
		local white = New('Frame', { Size = dim2(1, 0, 1, 0), BackgroundColor3 = rgb(255, 255, 255), ZIndex = 103, Parent = sv })
		New('UIGradient', { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }), Parent = white })
		local black = New('Frame', { Size = dim2(1, 0, 1, 0), BackgroundColor3 = rgb(0, 0, 0), ZIndex = 104, Parent = sv })
		New('UIGradient', { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }), Parent = black })
		local knob = New('Frame', { Size = UDim2.fromOffset(7, 7), AnchorPoint = vec2(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 106, Parent = sv })
		New('UIStroke', { Color = rgb(255, 255, 255), Thickness = 1, Parent = knob })
		local hueOuter, hueBase = Panel(inner, { 'd' }, { Size = UDim2.fromOffset(16, svH), Position = dim2(1, -16, 0, 18) })
		hueOuter.ZIndex = 101
		local hue = New('TextButton', { Text = '', AutoButtonColor = false, Size = dim2(1, 0, 1, 0), BackgroundColor3 = rgb(255, 255, 255), ZIndex = 102, Parent = hueBase })
		New('UIGradient', { Color = HUE_SEQUENCE, Rotation = 90, Parent = hue })
		local hueMark = New('Frame', { Size = dim2(1, 0, 0, 2), AnchorPoint = vec2(0, 0.5), BackgroundColor3 = rgb(255, 255, 255), ZIndex = 106, Parent = hue })
		local alphaBase, alpha, alphaMark, alphaGradient
		if picker.HasAlpha then
			local alphaOuter
			alphaOuter, alphaBase = Panel(inner, { 'd' }, { Size = UDim2.new(1, 0, 0, 12), Position = dim2(0, 0, 0, 18 + svH + 6) })
			alphaOuter.ZIndex = 101
			alpha = New('TextButton', { Text = '', AutoButtonColor = false, Size = dim2(1, 0, 1, 0), BackgroundColor3 = rgb(255, 255, 255), ZIndex = 102, Parent = alphaBase })
			alphaGradient = New('UIGradient', { Color = ColorSequence.new(picker.Value), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }), Parent = alpha })
			alphaMark = New('Frame', { Size = dim2(0, 2, 1, 0), AnchorPoint = vec2(0.5, 0), BackgroundColor3 = rgb(255, 255, 255), ZIndex = 106, Parent = alpha })
		end
		local hexRow = New('Frame', { BackgroundTransparency = 1, Position = dim2(0, 0, 0, 18 + svH + 6 + (picker.HasAlpha and 18 or 0)), Size = dim2(1, 0, 0, 20), ZIndex = 101, Parent = inner })
		local _, hexField = Panel(hexRow, { 'd', 'b' }, { Size = dim2(1, 0, 1, 0) })
		local hexBox = New('TextBox', { Text = '', PlaceholderText = 'hex', BackgroundTransparency = 1, Size = dim2(1, -8, 1, 0), Position = dim2(0, 5, 0, 0), TextSize = Library.TextSize, TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false, ZIndex = 103, Parent = hexField })
		hexBox.PlaceholderColor3 = Palette.dim

		function picker:Display()
			picker.Value = hsv(picker.Hue, picker.Sat, picker.Vib)
			swatch.BackgroundColor3 = picker.Value
			sv.BackgroundColor3 = hsv(picker.Hue, 1, 1)
			knob.Position = dim2(picker.Sat, 0, 1 - picker.Vib, 0)
			hueMark.Position = dim2(0, 0, picker.Hue, 0)
			if alphaGradient then
				alphaGradient.Color = ColorSequence.new(picker.Value)
				alphaMark.Position = dim2(1 - picker.Transparency, 0, 0, 0)
			end
			if not hexBox:IsFocused() then hexBox.Text = picker.Value:ToHex():upper() end
		end
		function picker:OnChanged(callback) picker.Changed = callback end
		function picker:RunChanged()
			Library:SafeCallback(picker.Callback, picker.Value)
			Library:SafeCallback(picker.Changed, picker.Value)
		end
		-- Obsidian's contract: SetValue takes {h, s, v} or a Color3; the transparency only counts when the picker has alpha
		function picker:SetValue(hsvTable, transparency)
			if typeof(hsvTable) == 'Color3' then
				picker:SetValueRGB(hsvTable, transparency)
				return
			end
			picker.Hue, picker.Sat, picker.Vib = hsvTable[1], hsvTable[2], hsvTable[3]
			picker.Transparency = picker.HasAlpha and (transparency or 0) or 0
			picker:Update()
		end
		function picker:SetValueRGB(color, transparency)
			picker.Hue, picker.Sat, picker.Vib = color:ToHSV()
			picker.Transparency = picker.HasAlpha and (transparency or 0) or 0
			picker:Update()
		end
		function picker:Update()
			picker:Display()
			picker:RunChanged()
		end
		function picker:Refresh() swatchOuter.Visible = parent.Visible ~= false end

		local dragging = nil
		local function drag()
			local mouse = MouseAbs()
			if dragging == 'sv' then
				picker.Sat = clamp((mouse.X - sv.AbsolutePosition.X) / max(sv.AbsoluteSize.X, 1), 0, 1)
				picker.Vib = 1 - clamp((mouse.Y - sv.AbsolutePosition.Y) / max(sv.AbsoluteSize.Y, 1), 0, 1)
			elseif dragging == 'hue' then
				picker.Hue = clamp((mouse.Y - hue.AbsolutePosition.Y) / max(hue.AbsoluteSize.Y, 1), 0, 1)
			elseif dragging == 'alpha' and alpha then
				picker.Transparency = 1 - clamp((mouse.X - alpha.AbsolutePosition.X) / max(alpha.AbsoluteSize.X, 1), 0, 1)
			end
			picker:Display()
			picker:RunChanged()
		end
		for name, target in pairs({ sv = sv, hue = hue, alpha = alpha }) do
			if target then
				Connect(target.InputBegan, function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						dragging = name
						drag()
					end
				end)
			end
		end
		Connect(UserInputService.InputChanged, function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then drag() end
		end)
		Connect(UserInputService.InputEnded, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = nil end
		end)
		Connect(hexBox.FocusLost, function()
			local text = hexBox.Text:gsub('#', '')
			if #text == 6 and text:match('^%x+$') then picker:SetValueRGB(Color3.fromHex(text), picker.Transparency) else picker:Display() end
		end)

		local isOpen = false
		local function close()
			isOpen = false
			popup.Visible = false
		end
		local handle = { Frame = popup, Anchor = swatchOuter, Close = close }
		local function togglePopup()
			if isOpen then
				Library:ClosePopup()
				return
			end
			Library:OpenPopup(handle)
			isOpen = true
			placePopup(popup, swatchOuter, width, popup.Size.Y.Offset, true)
			popup.Visible = true
			picker:Display()
		end
		picker.TogglePopup = togglePopup
		Connect(swatchButton.MouseButton1Click, togglePopup)
		Library:OnUnload(function() popup:Destroy() end)
		picker:Display()
		picker.Default = picker.Value
		function picker:Destroy()
			picker.Destroyed = true
			popup:Destroy()
			swatchOuter:Destroy()
			local at = table.find(parent.Addons, picker)
			if at then table.remove(parent.Addons, at) end
			if Library.Options[idx] == picker then Library.Options[idx] = nil end
		end
		table.insert(parent.Addons, picker)
		if idx ~= nil then Library.Options[idx] = picker end
		return parent
	end

	--// key picker (addon) \\--
	local SPECIAL_KEYS = { MB1 = Enum.UserInputType.MouseButton1, MB2 = Enum.UserInputType.MouseButton2, MB3 = Enum.UserInputType.MouseButton3 }
	local SPECIAL_INPUT = { [Enum.UserInputType.MouseButton1] = 'MB1', [Enum.UserInputType.MouseButton2] = 'MB2', [Enum.UserInputType.MouseButton3] = 'MB3' }
	local MODIFIERS = {
		LAlt = Enum.KeyCode.LeftAlt, RAlt = Enum.KeyCode.RightAlt, LCtrl = Enum.KeyCode.LeftControl, RCtrl = Enum.KeyCode.RightControl,
		LShift = Enum.KeyCode.LeftShift, RShift = Enum.KeyCode.RightShift, Tab = Enum.KeyCode.Tab, CapsLock = Enum.KeyCode.CapsLock,
	}
	local MODIFIER_INPUT = {}
	for name, code in pairs(MODIFIERS) do MODIFIER_INPUT[code] = name end
	local SHORT = {
		LeftShift = 'LShift', RightShift = 'RShift', LeftControl = 'LCtrl', RightControl = 'RCtrl', LeftAlt = 'LAlt', RightAlt = 'RAlt', Backspace = 'BkSp',
		Return = 'Enter', Insert = 'Ins', Delete = 'Del', PageUp = 'PgUp', PageDown = 'PgDn', Backquote = '`', CapsLock = 'Caps',
	}

	Library.KeybindToggles = Library.KeybindToggles or {}
	Library.IsPicking = false

	function Addons:AddKeyPicker(idx, info)
		info = Validate(info, Templates.KeyPicker)
		local parent = self
		local isButton = parent.Type == 'Button' or parent.Type == 'SubButton'
		local host = parent.RightHolder
		if isButton then
			assert(info.Mode == 'Press', "KeyPicker on Buttons can only be applied with the 'Press' mode.")
			host = parent.Row
		end
		if not host then return parent end
		local picker = {
			Text = info.Text, Value = info.Default, Modifiers = info.DefaultModifiers, DisplayValue = info.Default, Blacklisted = info.Blacklisted, BlacklistedModifiers = info.BlacklistedModifiers,
			Whitelisted = info.Whitelisted, WhitelistedModifiers = info.WhitelistedModifiers, Toggled = false, Mode = info.Mode, SyncToggleState = info.SyncToggleState, Callback = info.Callback,
			ChangedCallback = info.ChangedCallback, Changed = info.Changed, Clicked = info.Clicked, Type = 'KeyPicker', Library = Library, Connections = {},
		}
		local modes = info.Modes
		if picker.Mode == 'Press' then
			assert(parent.Type == 'Label' or isButton, "KeyPicker with the mode 'Press' can be only applied on Labels and Buttons.")
			picker.SyncToggleState, modes, info.Mode = false, { 'Press' }, 'Press'
		end
		if picker.SyncToggleState then
			modes = { 'Toggle', 'Hold' }
			if not table.find(modes, info.Mode) then picker.Mode = 'Toggle' end
		end

		-- the checkbox is the source of truth in Toggle mode (pickers that already sync it are left alone)
		local function drivesToggle() return parent.Type == 'Toggle' and picker.Mode == 'Toggle' and not picker.SyncToggleState end
		local function flipToggled()
			if drivesToggle() then picker.Toggled = not parent.Value else picker.Toggled = not picker.Toggled end
		end
		local function mirrorToggled()
			if drivesToggle() and parent.Value ~= picker.Toggled then
				parent:SetValue(picker.Toggled)
				picker.Toggled = parent.Value
			end
		end
		local function activeModifiers()
			local out = {}
			for name, code in pairs(MODIFIERS) do
				if UserInputService:IsKeyDown(code) then table.insert(out, name) end
			end
			return out
		end
		local function modifiersHeld(required)
			if type(required) ~= 'table' or #required == 0 then return true end
			local held = activeModifiers()
			for _, name in ipairs(required) do
				if not table.find(held, name) then return false end
			end
			return true
		end
		local function verifyModifiers(list)
			local out = {}
			if type(list) ~= 'table' then return out end
			for _, name in ipairs(list) do
				if MODIFIERS[name] then table.insert(out, name) end
			end
			return out
		end
		picker.Modifiers = verifyModifiers(picker.Modifiers)

		-- the key button
		local buttonOuter, buttonInner = Panel(host, { 'a', 'c' }, { Size = UDim2.fromOffset(40, 14) })
		buttonOuter.LayoutOrder = 20 + #parent.Addons
		if isButton then
			buttonOuter.Size = UDim2.fromOffset(44, 20)
			buttonOuter.LayoutOrder = 1000
		end
		local keyButton = New('TextButton', { Text = '', AutoButtonColor = false, BackgroundTransparency = 1, Size = dim2(1, 0, 1, 0), TextSize = Library.TextSize, ZIndex = 4, Parent = buttonInner })

		-- row in the keybind list
		local listHolder = New('Frame', { BackgroundTransparency = 1, Size = dim2(1, 0, 0, 14), Visible = not info.NoUI, Parent = Library.KeybindContainer })
		local listLabel = New('TextLabel', { Text = '', BackgroundTransparency = 1, Size = dim2(1, 0, 1, 0), TextSize = Library.TextSize, TextXAlignment = Enum.TextXAlignment.Left, Parent = listHolder }, { TextColor3 = 'dim' })

		-- mode menu (right click)
		local menu, menuInner = popupPanel(70, #modes * 18 + 4)
		New('UIListLayout', { SortOrder = Enum.SortOrder.LayoutOrder, Parent = menuInner })
		local modeButtons = {}
		for index, mode in ipairs(modes) do
			local button = New('TextButton', { Text = mode, AutoButtonColor = false, BackgroundTransparency = 1, Size = dim2(1, 0, 0, 18), LayoutOrder = index, TextSize = Library.TextSize, ZIndex = 102, Parent = menuInner }, { TextColor3 = 'dim' })
			modeButtons[mode] = button
			Connect(button.MouseButton1Click, function()
				picker:SetMode(mode)
				Library:ClosePopup()
			end)
		end
		function picker:SetMode(mode)
			picker.Mode = mode
			for name, button in pairs(modeButtons) do ThemeSet(button, 'TextColor3', name == mode and 'accent' or 'dim') end
			picker:Update()
		end

		local picking = false
		function picker:Display(text)
			if Library.Unloaded then return end
			local shown = text or picker.DisplayValue
			shown = shown:gsub('%a+', function(word) return SHORT[word] or word end)
			if picker.Value == 'None' or picker.Value == 'Unknown' then shown = text or 'none' end
			keyButton.Text = shown
			buttonOuter.Size = UDim2.fromOffset(TextWidth(shown, Library.TextSize) + 12, isButton and 20 or 14)
		end
		function picker:GetState()
			if picker.Mode == 'Always' then return true end
			if picker.Mode == 'Hold' then
				local key = picker.Value
				if key == 'None' or key == 'Unknown' then return false end
				if not modifiersHeld(picker.Modifiers) or picking then return false end
				if SPECIAL_KEYS[key] then
					if Library.Toggled then return false end
					return UserInputService:IsMouseButtonPressed(SPECIAL_KEYS[key]) and not UserInputService:GetFocusedTextBox()
				end
				local ok, code = pcall(function() return Enum.KeyCode[key] end)
				return ok and code ~= nil and UserInputService:IsKeyDown(code) and not UserInputService:GetFocusedTextBox() or false
			end
			return picker.Toggled
		end
		function picker:Update()
			picker:Display()
			if info.NoUI then return end
			if picker.Mode == 'Toggle' and parent.Type == 'Toggle' and parent.Disabled then
				listHolder.Visible = false
				return
			end
			local state = picker:GetState()
			if picker.SyncToggleState and parent.Value ~= state then parent:SetValue(state) end
			listLabel.Text = ('[%s] %s (%s)'):format(picker.DisplayValue, picker.Text, picker.Mode)
			listHolder.Visible = true
			ThemeSet(listLabel, 'TextColor3', state and 'accent' or 'dim')
		end
		function picker:OnChanged(callback) picker.Changed = callback end
		function picker:OnClick(callback) picker.Clicked = callback end
		function picker:DoClick()
			if picking then return end
			if picker.Mode == 'Press' then
				if picker.Toggled and info.WaitForCallback == true then return end
				picker.Toggled = true
			end
			Library:SafeCallback(picker.Callback, picker.Toggled)
			Library:SafeCallback(picker.Clicked, picker.Toggled)
			if isButton then Library:SafeCallback(parent.Func, picker.Toggled) end
			if Library.ToggleKeybind == picker and Library.Toggle then Library:Toggle() end
			if picker.Mode == 'Press' then picker.Toggled = false end
		end
		function picker:RunChanged(valid, code)
			if valid == nil or code == nil then
				valid, code = pcall(function()
					if picker.Value == 'None' then return nil end
					if SPECIAL_KEYS[picker.Value] == nil then return Enum.KeyCode[picker.Value] end
					return SPECIAL_KEYS[picker.Value]
				end)
			end
			local converted = {}
			for _, name in ipairs(picker.Modifiers) do table.insert(converted, MODIFIERS[name]) end
			Library:SafeCallback(picker.ChangedCallback, code, converted)
			Library:SafeCallback(picker.Changed, code, converted)
		end
		function picker:SetValue(data)
			local key, mode, modifiers = data[1], data[2], data[3]
			local valid, code = pcall(function()
				if key == 'None' then
					key = nil
					return nil
				end
				if SPECIAL_KEYS[key] == nil then return Enum.KeyCode[key] end
				return SPECIAL_KEYS[key]
			end)
			if key == nil then
				picker.Value = 'None'
			elseif valid then
				picker.Value = key
			else
				picker.Value = 'Unknown'
			end
			picker.Modifiers = verifyModifiers(type(modifiers) == 'table' and modifiers or picker.Modifiers)
			picker.DisplayValue = #picker.Modifiers > 0 and (table.concat(picker.Modifiers, ' + ') .. ' + ' .. picker.Value) or picker.Value
			if mode and modeButtons[mode] then picker:SetMode(mode) end
			picker:Update()
			picker:RunChanged(valid, code)
		end
		function picker:SetText(text)
			picker.Text = text
			picker:Update()
		end

		local function setPicking(state)
			picking = state
			Library.IsPicking = state
			parent.AnyKeyPickerPicking = state
			picker:Update()
		end
		local function startPicking()
			if picking or Library.IsPicking then return end
			setPicking(true)
			keyButton.Text, buttonOuter.Size = '...', UDim2.fromOffset(28, isButton and 20 or 14)
			local current
			local function valid(input)
				if input.KeyCode == Enum.KeyCode.Escape then return true end
				local isModifier = input.UserInputType == Enum.UserInputType.Keyboard and MODIFIER_INPUT[input.KeyCode] ~= nil
				local name
				if SPECIAL_INPUT[input.UserInputType] then
					name = SPECIAL_INPUT[input.UserInputType]
				elseif input.UserInputType == Enum.UserInputType.Keyboard then
					name = isModifier and MODIFIER_INPUT[input.KeyCode] or input.KeyCode.Name
				end
				if name then
					if isModifier then
						if picker.WhitelistedModifiers and #picker.WhitelistedModifiers > 0 and not table.find(picker.WhitelistedModifiers, name) then return false end
						if picker.BlacklistedModifiers and table.find(picker.BlacklistedModifiers, name) then return false end
					else
						if picker.Whitelisted and #picker.Whitelisted > 0 and not table.find(picker.Whitelisted, name) then return false end
						if picker.Blacklisted and table.find(picker.Blacklisted, name) then return false end
					end
				end
				return true
			end
			while true do
				local input = UserInputService.InputBegan:Wait()
				if UserInputService:GetFocusedTextBox() ~= nil or Library.Unloaded then
					setPicking(false)
					return
				end
				if valid(input) then
					current = input
					break
				end
			end
			local key = 'Unknown'
			if SPECIAL_INPUT[current.UserInputType] then
				key = SPECIAL_INPUT[current.UserInputType]
			elseif current.UserInputType == Enum.UserInputType.Keyboard then
				key = current.KeyCode == Enum.KeyCode.Escape and 'None' or current.KeyCode.Name
			end
			picker.Toggled = parent.Type == 'Toggle' and parent.Value or false
			picker:SetValue({ key, picker.Mode, {} })
			-- Always ignores its key, so a key bound in Always mode would never do anything: binding one to a checkbox switches the picker to Toggle
			if picker.Mode == 'Always' and parent.Type == 'Toggle' and key ~= 'None' and key ~= 'Unknown' and modeButtons.Toggle then
				picker:SetMode('Toggle')
				picker.Toggled = parent.Value
				picker:Update()
				Library:Notify({ Title = picker.Text, Description = picker.DisplayValue .. ' now toggles it. Right-click the key to use Hold or Always instead.', Time = 4 })
			end
			-- a key still reported as held (alt-tab while binding, a lost key-up) must not keep picking mode on forever
			local deadline = os.clock() + 1.5
			repeat
				task.wait()
				local down = false
				if SPECIAL_INPUT[current.UserInputType] then
					down = UserInputService:IsMouseButtonPressed(current.UserInputType)
				elseif current.UserInputType == Enum.UserInputType.Keyboard then
					down = UserInputService:IsKeyDown(current.KeyCode)
				end
			until not down or os.clock() > deadline or Library.Unloaded
			setPicking(false)
		end
		Connect(keyButton.MouseButton1Click, function()
			if picking or Library.IsPicking then return end
			local ok, err = pcall(startPicking)
			if picking then setPicking(false) end
			if not ok then warn('[ZkxVader] KeyPicker: ' .. tostring(err)) end
		end)
		local menuOpen = false
		local menuHandle = { Frame = menu, Anchor = keyButton, Close = function() menuOpen = false menu.Visible = false end }
		local function toggleMenu()
			if menuOpen then
				Library:ClosePopup()
				return
			end
			Library:OpenPopup(menuHandle)
			menuOpen = true
			placePopup(menu, buttonOuter, 70, #modes * 18 + 4, true)
			menu.Visible = true
		end
		picker.ToggleMenu = toggleMenu
		Connect(keyButton.MouseButton2Click, toggleMenu)
		Connect(UserInputService.InputBegan, function(input)
			if Library.Unloaded then return end
			local isMouse = SPECIAL_INPUT[input.UserInputType] ~= nil
			if picker.Mode == 'Always' or picker.Value == 'Unknown' or picker.Value == 'None' or picking or Library.IsPicking or UserInputService:GetFocusedTextBox() or (isMouse and Library.Toggled) then return end
			local holding = modifiersHeld(picker.Modifiers) and (SPECIAL_INPUT[input.UserInputType] == picker.Value or (input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode.Name == picker.Value))
			if picker.Mode == 'Toggle' then
				if holding then
					flipToggled()
					picker:DoClick()
					mirrorToggled()
				end
			elseif picker.Mode == 'Press' then
				if holding then picker:DoClick() end
			end
			picker:Update()
		end)
		Connect(UserInputService.InputEnded, function(input)
			if Library.Unloaded then return end
			local isMouse = SPECIAL_INPUT[input.UserInputType] ~= nil
			if picker.Value == 'Unknown' or picker.Value == 'None' or picking or Library.IsPicking or UserInputService:GetFocusedTextBox() or (isMouse and Library.Toggled) then return end
			picker:Update()
		end)

		picker:SetMode(picker.Mode)
		Library:OnUnload(function() menu:Destroy() end)
		picker.Default, picker.DefaultModifiers = picker.Value, table.clone(picker.Modifiers or {})
		function picker:Destroy()
			picker.Destroyed = true
			menu:Destroy()
			buttonOuter:Destroy()
			listHolder:Destroy()
			local at = table.find(parent.Addons, picker)
			if at then table.remove(parent.Addons, at) end
			if Library.Options[idx] == picker then Library.Options[idx] = nil end
		end
		table.insert(parent.Addons, picker)
		if idx ~= nil then Library.Options[idx] = picker end
		picker:Update()
		return parent
	end
end

-- ==== 42_viewport.lua ====
-- ZkxVader viewport element (the ESP tab's live preview): a ViewportFrame inside a Vaderhaxx panel, Obsidian's Viewport contract.
do
	local Container = Classes.Container

	function Container:AddViewport(idx, info)
		info = Library:Validate(info, { Object = nil, Camera = nil, Clone = true, AutoFocus = true, Interactive = false, Height = 200, Visible = true })
		local owner = self
		local object = info.Object
		if info.Clone and typeof(object) == 'Instance' then
			local wasArchivable = object.Archivable
			object.Archivable = true
			object = object:Clone()
			object.Archivable = wasArchivable
		end
		local viewport = {
			Destroyed = false, Object = object, Camera = info.Camera or Instance.new('Camera'), Interactive = info.Interactive, AutoFocus = info.AutoFocus, Visible = info.Visible,
			Type = 'Viewport', Library = Library,
		}
		assert(typeof(viewport.Object) == 'Instance' and (viewport.Object:IsA('BasePart') or viewport.Object:IsA('Model')), 'Instance must be a BasePart or Model.')
		assert(typeof(viewport.Camera) == 'Instance' and viewport.Camera:IsA('Camera'), 'Camera must be a valid Camera instance.')

		local holder = New('Frame', { BackgroundTransparency = 1, Size = dim2(1, 0, 0, info.Height), LayoutOrder = self:NextOrder(), Visible = viewport.Visible, Parent = self.Container })
		local _, box = Panel(holder, { 'a', 'b', 'd' }, { Size = dim2(1, 0, 1, 0) })
		local frame = New('ViewportFrame', { BackgroundTransparency = 1, Size = dim2(1, 0, 1, 0), CurrentCamera = viewport.Camera, Active = viewport.Interactive, Parent = box })
		viewport.Camera.Parent = frame
		viewport.Object.Parent = frame
		viewport.Holder, viewport.Frame = holder, frame

		local function focus()
			local object = viewport.Object
			local size = object:IsA('BasePart') and object.Size or select(2, object:GetBoundingBox())
			local extent = math.max(size.X, size.Y, size.Z)
			local position = object:GetPivot().Position
			viewport.Camera.CFrame = CFrame.new(position + Vector3.new(0, extent / 2, extent * 2), position)
		end
		if viewport.AutoFocus then focus() end

		-- the interactive orbit (right mouse drag, wheel zoom) of the stock widget
		local dragging, last = false, nil
		Connect(frame.InputBegan, function(input)
			if viewport.Interactive and input.UserInputType == Enum.UserInputType.MouseButton2 then dragging, last = true, input.Position end
		end)
		Connect(UserInputService.InputEnded, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton2 then dragging = false end
		end)
		Connect(UserInputService.InputChanged, function(input)
			if Library.Unloaded or not viewport.Interactive or not dragging or input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
			local delta = input.Position - last
			last = input.Position
			local position = viewport.Object:GetPivot().Position
			local camera = viewport.Camera
			camera.CFrame = CFrame.new(position) * CFrame.fromAxisAngle(Vector3.new(0, 1, 0), -delta.X * 0.01) * CFrame.new(-position) * camera.CFrame
			local pitched = CFrame.new(position) * CFrame.fromAxisAngle(camera.CFrame.RightVector, -delta.Y * 0.01) * CFrame.new(-position) * camera.CFrame
			if pitched.UpVector.Y > 0.1 then camera.CFrame = pitched end
		end)
		Connect(frame.InputChanged, function(input)
			if viewport.Interactive and input.UserInputType == Enum.UserInputType.MouseWheel then
				viewport.Camera.CFrame += viewport.Camera.CFrame.LookVector * (input.Position.Z * 2)
			end
		end)

		function viewport:SetObject(newObject, clone)
			assert(newObject, 'Object cannot be nil.')
			if clone then newObject = newObject:Clone() end
			if viewport.Object then viewport.Object:Destroy() end
			viewport.Object = newObject
			viewport.Object.Parent = frame
		end
		function viewport:SetHeight(height) holder.Size = dim2(1, 0, 0, height) end
		function viewport:Focus() if viewport.Object then focus() end end
		function viewport:SetCamera(camera)
			viewport.Camera = camera
			frame.CurrentCamera = camera
		end
		function viewport:SetInteractive(interactive)
			viewport.Interactive = interactive
			frame.Active = interactive
		end
		function viewport:SetVisible(visible)
			viewport.Visible = visible
			holder.Visible = visible
		end
		function viewport:Destroy()
			viewport.Destroyed = true
			holder:Destroy()
			local at = table.find(owner.Elements, viewport)
			if at then table.remove(owner.Elements, at) end
			if idx ~= nil and Library.Options[idx] == viewport then Library.Options[idx] = nil end
		end
		table.insert(self.Elements, viewport)
		viewport.Idx = idx
		if idx ~= nil then Library.Options[idx] = viewport end
		return viewport
	end
end

-- ==== 43_search.lua ====
-- ZkxVader search: a box in the header; typing lists every matching control of every tab ("tab > box > name"); a click jumps there and flashes the row.
-- (The real rows are never hidden or moved, so searching can not disturb layouts or dependency boxes.)
do
	local Window = Classes.Window

	local function plain(text) return (tostring(text or ''):gsub('<[^>]->', '')) end
	local function walk(container, visit)
		for _, element in ipairs(container.Elements or {}) do
			if element.Type == 'DependencyBox' then walk(element, visit) else visit(element) end
		end
	end
	-- every searchable element of the menu: { tab, box, boxName, element }
	local function collect()
		local found = {}
		for _, tab in ipairs(Library.Window and Library.Window.Tabs or {}) do
			for name, box in pairs(tab.Groupboxes) do
				walk(box, function(element) table.insert(found, { tab = tab, box = box, boxName = name, element = element }) end)
			end
			for _, tabbox in pairs(tab.Tabboxes) do
				for _, sub in ipairs(tabbox.Tabs or {}) do
					walk(sub, function(element)
						table.insert(found, { tab = tab, box = sub, boxName = tostring(tabbox.Name or 'tabs') .. ' / ' .. tostring(sub.Name), element = element, sub = sub })
					end)
				end
			end
		end
		return found
	end
	local SEARCHABLE = { Toggle = true, Slider = true, Dropdown = true, Input = true, Label = true, Button = true }

	local function flash(element)
		local holder = element.Holder
		if not (holder and holder.Parent) then return end
		local glow = New('Frame', { Size = dim2(1, 8, 1, 4), Position = dim2(0, -4, 0, -2), BackgroundTransparency = 0.7, ZIndex = holder.ZIndex + 5, Active = false, Parent = holder }, { BackgroundColor3 = 'accent' })
		Tween(glow, { BackgroundTransparency = 1 }, 1.4, Enum.EasingStyle.Quad)
		task.delay(1.5, function() glow:Destroy() end)
	end

	local function jump(entry)
		entry.tab:Show(true)
		local root = entry.box.Root or entry.box
		if root.SetCollapsed then root:SetCollapsed(false) end
		if entry.sub then entry.sub:Show() end
		task.delay(0.12, function()
			local holder = entry.element.Holder
			local column = entry.box.Container and entry.box.Container:FindFirstAncestorWhichIsA('ScrollingFrame')
			if holder and column then
				local target = holder.AbsolutePosition.Y - column.AbsolutePosition.Y + column.CanvasPosition.Y - 24
				column.CanvasPosition = Vector2.new(0, max(0, target))
			end
			flash(entry.element)
		end)
	end

	function Window:BuildSearch()
		local header = self.TitleHolder
		local footerWidth = TextWidth(self.FooterLabel.Text, Library.TextSize) + 16
		local outer, field = Panel(header, { 'a', 'd' }, { Size = UDim2.fromOffset(170, 20), AnchorPoint = vec2(1, 0.5), Position = UDim2.new(1, -footerWidth, 0.5, 0) })
		outer.ZIndex = 5
		local box = New('TextBox', {
			Text = '', PlaceholderText = 'search', BackgroundTransparency = 1, Size = dim2(1, -10, 1, 0), Position = dim2(0, 6, 0, 0), TextSize = Library.TextSize,
			TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false, ZIndex = 6, Parent = field,
		})
		box.PlaceholderColor3 = Palette.dim
		self.SearchBox = box

		-- results page
		local page = New('Frame', { Name = 'SearchResults', BackgroundTransparency = 1, Size = dim2(1, 0, 1, 0), Visible = false, ZIndex = 30, Parent = self.Pages })
		New('Frame', { Size = dim2(1, 0, 1, 0), ZIndex = 30, Parent = page }, { BackgroundColor3 = 'e' })
		local list = New('ScrollingFrame', {
			BackgroundTransparency = 1, Size = dim2(1, -24, 1, -24), Position = dim2(0, 12, 0, 12), ScrollBarThickness = 2, AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = dim2(0, 0, 0, 0), ZIndex = 31, Active = true, Parent = page,
		})
		Library.Theme(list, 'ScrollBarImageColor3', 'accent')
		New('UIListLayout', { Padding = dim(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
		local heading = New('TextLabel', { Text = '', BackgroundTransparency = 1, Size = dim2(1, 0, 0, 16), TextSize = Library.TextSize, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 0, ZIndex = 32, Parent = list }, { TextColor3 = 'dim' })
		local rows = {}
		local token = 0

		local function close()
			page.Visible = false
			if self.ActiveTab then self.ActiveTab.Page.Visible = true end
		end
		local function refresh()
			token += 1
			local mine = token
			task.delay(0.12, function()
				if mine ~= token or Library.Unloaded then return end
				local needle = plain(box.Text):lower()
				for _, row in ipairs(rows) do row:Destroy() end
				table.clear(rows)
				if needle == '' then
					close()
					return
				end
				local count = 0
				for _, entry in ipairs(collect()) do
					local element = entry.element
					local text = plain(element.Text)
					if SEARCHABLE[element.Type] and text ~= '' and text:lower():find(needle, 1, true) then
						count += 1
						if count <= 80 then
							local row = New('TextButton', { Text = '', AutoButtonColor = false, BackgroundTransparency = 1, Size = dim2(1, 0, 0, 20), LayoutOrder = count, ZIndex = 32, Parent = list })
							local crumb = string.format('%s > %s', entry.tab.Name:lower(), tostring(entry.boxName):lower())
							New('TextLabel', { Text = text, BackgroundTransparency = 1, Size = dim2(0.5, 0, 1, 0), Position = dim2(0, 8, 0, 0), TextSize = Library.TextSize, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 33, Parent = row })
							New('TextLabel', {
								Text = crumb, BackgroundTransparency = 1, Size = dim2(0.5, -16, 1, 0), Position = dim2(0.5, 8, 0, 0), TextSize = Library.TextSize, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 33, Parent = row,
							}, { TextColor3 = 'dim' })
							Connect(row.MouseEnter, function()
								row.BackgroundColor3 = Palette.accent
								Tween(row, { BackgroundTransparency = 0.85 }, 0.08)
							end)
							Connect(row.MouseLeave, function() Tween(row, { BackgroundTransparency = 1 }, 0.1) end)
							Connect(row.MouseButton1Click, function()
								box.Text = ''
								close()
								jump(entry)
							end)
							table.insert(rows, row)
						end
					end
				end
				heading.Text = count == 0 and 'no matches' or (count > 80 and ('showing 80 of ' .. count .. ' matches') or (count .. ' match' .. (count == 1 and '' or 'es')))
				if self.ActiveTab then self.ActiveTab.Page.Visible = false end
				page.Visible = true
			end)
		end
		Connect(box:GetPropertyChangedSignal('Text'), refresh)
		Connect(box.FocusLost, function(entered)
			if entered and box.Text == '' then close() end
		end)
		-- changing tab leaves the search
		local previousHook = Library.OnTabChanged
		Library.OnTabChanged = function(tab)
			if page.Visible and not box:IsFocused() then
				page.Visible = false
				box.Text = ''
			end
			if previousHook then previousHook(tab) end
		end
	end
end

-- ==== 50_misc.lua ====
-- ZkxVader misc: notifications, dialog, draggable label.
do
	local Window, Dialog, Container = Classes.Window, Classes.Dialog, Classes.Container

	--// notifications \\--
	local holder
	local counter = 0
	local function ensureHolder()
		Library:EnsureGui()
		if holder and holder.Parent then return holder end
		local left = tostring(Library.NotifySide):lower() ~= 'right'
		holder = New('Frame', {
			Name = 'Notifications', BackgroundTransparency = 1, AnchorPoint = vec2(left and 0 or 1, 0), Position = dim2(left and 0 or 1, left and 14 or -14, 0, 14),
			Size = dim2(0, 300, 1, -28), ZIndex = 200, Parent = Library.Main,
		})
		New('UIListLayout', { Padding = dim(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = left and Enum.HorizontalAlignment.Left or Enum.HorizontalAlignment.Right, Parent = holder })
		return holder
	end

	function Library:Notify(...)
		if Library.Unloaded then return nil end
		local data = {}
		local first = select(1, ...)
		if type(first) == 'table' then
			data.Title = first.Title ~= nil and tostring(first.Title) or nil
			data.Description = first.Description ~= nil and tostring(first.Description) or ''
			data.Time = first.Time or 5
			data.Persist = first.Persist
			data.TitleColor, data.DescriptionColor = first.TitleColor, first.DescriptionColor
		else
			data.Description = tostring(first)
			data.Time = select(2, ...) or 5
		end
		local left = tostring(Library.NotifySide):lower() ~= 'right'
		local parent = ensureHolder()
		counter += 1
		local wrapper = New('Frame', { BackgroundTransparency = 1, Size = dim2(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = counter, Parent = parent })
		local panel, inner = Panel(wrapper, { 'a', 'b', 'e' }, { Size = dim2(1, 0, 0, 0), Auto = true })
		panel.Position = dim2(left and -1.15 or 1.15, 0, 0, 0)
		New('UIListLayout', { Padding = dim(0, 3), SortOrder = Enum.SortOrder.LayoutOrder, Parent = inner })
		New('UIPadding', { PaddingTop = dim(0, 6), PaddingBottom = dim(0, 8), PaddingLeft = dim(0, 8), PaddingRight = dim(0, 8), Parent = inner })
		local notification = { Destroyed = false }
		local titleLabel
		if data.Title then
			titleLabel = New('TextLabel', {
				Text = data.Title, BackgroundTransparency = 1, Size = dim2(1, 0, 0, 14), TextSize = Library.TextSize, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1, RichText = true, ZIndex = 201, Parent = inner,
			}, { TextColor3 = 'accent' })
			if data.TitleColor then titleLabel.TextColor3 = data.TitleColor end
		end
		local body = New('TextLabel', {
			Text = data.Description, BackgroundTransparency = 1, Size = dim2(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = Library.TextSize, TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, LayoutOrder = 2, RichText = true, ZIndex = 201, Parent = inner,
		}, { TextColor3 = data.Title and 'dim' or 'text' })
		if data.DescriptionColor then body.TextColor3 = data.DescriptionColor end
		local barHolder = New('Frame', { BackgroundTransparency = 1, Size = dim2(1, 0, 0, 2), LayoutOrder = 3, Parent = inner })
		local bar = New('Frame', { Size = dim2(1, 0, 1, 0), Parent = barHolder }, { BackgroundColor3 = 'accent' })

		local dismissed = false
		function notification:Destroy()
			if dismissed then return end
			dismissed = true
			notification.Destroyed = true
			if not wrapper.Parent then return end
			local height = wrapper.AbsoluteSize.Y / max(Library.GetScale(), 0.01)
			if Animating() then
				wrapper.AutomaticSize = Enum.AutomaticSize.None
				wrapper.Size = dim2(1, 0, 0, height)
				Tween(panel, { Position = dim2(left and -1.15 or 1.15, 0, 0, 0) }, 0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
				task.delay(0.22, function()
					if wrapper.Parent then Tween(wrapper, { Size = dim2(1, 0, 0, 0) }, 0.18, Enum.EasingStyle.Quint) end
				end)
				task.delay(0.45, function() wrapper:Destroy() end)
			else
				wrapper:Destroy()
			end
		end
		function notification:ChangeTitle(text)
			if titleLabel then titleLabel.Text = tostring(text) end
		end
		function notification:ChangeDescription(text) body.Text = tostring(text) end

		-- slide in, decode the text, count down
		if Animating() then
			Tween(panel, { Position = dim2(0, 0, 0, 0) }, 0.45, Enum.EasingStyle.Quint)
			if titleLabel then
				FX.Scramble(titleLabel, data.Title, 0.35)
				FX.Glitch(titleLabel, 0.2)
			elseif #data.Description <= 70 and not data.Description:find('<') then
				FX.Scramble(body, data.Description, 0.3)
			end
		else
			panel.Position = dim2(0, 0, 0, 0)
		end
		local duration = tonumber(data.Time)
		if data.Persist or not duration then
			barHolder.Visible = false
			if typeof(data.Time) == 'Instance' then
				data.Time.Destroying:Once(function() notification:Destroy() end)
			end
		else
			Tween(bar, { Size = dim2(0, 0, 1, 0) }, duration, Enum.EasingStyle.Linear)
			task.delay(duration, function() notification:Destroy() end)
		end
		return notification
	end

	--// dialog \\--
	local VARIANTS = { Primary = 'accent', Destructive = 'risky', Ghost = 'text' }
	function Window:AddDialog(idx, info)
		info = info or {}
		local settings = {
			Title = info.Title or 'Dialog', Description = info.Description or '', AutoDismiss = info.AutoDismiss ~= false, OutsideClickDismiss = info.OutsideClickDismiss ~= false,
			FooterButtons = info.FooterButtons or {},
		}
		Library:EnsureGui()
		Library.Dialogs = Library.Dialogs or {}
		local existing = Library.Dialogs[idx]
		if existing then existing:Dismiss(true) end

		local layer = New('TextButton', {
			Text = '', AutoButtonColor = false, Size = dim2(1, 0, 1, 0), BackgroundColor3 = rgb(0, 0, 0), BackgroundTransparency = 1, ZIndex = 150, Active = true, Parent = Library.Main,
		})
		Tween(layer, { BackgroundTransparency = 0.45 }, 0.2)
		local panel, inner = Panel(layer, { 'a', 'b', 'c', 'e' }, { Size = dim2(0, 440, 0, 0), Auto = true, AnchorPoint = vec2(0.5, 0.5), Position = dim2(0.5, 0, 0.5, 0) })
		panel.ZIndex = 151
		panel.AutomaticSize = Enum.AutomaticSize.Y
		New('UIListLayout', { Padding = dim(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = inner })
		New('UIPadding', { PaddingTop = dim(0, 12), PaddingBottom = dim(0, 12), PaddingLeft = dim(0, 14), PaddingRight = dim(0, 14), Parent = inner })
		local title = New('TextLabel', { Text = settings.Title, BackgroundTransparency = 1, Size = dim2(1, 0, 0, 16), TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1, ZIndex = 152, Parent = inner }, { TextColor3 = 'accent' })
		New('TextLabel', {
			Text = settings.Description, BackgroundTransparency = 1, Size = dim2(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = Library.TextSize, TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, LayoutOrder = 2, ZIndex = 152, Visible = settings.Description ~= '', Parent = inner,
		}, { TextColor3 = 'dim' })
		local content = New('Frame', { BackgroundTransparency = 1, Size = dim2(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, ZIndex = 152, Parent = inner })
		New('UIListLayout', { Padding = dim(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content })
		local footer = New('Frame', { BackgroundTransparency = 1, Size = dim2(1, 0, 0, 22), LayoutOrder = 4, ZIndex = 152, Parent = inner })
		New('UIListLayout', { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = dim(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = footer })

		local dialog = setmetatable({ Library = Library, Container = content, Elements = {}, Type = 'Dialog', Index = idx, Dismissed = false, Panel = panel, Layer = layer }, Dialog)
		function dialog:Dismiss(instant)
			if dialog.Dismissed then return end
			dialog.Dismissed = true
			Library:ClosePopup()
			if Library.Dialogs[idx] == dialog then Library.Dialogs[idx] = nil end
			for index = #dialog.Elements, 1, -1 do
				local element = dialog.Elements[index]
				if element and element.Destroy then pcall(element.Destroy, element) end
			end
			if instant ~= true and Animating() then
				Tween(layer, { BackgroundTransparency = 1 }, 0.15)
				task.delay(0.16, function() layer:Destroy() end)
			else
				layer:Destroy()
			end
		end
		local ordered = {}
		for name, button in pairs(settings.FooterButtons) do table.insert(ordered, { Name = name, Info = button }) end
		table.sort(ordered, function(a, b) return (a.Info.Order or 0) < (b.Info.Order or 0) end)
		for index, entry in ipairs(ordered) do
			local variantKey = VARIANTS[entry.Info.Variant or 'Ghost'] or 'text'
			local text = tostring(entry.Info.Title or entry.Name)
			local outer, face = Panel(footer, { variantKey == 'text' and 'a' or 'a', 'c' }, { Size = UDim2.fromOffset(TextWidth(text, Library.TextSize) + 22, 22) })
			outer.LayoutOrder, outer.ZIndex = index, 153
			local button = New('TextButton', { Text = text, AutoButtonColor = false, BackgroundTransparency = 1, Size = dim2(1, 0, 1, 0), TextSize = Library.TextSize, ZIndex = 154, Parent = face })
			Library.Registry[button] = { TextColor3 = variantKey }
			button.TextColor3 = Palette[variantKey]
			Connect(button.MouseEnter, function() Tween(face, { BackgroundColor3 = Palette.g }, 0.1) end)
			Connect(button.MouseLeave, function() Tween(face, { BackgroundColor3 = Palette.c }, 0.15) end)
			Connect(button.MouseButton1Click, function()
				Library:SafeCallback(entry.Info.Callback, dialog)
				if settings.AutoDismiss and not dialog.Dismissed then dialog:Dismiss() end
			end)
		end
		Connect(layer.MouseButton1Click, function()
			if settings.OutsideClickDismiss and not IsMouseOver(panel) then dialog:Dismiss() end
		end)
		if Animating() then
			panel.Position = dim2(0.5, 0, 0.5, 14)
			Tween(panel, { Position = dim2(0.5, 0, 0.5, 0) }, 0.28, Enum.EasingStyle.Quint)
			FX.Scramble(title, settings.Title, 0.3)
		end
		Library.Dialogs[idx] = dialog
		return dialog
	end

	--// draggable label (a small movable text panel) \\--
	function Library:AddDraggableLabel(text)
		Library:EnsureGui()
		local frame, inner = Panel(Library.Main, { 'a', 'b', 'e' }, { Size = dim2(0, 0, 0, 0), Auto = true, Position = dim2(0.5, -90, 0, 90) })
		frame.AutomaticSize = Enum.AutomaticSize.XY
		inner.AutomaticSize = Enum.AutomaticSize.XY
		frame.ZIndex = 45
		local label = New('TextLabel', {
			Text = tostring(text or ''), BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.XY, Size = dim2(0, 0, 0, 0), TextSize = Library.TextSize, RichText = true, ZIndex = 46, Active = true, Parent = inner,
		})
		New('UIPadding', { PaddingLeft = dim(0, 8), PaddingRight = dim(0, 8), PaddingTop = dim(0, 4), PaddingBottom = dim(0, 5), Parent = inner })
		Library.MakeDraggable(frame, label)
		local object = { Frame = frame, Label = label, Type = 'DraggableLabel', Visible = true }
		function object:SetText(value) label.Text = tostring(value) end
		function object:SetVisible(visible)
			object.Visible = visible
			frame.Visible = visible
		end
		function object:Destroy() frame:Destroy() end
		return object
	end
end

-- ==== 99_end.lua ====

-- like Obsidian, publish the instance (the hub's unload path and external tooling look for getgenv().Library)
pcall(function()
	local env = (type(getgenv) == 'function' and getgenv()) or _G
	env.Library = Library
end)

-- done: the Library table is the module
return Library

end)()
