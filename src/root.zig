const std = @import("std");
const serde = @import("serde");
const Io = std.Io;

const Commands = @import("command-registry.zig");
const Registry = Commands.Registry;
pub const Context = Commands.Context;

const httpz = @import("httpz");
pub const Webview = @import("webview").Webview;
pub const PublicFolder = @import("embedded_public");
const js_bridge_code = @embedFile("init.js");
pub const DefaultCommands = @import("default-commands.zig");

const InvokeArgs = std.meta.Tuple(&.{
    []const u8, // name
    ?[]const u8, // args
});
pub const Window = struct {
    const Self = @This();
    w: *Webview,
    gpa: std.mem.Allocator,
    destroy_handler: *const fn (
        std.mem.Allocator,
        *anyopaque,
    ) void,

    handler: *anyopaque,

    pub fn deinit(self: *Self) void {
        self.w.destroy() catch {};

        self.destroy_handler(
            self.gpa,
            self.handler,
        );

        self.gpa.destroy(self);
    }

    pub fn run(self: *Self) Webview.Error!void {
        return self.w.run();
    }

    pub fn terminate(self: *Self) Webview.Error!void {
        return self.w.terminate();
    }

    pub fn getWindow(self: *Self) ?*anyopaque {
        return self.w.getWindow();
    }

    pub fn getNativeHandle(
        self: *Self,
        comptime kind: Webview.NativeHandleKind,
    ) ?*anyopaque {
        return self.w.getNativeHandle(kind);
    }

    pub fn setTitle(
        self: *Self,
        title: [:0]const u8,
    ) Webview.Error!void {
        return self.w.setTitle(title);
    }

    pub fn setSize(
        self: *Self,
        width: i32,
        height: i32,
        hint: Webview.Hint,
    ) Webview.Error!void {
        return self.w.setSize(width, height, hint);
    }

    pub fn navigate(
        self: *Self,
        url: [:0]const u8,
    ) Webview.Error!void {
        return self.w.navigate(url);
    }

    pub fn setHtml(
        self: *Self,
        html: [:0]const u8,
    ) Webview.Error!void {
        return self.w.setHtml(html);
    }

    pub fn addInitScript(
        self: *Self,
        js: [:0]const u8,
    ) Webview.Error!void {
        return self.w.addInitScript(js);
    }

    pub fn eval(
        self: *Self,
        js: [:0]const u8,
    ) Webview.Error!void {
        return self.w.eval(js);
    }

    pub fn maximize(self: *Self) Webview.Error!void {
        return self.w.maximize();
    }

    pub fn unmaximize(self: *Self) Webview.Error!void {
        return self.w.unmaximize();
    }

    pub fn minimize(self: *Self) Webview.Error!void {
        return self.w.minimize();
    }

    pub fn unminimize(self: *Self) Webview.Error!void {
        return self.w.unminimize();
    }

    pub fn fullscreen(self: *Self) Webview.Error!void {
        return self.w.fullscreen();
    }

    pub fn unfullscreen(self: *Self) Webview.Error!void {
        return self.w.unfullscreen();
    }

    pub fn hide(self: *Self) Webview.Error!void {
        return self.w.hide();
    }

    pub fn show(self: *Self) Webview.Error!void {
        return self.w.show();
    }

    pub fn isFullscreen(self: *Self) Webview.Error!bool {
        return self.w.isFullscreen();
    }

    pub fn isMaximized(self: *Self) Webview.Error!bool {
        return self.w.isMaximized();
    }

    pub fn isMinimized(self: *Self) Webview.Error!bool {
        return self.w.isMinimized();
    }

    pub fn isVisible(self: *Self) Webview.Error!bool {
        return self.w.isVisible();
    }
};

pub fn App(comptime commands: anytype) type {
    return struct {
        const Self = @This();
        const registry = Registry(commands);
        const WebviewHandler = struct {
            const SelfWebviewHandler = @This();
            w: *Webview,
            window: *Window,
            app: *Self,
            pub fn handleInvokeRequest(self: *SelfWebviewHandler, id: [:0]const u8, req: [:0]const u8) void {
                // Retain up to 64 KB for reuse by the next request.
                _ = self.app.arena.reset(
                    .{ .retain_with_limit = 64 * 1024 },
                );

                const allocator = self.app.arena.allocator();
                const parsed = serde.json.fromSlice(
                    InvokeArgs,
                    allocator,
                    req,
                ) catch {
                    self.w.respond(id, .err, "\"Provide valid invoke args\"") catch {};
                    return;
                };

                const name = parsed[0];
                const args_json = parsed[1] orelse "[]";
                var ctx: Context = .{
                    .allocator = allocator,
                    .window = self.window,
                };
                const response = registry.call(
                    &ctx,
                    name,
                    args_json,
                ) catch |err| {
                    const message = std.fmt.allocPrintSentinel(
                        allocator,
                        "\"Error at {s}: {s}\"",
                        .{
                            name,
                            @errorName(err),
                        },
                        0,
                    ) catch "Unknown Error at invoke";
                    self.w.respond(id, .err, message) catch {};
                    return;
                };

                defer response.deinit(allocator);

                switch (response) {
                    .void => {
                        self.w.respond(id, .ok, "") catch {};
                    },

                    .json => |json| {
                        self.w.respond(id, .ok, json) catch {};
                    },
                }
            }
        };

        server: httpz.Server(void),
        debug: bool,
        serve_url: [:0]const u8,
        server_thread: std.Thread,

        gpa: std.mem.Allocator,
        arena: std.heap.ArenaAllocator,

        pub fn init(
            io: Io,
            gpa_allocator: std.mem.Allocator,
            debug: bool,
            port: ?u16,
        ) !*Self {
            const chosen_port = if (port) |p| p else try getFreePort(io);

            var server = try httpz.Server(void).init(
                io,
                gpa_allocator,
                .{
                    .address = .localhost(chosen_port),
                },
                {},
            );

            errdefer server.deinit();

            const arena = std.heap.ArenaAllocator.init(
                gpa_allocator,
            );

            const serve_url = try std.fmt.allocPrintSentinel(
                gpa_allocator,
                "http://localhost:{d}",
                .{chosen_port},
                0,
            );

            errdefer gpa_allocator.free(serve_url);

            var router = try server.router(.{});
            router.get("/*", staticFileHandler, .{});

            const self = try gpa_allocator.create(Self);
            errdefer gpa_allocator.destroy(self);

            self.* = .{
                .server = server,
                .debug = debug,
                .serve_url = serve_url,
                .server_thread = undefined,
                .gpa = gpa_allocator,
                .arena = arena,
            };
            self.server_thread = try self.server.listenInNewThread();
            return self;
        }

        pub fn createWindow(self: *Self) !*Window {
            const win = try self.gpa.create(Window);
            errdefer self.gpa.destroy(win);

            const wv_handler = try self.gpa.create(WebviewHandler);
            errdefer self.gpa.destroy(wv_handler);

            const webview = try Webview.create(self.debug, null);
            errdefer webview.destroy() catch {};

            wv_handler.* = .{
                .app = self,
                .w = webview,
                .window = win,
            };

            const destroy_handler = struct {
                fn destroy(
                    allocator: std.mem.Allocator,
                    ptr: *anyopaque,
                ) void {
                    const handler: *WebviewHandler =
                        @ptrCast(@alignCast(ptr));

                    allocator.destroy(handler);
                }
            }.destroy;

            win.* = .{
                .gpa = self.gpa,
                .w = webview,
                .handler = wv_handler,
                .destroy_handler = destroy_handler,
            };

            try webview.bind(
                WebviewHandler,
                "__zyde_raw_invoke",
                WebviewHandler.handleInvokeRequest,
                wv_handler,
            );

            try webview.addInitScript(js_bridge_code);
            try webview.navigate(self.serve_url);

            return win;
        }

        pub fn deinit(self: *Self) void {
            self.server.stop();
            self.server.deinit();
            self.server_thread.join();

            self.gpa.free(self.serve_url);
            self.arena.deinit();

            self.gpa.destroy(self);
        }
    };
}
pub fn staticFileHandler(
    req: *httpz.Request,
    res: *httpz.Response,
) !void {
    if (std.mem.eql(u8, req.url.raw, "/")) {
        res.content_type = .HTML;
        if (PublicFolder.get("/index.html")) |indexHtml| {
            res.body = indexHtml;
            return;
        }
    }

    if (PublicFolder.get(req.url.raw)) |content| {
        res.content_type = getMimeType(req.url.raw);
        res.body = content;
        return;
    }

    if (PublicFolder.get("/404.html")) |content| {
        res.content_type = .HTML;
        res.body = content;
        res.status = 404;
        return;
    }

    res.status = 404;
    res.body = "Not Found";
}

fn getFreePort(io: Io) !u16 {
    const loopback: Io.net.IpAddress = .{
        .ip4 = .loopback(0),
    };

    var server = try loopback.listen(io, .{
        .reuse_address = true,
    });

    defer server.deinit(io);

    return server.socket.address.ip4.port;
}

fn getMimeType(filename: []const u8) httpz.ContentType {
    const ext = std.fs.path.extension(filename);

    if (std.mem.eql(u8, ext, ".css")) return .CSS;
    if (std.mem.eql(u8, ext, ".csv")) return .CSV;
    if (std.mem.eql(u8, ext, ".eot")) return .EOT;
    if (std.mem.eql(u8, ext, ".events")) return .EVENTS;
    if (std.mem.eql(u8, ext, ".gif")) return .GIF;
    if (std.mem.eql(u8, ext, ".gz")) return .GZ;
    if (std.mem.eql(u8, ext, ".html")) return .HTML;
    if (std.mem.eql(u8, ext, ".htm")) return .HTML;
    if (std.mem.eql(u8, ext, ".ico")) return .ICO;
    if (std.mem.eql(u8, ext, ".jpg")) return .JPG;
    if (std.mem.eql(u8, ext, ".js")) return .JS;
    if (std.mem.eql(u8, ext, ".json")) return .JSON;
    if (std.mem.eql(u8, ext, ".otf")) return .OTF;
    if (std.mem.eql(u8, ext, ".pdf")) return .PDF;
    if (std.mem.eql(u8, ext, ".png")) return .PNG;
    if (std.mem.eql(u8, ext, ".svg")) return .SVG;
    if (std.mem.eql(u8, ext, ".tar")) return .TAR;
    if (std.mem.eql(u8, ext, ".text")) return .TEXT;
    if (std.mem.eql(u8, ext, ".ttf")) return .TTF;
    if (std.mem.eql(u8, ext, ".wasm")) return .WASM;
    if (std.mem.eql(u8, ext, ".webp")) return .WEBP;
    if (std.mem.eql(u8, ext, ".woff")) return .WOFF;
    if (std.mem.eql(u8, ext, ".woff2")) return .WOFF2;
    if (std.mem.eql(u8, ext, ".xml")) return .XML;

    return .BINARY;
}
