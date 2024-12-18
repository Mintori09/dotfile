local wezterm = require("wezterm")
local act = wezterm.action

if wezterm.plugin and wezterm.plugin.load then
    config.plugins = {
        wezterm.plugin.load("modal.wezterm"),
    }
else
    print("Warning: Plugin system not available.")
end

-- https://wezfurlong.org/wezterm/config/files.html
local config = wezterm.config_builder()
local keys = {
    {
        key = "w",
        mods = "CTRL",
        action = wezterm.action({CloseCurrentTab = {confirm = false}})
    }, {
        key = "t",
        mods = "CTRL",
        action = wezterm.action({SpawnTab = "CurrentPaneDomain"})
    }, {key = "c", mods = "CTRL", action = wezterm.action.CopyTo("Clipboard")},
    {key = "v", mods = "CTRL", action = wezterm.action.PasteFrom("Clipboard")},
    {
        key = "=",
        mods = "CTRL",
        action = wezterm.action.IncreaseFontSize -- Tăng kích thước font
    }, {
        key = "-",
        mods = "CTRL",
        action = wezterm.action.DecreaseFontSize -- Giảm kích thước font
    }, {
        key = "0",
        mods = "CTRL",
        action = wezterm.action.ResetFontSize -- Đặt lại kích thước font
    }, {
        key = "F11",
        action = wezterm.action.ToggleFullScreen -- Chuyển đổi chế độ toàn màn hình
    }
}

-- NOTE: some help/reminders:
--
-- Add logs with wezterm.log_info("hello")
-- See logs from wezterm: CTRL+SHIFT+L
--
-- Update all plugins:
-- wezterm.plugin.update_all()

local is_windows = os.getenv("OS") == "Windows_NT"

config.check_for_updates = true
config.check_for_updates_interval_seconds = 86400

-- font
-- https://www.jetbrains.com/lp/mono
-- https://github.com/ryanoasis/nerd-fonts/releases
-- https://fonts.google.com/noto/specimen/Noto+Color+Emoji
local disable_ligatures = {"calt=0", "clig=0", "liga=0"}
config.font = wezterm.font_with_fallback({
    -- { family = "Berkeley Mono" },
    -- { family = "JetBrains Mono", harfbuzz_features = disable_ligatures },
    -- { family = "JetBrainsMono Nerd Font", harfbuzz_features = disable_ligatures },
    {family = "CaskaydiaMono Nerd Font"}, {family = "Noto Color Emoji"},
    {family = "Noto Emoji"}
})

config.font_size = 13

-- colorschemes
-- https://wezfurlong.org/wezterm/colorschemes/
-- wezterm.gui is not available to the mux server, so take care to
-- do something reasonable when this config is evaluated by the mux
local function get_appearance()
    if wezterm.gui then
        return wezterm.gui.get_appearance() -- "Dark" or "Light"
    end
    return "Dark"
end

local function scheme_for_appearance(appearance)
    if appearance:find("Dark") then
        return "Catppuccin"
    else
        return "dayfox"
        -- return "Tokyo Night Day"
    end
end

config.color_scheme = scheme_for_appearance(get_appearance())

-- title bar
-- NOTE: For Windows/WSL, the "RESIZE" setting doesn't allow for moving around the window
if is_windows then
    config.window_decorations = "TITLE | RESIZE"
else
    config.window_decorations = "RESIZE"
end

-- https://wezfurlong.org/wezterm/config/lua/config/window_padding.html
config.window_padding = {left = 0, right = 0, top = 0, bottom = 0}

-- https://wezfurlong.org/wezterm/config/appearance.html
config.window_background_opacity = 1.0 -- 0.4
config.text_background_opacity = 1.0 -- 0.9

-- tab config
config.hide_tab_bar_if_only_one_tab = false
config.use_fancy_tab_bar = false

local function get_current_working_dir(tab)
    local current_dir =
        tab.active_pane and tab.active_pane.current_working_dir or
            {file_path = ""}
    local HOME_DIR = string.format("file://%s", os.getenv("HOME"))

    return current_dir == HOME_DIR and "." or
               string.gsub(current_dir.file_path, "(.*[/\\])(.*)", "%2")
end

-- tab title
wezterm.on("format-tab-title",
           function(tab, tabs, panes, config, hover, max_width)
    local has_unseen_output = false
    if not tab.is_active then
        for _, pane in ipairs(tab.panes) do
            if pane.has_unseen_output then
                has_unseen_output = true
                break
            end
        end
    end

    local cwd = wezterm.format({
        {Attribute = {Intensity = "Bold"}},
        {Text = get_current_working_dir(tab)}
    })

    local title = string.format(" [%s] %s", tab.tab_index + 1, cwd)

    if has_unseen_output then
        return {{Foreground = {Color = "#8866bb"}}, {Text = title}}
    end

    return {{Text = title}}
end)

-- workspaces
wezterm.on("update-right-status", function(window, pane)
    -- TODO: fix color, this is almost unreadable
    window:set_right_status(window:active_workspace())
end)
local workspace_switcher = wezterm.plugin.require(
                               "https://github.com/MLFlexer/smart_workspace_switcher.wezterm")
workspace_switcher.zoxide_path = "/opt/homebrew/bin/zoxide"
table.insert(keys, {
    key = "s",
    mods = "CTRL|SHIFT",
    action = workspace_switcher.switch_workspace()
})
table.insert(keys, {
    key = "t",
    mods = "CTRL|SHIFT",
    action = act.ShowLauncherArgs({flags = "FUZZY|WORKSPACES"})
})
table.insert(keys, {
    key = "[",
    mods = "CTRL|SHIFT",
    action = act.SwitchWorkspaceRelative(1)
})
table.insert(keys, {
    key = "]",
    mods = "CTRL|SHIFT",
    action = act.SwitchWorkspaceRelative(-1)
})

-- ssh hosts from ~./ssh/config
local ssh_domains = {}
for host, config_ in pairs(wezterm.enumerate_ssh_hosts()) do
    table.insert(ssh_domains, {
        -- the name can be anything you want; we're just using the hostname
        name = host,
        -- remote_address must be set to `host` for the ssh config to apply to it
        remote_address = host,

        -- if you don't have wezterm's mux server installed on the remote
        -- host, you may wish to set multiplexing = "None" to use a direct
        -- ssh connection that supports multiple panes/tabs which will close
        -- when the connection is dropped.

        -- multiplexing = "None",

        -- if you know that the remote host has a posix/unix environment,
        -- setting assume_shell = "Posix" will result in new panes respecting
        -- the remote current directory when multiplexing = "None".
        assume_shell = "Posix"
    })
end
config.ssh_domains = ssh_domains

config.audible_bell = "Disabled"
config.visual_bell = {
    fade_in_function = "EaseIn",
    fade_in_duration_ms = 150,
    fade_out_function = "EaseOut",
    fade_out_duration_ms = 150
}
config.colors = {visual_bell = "#202020"}
config.window_background_opacity = 0
config.win32_system_backdrop = "Mica"
-- start straight into WSL
config.default_prog = {"pwsh.exe"} -- Nếu bạn muốn mở PowerShell

config.keys = keys
return config
