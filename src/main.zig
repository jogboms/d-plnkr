const std = @import("std");
const sqlite = @import("sqlite");
const uuid = @import("uuid");

const schemaVersion = 1;
const configDirName = ".config";
const configSubDirName = "d-plnkr";
const dbName = "default.db";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) {
        @panic("Leaks detected");
    };

    const allocator = gpa.allocator();

    const dbFilePath = try deriveDbFilePath(allocator);
    const dbPath = try std.mem.Allocator.dupeZ(allocator, u8, dbFilePath);
    defer {
        allocator.free(dbFilePath);
        allocator.free(dbPath);
    }

    var db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = dbPath },
        .open_flags = .{ .write = true, .create = true },
        .threading_mode = .MultiThread,
    });
    defer db.deinit();

    try setupSchema(&db);

    // TODO: search command
    {
        // // TODO: parse from args
        // const needle = "";
        //
        // var arena = std.heap.ArenaAllocator.init(allocator);
        // defer arena.deinit();
        //
        // const links = try searchLinks(&db, arena.allocator(), needle);
        // for (links) |link| {
        //     std.log.debug("Link -> id: {s}, url: {s}", .{ link.id, link.url });
        // }
    }

    // TODO: add command
    {
        // // TODO: parse from args
        // const url = "appie://flutter-backstage";
        // try addLink(&db, url);
    }
}

fn deriveDbFilePath(allocator: std.mem.Allocator) ![]const u8 {
    const path = if (try isEnabledFromEnv(allocator, "PROD")) blk: {
        const homeDir = fromEnv(allocator, "HOME") catch @panic("Could not find $HOME environment variable");
        defer allocator.free(homeDir);

        const dbDir = try std.fs.path.join(allocator, &[_][]const u8{ homeDir, configDirName, configSubDirName });
        defer allocator.free(dbDir);

        _ = std.fs.cwd().makeDir(dbDir) catch |e| switch (e) {
            error.PathAlreadyExists => std.log.debug("Skipping config directory creation as it exists", .{}),
            else => std.debug.panic("Unhandle error: {any}", .{e}),
        };

        break :blk dbDir;
    } else ".";

    return try std.fs.path.join(allocator, &[_][]const u8{ path, dbName });
}

fn setupSchema(db: *sqlite.Db) !void {
    try db.exec("create table if not exists schema_version(version integer primary key)", .{}, .{});

    const versionRow = try db.one(usize, "select version from schema_version limit 1", .{}, .{});
    if (versionRow) |version| {
        if (schemaVersion > version) {
            // TODO: do migrations
        }
    } else {
        try db.exec("insert into schema_version(version) values(?)", .{}, .{schemaVersion});
    }

    try db.exec(
        \\ create table if not exists links (
        \\    id uuid primary key,
        \\    url text not null,
        \\    created_at timestamp default current_timestamp
        \\ )
    , .{}, .{});
}

const Link = struct {
    id: []const u8,
    url: []const u8,
};

fn searchLinks(db: *sqlite.Db, allocator: std.mem.Allocator, needle: []const u8) ![]Link {
    var stmt = try db.prepare("select id, url from links where url like ?");
    defer stmt.deinit();

    const like = try std.fmt.allocPrint(allocator, "%{s}%", .{needle});
    defer allocator.free(like);

    return stmt.all(Link, allocator, .{}, .{like});
}

fn addLink(db: *sqlite.Db, url: []const u8) !void {
    const id = uuid.v7.new();
    try db.exec("insert into links(id, url) values(?, ?)", .{}, .{ @as([36]u8, uuid.urn.serialize(id)), url });
}

fn isEnabledFromEnv(allocator: std.mem.Allocator, key: []const u8) !bool {
    const value = fromEnv(allocator, key) catch |e| switch (e) {
        error.EnvironmentVariableNotFound => return false,
        else => std.debug.panic("Unhandle error: {any}", .{e}),
    };
    defer allocator.free(value);

    return std.mem.eql(u8, value, "1");
}

fn fromEnv(allocator: std.mem.Allocator, key: []const u8) ![]const u8 {
    return try std.process.getEnvVarOwned(allocator, key);
}
