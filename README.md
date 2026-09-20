# Zyde

Zyde is a Zig library for building desktop applications with web-based UIs. It provides a lightweight alternative to Electron by using the operating system's native WebView instead of bundling Chromium.

Use regular Zig functions as commands from your web UI. Register a function and invoke it from JavaScript — arguments are deserialized automatically, and return values are serialized back to JavaScript.

Zyde is inspired by [Tauri](https://tauri.app/) and the general approach behind tools like Electron: build desktop applications using web technologies while keeping the application logic in native code.

This is **not intended to be a full Electron or Tauri alternative**. It is currently a hobby project.

> Zyde is pronounced *“zayd”* (/zaɪd/) and is just a dummy name.
> Supported Zig version: 0.16.0

## How it works

The UI runs inside the operating system's native WebView.

At startup, Zyde starts a local HTTP server using [http.zig](https://github.com/karlseguin/http.zig) on an available port and serves the embedded UI files from it. The application then opens that local URL in the native WebView.

This keeps the UI as a regular web application while allowing it to communicate with the Zig application through registered commands.

## Installation and usage

```bash
zig fetch --save https://github.com/erdemozveren/zyde
```

Then add the Zyde dependency to your `build.zig`:

```zig
const zyde = b.dependency("zyde", .{
    .target = target,
    .optimize = optimize,
    .public_dir = b.path("public"),
});
```

The `public_dir` option specifies the directory containing your UI files. It can point to any directory in your project. The directory will be recursively embedded at build time using Zig's `@embedFile`.

If a `404.html` file exists in the UI directory, it is used as the 404 fallback page.

## Example

The `examples` directory contains a small example application demonstrating how to use the library.

To build and run the example:

```bash
zig build example
```

> The example uses the `examples/public` directory as its UI.

```zig
const std = @import("std");
const Zyde = @import("zyde");

const App = Zyde.App(.{
    .add = add,
    .@"window.minimize" = minimize,
    .@"window.isMinimized" = isMinimized,
});

fn add(a: i32, b: i32) !i32 {
    return a + b;
}

fn minimize(ctx: *Zyde.Context) !void {
    try ctx.window.minimize();
}

fn isMinimized(ctx: *Zyde.Context) !bool {
    return ctx.window.isMinimized();
}

pub fn main(init: std.process.Init) !void {
    const app = try App.init(init.io, init.gpa, true, null);
    defer app.deinit();

    var window = try app.createWindow();
    defer window.deinit();

    try window.setTitle("Zyde Example");
    try window.navigate(app.serve_url);
    try window.run();
}
```

Commands are invoked from JavaScript:

```js
const result = await window.zyde.invoke("add", 10, 20);

await window.zyde.invoke("window.minimize");

const minimized = await window.zyde.invoke(
  "window.isMinimized"
);
```

The first parameter of a command can optionally be `*Zyde.Context`. If present, it receives the current request context; the remaining parameters are deserialized from the command arguments in order.

Command arguments and return values are serialized and deserialized using [`serde`](https://github.com/OrlovEvgeny/serde.zig).

Arguments can also be passed as objects and deserialized into Zig structs:

```zig
const Credentials = struct {
    username: []const u8,
    password: []const u8,
};

fn login(cred: Credentials) bool {
    return std.mem.eql(u8, cred.username, "erdem") and
        std.mem.eql(u8, cred.password, "123");
}
```

```js
const result = await window.zyde.invoke("login", {
    username,
    password,
});
```

### Command groups

Commands can be organized into separate structs and passed to `Zyde.App` as command groups. The groups are combined into a single command registry.

This makes it possible to provide reusable sets of commands, such as the built-in window commands, while still adding application-specific commands.

```zig
const App = Zyde.App(.{
    Zyde.DefaultCommands.WindowControls,
    .{
        .@"window.toggleFullscreen" = toggleFullscreen,
        .@"window.eval" = eval,
        .login = login,
        .add = add,
    },
});
```

`Zyde.DefaultCommands.WindowControls,` provides the basic window commands, while the second group adds application-specific commands.

## Dependencies

* [http.zig](https://github.com/karlseguin/http.zig)
* [serde](https://github.com/OrlovEvgeny/serde.zig)
* [zig-webview](https://github.com/happystraw/zig-webview)

For platform-specific requirements (WebKitGTK, WebView2, etc.), refer to the [webview/webview](https://github.com/webview/webview) documentation.

## License

MIT

