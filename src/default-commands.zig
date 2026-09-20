const Commands = @import("command-registry.zig");
const Webview = @import("webview").Webview;
const Context = Commands.Context;

pub const WindowControls = .{
    .@"window.maximize" = win_commands.maximize,
    .@"window.unmaximize" = win_commands.unmaximize,
    .@"window.minimize" = win_commands.minimize,
    .@"window.unminimize" = win_commands.unminimize,
    .@"window.fullscreen" = win_commands.fullscreen,
    .@"window.unfullscreen" = win_commands.unfullscreen,
    .@"window.hide" = win_commands.hide,
    .@"window.show" = win_commands.show,
    .@"window.isFullscreen" = win_commands.isFullscreen,
    .@"window.isMaximized" = win_commands.isMaximized,
    .@"window.isMinimized" = win_commands.isMinimized,
    .@"window.isVisible" = win_commands.isVisible,
};

const win_commands = struct {
    fn maximize(ctx: *Context) Webview.Error!void {
        return ctx.window.maximize();
    }

    fn unmaximize(ctx: *Context) Webview.Error!void {
        return ctx.window.unmaximize();
    }

    fn minimize(ctx: *Context) Webview.Error!void {
        return ctx.window.minimize();
    }

    fn unminimize(ctx: *Context) Webview.Error!void {
        return ctx.window.unminimize();
    }

    fn fullscreen(ctx: *Context) Webview.Error!void {
        return ctx.window.fullscreen();
    }

    fn unfullscreen(ctx: *Context) Webview.Error!void {
        return ctx.window.unfullscreen();
    }

    fn hide(ctx: *Context) Webview.Error!void {
        return ctx.window.hide();
    }

    fn show(ctx: *Context) Webview.Error!void {
        return ctx.window.show();
    }

    fn isFullscreen(ctx: *Context) Webview.Error!bool {
        return ctx.window.isFullscreen();
    }

    fn isMaximized(ctx: *Context) Webview.Error!bool {
        return ctx.window.isMaximized();
    }

    fn isMinimized(ctx: *Context) Webview.Error!bool {
        return ctx.window.isMinimized();
    }

    fn isVisible(ctx: *Context) Webview.Error!bool {
        return ctx.window.isVisible();
    }
};
