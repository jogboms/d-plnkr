const std = @import("std");
const sqlite = @import("sqlite");

const schemaVersion = 1;
const configDirName = ".config";
const configSubDirName = "d-plnkr";
const dbName = "default.db";

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) {
        @panic("Leaks detected");
    };

    const allocator = gpa.allocator();

    const isProduction = try isEnabledFromEnv(allocator, "PROD");
    const dbFilePath: []u8 = if (isProduction) block: {
        const homeDir = fromEnv(allocator, "HOME") catch @panic("Could not find $HOME environment variable");
        defer allocator.free(homeDir);

        const dbDir = try std.fs.path.join(allocator, &[_][]const u8{ homeDir, configDirName, configSubDirName });
        defer allocator.free(dbDir);

        _ = std.fs.cwd().makeDir(dbDir) catch |e| switch (e) {
            error.PathAlreadyExists => std.log.debug("Skipping config directory creation as it exists", .{}),
            else => std.debug.panic("Unhandle error: {any}", .{e}),
        };

        break :block try std.fs.path.join(allocator, &[_][]const u8{ dbDir, dbName });
    } else try std.fs.path.join(allocator, &[_][]const u8{ ".", dbName });
    defer allocator.free(dbFilePath);

    const dbPath = try std.mem.Allocator.dupeZ(allocator, u8, dbFilePath);
    defer allocator.free(dbPath);
}

fn isEnabledFromEnv(allocator: std.mem.Allocator, key: []const u8) anyerror!bool {
    const value = fromEnv(allocator, key) catch |e| switch (e) {
        error.EnvironmentVariableNotFound => return false,
        else => std.debug.panic("Unhandle error: {any}", .{e}),
    };
    defer allocator.free(value);

    return std.mem.eql(u8, value, "1");
}

fn fromEnv(allocator: std.mem.Allocator, key: []const u8) anyerror![]const u8 {
    return try std.process.getEnvVarOwned(allocator, key);
}
