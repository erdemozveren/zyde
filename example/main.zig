const std = @import("std");
const Zyde = @import("zyde");

const Credentials = struct {
    username: []const u8,
    password: []const u8,
};

pub fn login(cred: Credentials) bool {
    return std.mem.eql(u8, cred.username, "erdem") and std.mem.eql(u8, cred.password, "123");
}

pub fn toggleFullscreen(ctx: *Zyde.Context) !bool {
    const fullscreen = try ctx.window.isFullscreen();

    if (fullscreen) {
        try ctx.window.unfullscreen();
    } else {
        try ctx.window.fullscreen();
    }

    return !fullscreen;
}

pub fn eval(ctx: *Zyde.Context) !void {
    try ctx.window.eval("alert('Hello from Zig!')");
}

fn add(a: i32, b: i32) !i32 {
    return a + b;
}

const User = struct {
    name: []const u8,
    age: u32,
};

fn getUsers(ctx: *Zyde.Context) ![]User {
    const users = try ctx.allocator.alloc(User, 3);

    users[0] = .{ .name = "Erdem", .age = 28 };
    users[1] = .{ .name = "Alice", .age = 24 };
    users[2] = .{ .name = "Bob", .age = 31 };

    return users;
}

// Commands are regular Zig functions.
// They can live in this file or be imported from other modules.
const App = Zyde.App(.{ Zyde.DefaultCommands.WindowControls, .{
    .@"window.toggleFullscreen" = toggleFullscreen,
    .@"window.eval" = eval,
    .getUsers = getUsers,
    .login = login,
    .add = add,
} });

pub fn main(init: std.process.Init) !void {
    const app = try App.init(
        init.io,
        init.gpa,
        true,
        null,
    );
    defer app.deinit();

    var window = try app.createWindow();
    defer window.deinit();

    try window.setTitle("Zyde Example");
    try window.navigate(app.serve_url);

    try window.run();
}
