# ZkxVader

A Roblox UI library: a fork of **Vaderhaxx** by [i77lhm](https://github.com/i77lhm/Libraries/tree/main/Vaderhaxx) (MIT), extended with an Obsidian-style API,
transitions and text effects. Pixel font, layered 1px outlines, yellow accent.

## Use

```lua
local Library = loadstring(game:HttpGet('https://raw.githubusercontent.com/Zkxrll/<this-repo>/main/Library.lua'))()

local Window = Library:CreateWindow({ Title = 'My Hub', Footer = 'v1', Size = UDim2.fromOffset(920, 640), AutoShow = true })
local Tab = Window:AddTab('combat')
local Box = Tab:AddLeftGroupbox('aim assist')

Box:AddToggle('aim', { Text = 'Enabled', Default = true, Callback = function(value) print(value) end })
    :AddKeyPicker('aimKey', { Default = 'RightShift', Mode = 'Toggle', Text = 'Aim' })
Box:AddSlider('fov', { Text = 'FOV', Default = 90, Min = 10, Max = 360, Rounding = 0, Suffix = ' deg' })
Box:AddDropdown('part', { Text = 'Hitbox', Values = { 'Head', 'Torso' }, Default = 'Head' })
Box:AddButton('Hello', function() Library:Notify({ Title = 'Hi', Description = 'works', Time = 4 }) end)

print(Library.Toggles.aim.Value, Library.Options.fov.Value)
```

Elements: toggle (+ key picker, colour picker addons), slider, dropdown (single / multi / search / Player / Team), input, button (+ sub buttons, double click),
label, divider, dependency box (`SetupDependencies`), tabbox, viewport, dialog (`Window:AddDialog`), notifications, tooltips, header search, keybind list.
Controls are objects with `Value`, `SetValue`, `OnChanged`, `Type`, `SetVisible`, `SetDisabled`; `Library.Toggles` / `Library.Options` hold them by id.
`Library:Unload()` removes everything (GUI, connections, loops). Menu key: `Library.ToggleKeybind` (default RightControl).

## Effects

Tab switch slide + fade with a gliding underline, window open/close, toggle pop, dropdown / dependency / collapse easing, notification slide with countdown bar,
scrambling tab names and notification titles, shimmering title, glitch on risky toggles. `Library.Animations.Enabled = false` turns them off.
`Library.FX` has `Rainbow`, `Shimmer`, `Wave`, `Pulse`, `Scramble`, `Typewriter`, `Glitch` for your own labels.

## Notes

* The pixel font (ProggyClean) is downloaded once from `i77lhm/storage` into the `ZkxVader` workspace folder; without file/HTTP functions it falls back to `Enum.Font.Code`.
* Needs an executor with `gethui` (or falls back to CoreGui); `getgenv().Library` is set to the library table.
* Credit: Vaderhaxx by i77lhm. License: MIT (see `LICENSE`).
