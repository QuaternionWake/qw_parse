//! This module provides functions for parsing and printing long and short
//! suffixes. It is only useful if you're writing your own parser or formatter.
const std = @import("std");
const Writer = std.Io.Writer;

/// Biggest n that can be given to shortSuffix() and longSuffix()
pub const max_suffix = 999;

/// Writes nth short suffix.
/// To get the suffix for 10^n, call with n/3 - 1.
/// Asserts n is less than or equal to `max_suffix`.
pub fn writeShortSuffix(writer: *Writer, n: u10) Writer.Error!void {
    switch (n) {
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9 => |i| {
            return writer.writeAll(short_special_cases[i]);
        },
        else => {},
    }

    std.debug.assert(n <= max_suffix);

    const hundred = short_hundreds[n / 100];
    const ten = short_tens[n / 10 % 10];
    const unit = short_units[n % 10];

    return writer.print("{s}{s}{s}", .{ unit, ten, hundred });
}

/// Parses `string` as a short suffix case-insensitevely.
/// To get the order of magnitde, add 1 to result and multiply by 3.
/// Returns `null` for unknown suffixes.
pub fn parseShortSuffix(string: []const u8) ?u10 {
    if (string.len == 0) return null;
    for (short_special_cases, 0..) |suffix, i| {
        if (std.ascii.eqlIgnoreCase(string, suffix)) {
            return @intCast(i);
        }
    }

    return parseShortUnit(string);
}

fn parseShortUnit(str: []const u8) ?u10 {
    for (short_units[1..], 1..) |unit, i| {
        if (std.ascii.startsWithIgnoreCase(str, unit)) {
            const ten_str = str[unit.len..];
            if (parseShortTen(ten_str)) |result| {
                if (result != 0) return result + @as(u10, @intCast(i));
            }
            break;
        }
    }
    return parseShortTen(str);
}

fn parseShortTen(str: []const u8) ?u10 {
    if (str.len == 0) return 0;
    for (short_tens[1..], 1..) |ten, i| {
        if (std.ascii.startsWithIgnoreCase(str, ten)) {
            const hundred_str = str[ten.len..];
            if (parseShortHundred(hundred_str)) |result| {
                return result + @as(u10, @intCast(i * 10));
            }
            break;
        }
    }
    return parseShortHundred(str);
}

fn parseShortHundred(str: []const u8) ?u10 {
    if (str.len == 0) return 0;
    for (short_hundreds[1..], 1..) |hundred, i| {
        if (std.ascii.startsWithIgnoreCase(str, hundred)) {
            if (str.len == hundred.len) {
                return @intCast(i * 100);
            }
            break;
        }
    }
    return null;
}

// As far as I can tell though the full names are standardized, the abbreviatons aren't
const short_units: [10][]const u8 = .{
    "", "U", "D", "T", "Qa", "Qi", "Sx", "Sp", "O", "N",
};

const short_tens: [10][]const u8 = .{
    "", "Dc", "Vi", "Tg", "Qd", "Qq", "Sg", "St", "Og", "Ng",
};

const short_hundreds: [10][]const u8 = .{ // holy collison avoidance
    "", "Ct", "Duc", "Trc", "Qgt", "Qigt", "Ssc", "Stg", "Octg", "Nntg",
};

const short_special_cases: [10][]const u8 = .{
    "k", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No",
};

/// Writes nth long suffix.
/// To get the suffix for 10^n, call with n/3 - 1.
/// Asserts n is less than or equal to `max_suffix`.
pub fn writeLongSuffix(writer: *Writer, n: u10) Writer.Error!void {
    switch (n) {
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9 => |i| {
            return writer.writeAll(long_special_cases[i]);
        },
        else => {},
    }

    std.debug.assert(n <= max_suffix);

    const hundred = long_hundreds[n / 100];
    const ten = long_tens[n / 10 % 10];

    const tags = if (ten.name.len != 0) ten.tags else hundred.tags;
    const unit_str = long_units[n % 10].getName(tags);

    // longest possible result is 'quattuorquinquagintaquadringentillion' (454) at 37 characters
    var buf: [64]u8 = undefined;
    var name = std.fmt.bufPrint(&buf, "{s}{s}{s}", .{ unit_str, ten.name, hundred.name }) catch unreachable;
    name.len += 5;
    @memcpy(name[name.len - 6 ..], "illion");

    return writer.writeAll(name);
}

/// Parses `string` as a long suffix case-insensitevely.
/// To get the order of magnitde, add 1 to result and multiply by 3.
/// Returns `null` for unknown suffixes.
pub fn parseLongSuffix(string: []const u8) ?u10 {
    for (long_special_cases, 0..) |suffix, i| {
        if (std.ascii.eqlIgnoreCase(string, suffix)) {
            return @intCast(i);
        }
    }

    return parseLongUnit(string);
}

fn parseLongUnit(str: []const u8) ?u10 {
    for (long_units[1..], 1..) |unit, i| {
        if (std.ascii.startsWithIgnoreCase(str, unit.name)) {
            const ten_str = str[unit.name.len..];
            if (parseLongTen(ten_str, .none, unit.tags)) |result| {
                if (result != 0) return result + @as(u10, @intCast(i));
            }
        }
        const fields = .{
            .{ .name = "name_n", .tag = .n },
            .{ .name = "name_m", .tag = .m },
            .{ .name = "name_s", .tag = .s },
            .{ .name = "name_x", .tag = .x },
        };
        inline for (fields) |field| {
            if (@field(unit, field.name)) |name| {
                if (std.ascii.startsWithIgnoreCase(str, name)) {
                    const ten_str = str[name.len..];
                    if (parseLongTen(ten_str, field.tag, .{})) |result| {
                        if (result != 0) return result + @as(u10, @intCast(i));
                    }
                }
            }
        }
    }
    return parseLongTen(str, .none, .{});
}

const WantedTag = enum { n, m, s, x, none };

fn parseLongTen(str: []const u8, comptime wanted_tag: WantedTag, forbidden_tags: NameInfo.Tags) ?u10 {
    for (long_tens[1..], 1..) |ten, i| {
        // TODO: inefficient, make better
        if (std.ascii.startsWithIgnoreCase(str, ten.name)) {
            if (wanted_tag != .none and !@field(ten.tags, @tagName(wanted_tag))) break;
            if (@as(u4, @bitCast(ten.tags)) & @as(u4, @bitCast(forbidden_tags)) != 0) break;
            const hundred_str = str[ten.name.len..];
            if (parseLongHundred(hundred_str, .none, .{})) |result| {
                return result + @as(u10, @intCast(i * 10));
            }
        }
        if (std.ascii.startsWithIgnoreCase(str, ten.name[0 .. ten.name.len - 1])) {
            const illion_str = str[ten.name.len - 1 ..];
            if (parseIllionString(illion_str)) {
                return @intCast(i * 10);
            }
        }
    }
    return parseLongHundred(str, wanted_tag, forbidden_tags);
}

fn parseLongHundred(str: []const u8, comptime wanted_tag: WantedTag, forbidden_tags: NameInfo.Tags) ?u10 {
    if (parseIllionString(str)) return 0;
    for (long_hundreds[1..], 1..) |hundred, i| {
        if (std.ascii.startsWithIgnoreCase(str, hundred.name)) {
            if (wanted_tag != .none and !@field(hundred.tags, @tagName(wanted_tag))) break;
            if (@as(u4, @bitCast(hundred.tags)) & @as(u4, @bitCast(forbidden_tags)) != 0) break;
            const illion_str = str[hundred.name.len - 1 ..];
            if (parseIllionString(illion_str)) {
                return @intCast(i * 100);
            }
        }
    }
    return null;
}

fn parseIllionString(str: []const u8) bool {
    return std.ascii.eqlIgnoreCase(str, "illion");
}

const NameInfo = struct {
    name: []const u8,
    name_n: ?[]const u8 = null,
    name_m: ?[]const u8 = null,
    name_s: ?[]const u8 = null,
    name_x: ?[]const u8 = null,
    tags: Tags = .{},

    const Tags = packed struct {
        n: bool = false,
        m: bool = false,
        s: bool = false,
        x: bool = false,
    };

    fn getName(self: NameInfo, tags: Tags) []const u8 {
        var name = self.name;
        if (tags.n) name = self.name_n orelse name;
        if (tags.m) name = self.name_m orelse name;
        if (tags.s) name = self.name_s orelse name;
        if (tags.x) name = self.name_x orelse name;
        return name;
    }
};

const long_units: [10]NameInfo = .{
    .{ .name = "" },
    .{ .name = "un" },
    .{ .name = "duo" },
    .{ .name = "tre", .name_s = "tres", .name_x = "tres", .tags = .{ .s = true, .x = true } },
    .{ .name = "quattuor" },
    .{ .name = "quinqua" },
    .{ .name = "se", .name_s = "ses", .name_x = "sex", .tags = .{ .s = true, .x = true } },
    .{ .name = "septe", .name_n = "septen", .name_m = "septem", .tags = .{ .n = true, .m = true } },
    .{ .name = "octo" },
    .{ .name = "nove", .name_n = "noven", .name_m = "novem", .tags = .{ .n = true, .m = true } },
};

const long_tens: [10]NameInfo = .{
    .{ .name = "" },
    .{ .name = "deci", .tags = .{ .n = true } },
    .{ .name = "viginti", .tags = .{ .m = true, .s = true } },
    .{ .name = "triginta", .tags = .{ .n = true, .s = true } },
    .{ .name = "quadraginta", .tags = .{ .n = true, .s = true } },
    .{ .name = "quinquaginta", .tags = .{ .n = true, .s = true } },
    .{ .name = "sexaginta", .tags = .{ .n = true } },
    .{ .name = "septuaginta", .tags = .{ .n = true } },
    .{ .name = "octoginta", .tags = .{ .m = true, .x = true } },
    .{ .name = "nonaginta" },
};

const long_hundreds: [10]NameInfo = .{
    .{ .name = "" },
    .{ .name = "centi", .tags = .{ .n = true, .x = true } },
    .{ .name = "ducenti", .tags = .{ .n = true } },
    .{ .name = "trecenti", .tags = .{ .n = true, .s = true } },
    .{ .name = "quadringenti", .tags = .{ .n = true, .s = true } },
    .{ .name = "quingenti", .tags = .{ .n = true, .s = true } },
    .{ .name = "sescenti", .tags = .{ .n = true } },
    .{ .name = "septingenti", .tags = .{ .n = true } },
    .{ .name = "octingenti", .tags = .{ .m = true, .x = true } },
    .{ .name = "nongenti" },
};

const long_special_cases: [10][]const u8 = .{
    "thousand",
    "million",
    "billion",
    "trillion",
    "quadrillion",
    "quintillion",
    "sextillion",
    "septillion",
    "octillion",
    "nonillion",
};

const t = std.testing;

test "Short suffixes" {
    const testcases = [_]struct { u10, []const u8 }{
        .{ 0, "k" },
        .{ 5, "Qi" },
        .{ 10, "Dc" },
        .{ 11, "UDc" },
        .{ 24, "QaVi" },
        .{ 100, "Ct" },
        .{ 999, "NNgNntg" }, // how very easy to read and parse at a glance
    };

    for (testcases) |case| {
        const n, const expected = case;
        var buf: [16]u8 = undefined;
        var writer: Writer = .fixed(&buf);
        try writeShortSuffix(&writer, n);
        try t.expectEqualStrings(expected, buf[0..writer.end]);
    }
}

test "Parse short suffix" {
    try t.expectEqual(0, parseShortSuffix("k"));
    try t.expectEqual(5, parseShortSuffix("Qi"));
    try t.expectEqual(10, parseShortSuffix("Dc"));
    try t.expectEqual(11, parseShortSuffix("UDc"));
    try t.expectEqual(24, parseShortSuffix("QaVi"));
    try t.expectEqual(100, parseShortSuffix("Ct"));
    try t.expectEqual(999, parseShortSuffix("NNgNntg"));
    try t.expectEqual(999, parseShortSuffix("nngnntg"));
    try t.expectEqual(999, parseShortSuffix("nNGnnTg"));

    try t.expectEqual(null, parseShortSuffix(""));
    try t.expectEqual(null, parseShortSuffix("U"));
    try t.expectEqual(null, parseShortSuffix("D"));
    try t.expectEqual(null, parseShortSuffix("O"));
    try t.expectEqual(null, parseShortSuffix("N"));
}

test "Parse short suffix exhaustive" {
    for (0..1000) |i| {
        var buf: [16]u8 = undefined;
        var writer: Writer = .fixed(&buf);
        try writeShortSuffix(&writer, @intCast(i));
        const str = buf[0..writer.end];

        try t.expectEqual(@as(u10, @intCast(i)), parseShortSuffix(str));
    }
}

test "Parse long suffix" {
    try t.expectEqual(0, parseLongSuffix("thousand"));
    try t.expectEqual(5, parseLongSuffix("quintillion"));
    try t.expectEqual(10, parseLongSuffix("decillion"));
    try t.expectEqual(11, parseLongSuffix("undecillion"));
    try t.expectEqual(24, parseLongSuffix("quattuorvigintillion"));
    try t.expectEqual(100, parseLongSuffix("centillion"));
    try t.expectEqual(999, parseLongSuffix("novenonagintanongentillion"));
    try t.expectEqual(999, parseLongSuffix("NOVENONAGINTANONGENTILLION"));
    try t.expectEqual(999, parseLongSuffix("nOvEnoNAgIntANonGeNTIlliON"));

    try t.expectEqual(null, parseLongSuffix(""));
    try t.expectEqual(null, parseLongSuffix("un"));
    try t.expectEqual(null, parseLongSuffix("quattuor"));
    try t.expectEqual(null, parseLongSuffix("unillion"));
    try t.expectEqual(null, parseLongSuffix("quattuorillion"));
}

test "Parse long suffix exhaustive" {
    for (0..1000) |i| {
        var buf: [64]u8 = undefined;
        var writer: Writer = .fixed(&buf);
        try writeLongSuffix(&writer, @intCast(i));
        const str = buf[0..writer.end];

        try t.expectEqual(@as(u10, @intCast(i)), parseLongSuffix(str));
    }
}

// *sheds tear* My most beautiful test yet
// Strings gotten from https://web.archive.org/web/20170523072248/http://home.kpn.nl/vanadovv/BignumbyN.html
test "All long suffixes" {
    const suffixes = [_][]const u8{
        "thousand",
        "million",
        "billion",
        "trillion",
        "quadrillion",
        "quintillion",
        "sextillion",
        "septillion",
        "octillion",
        "nonillion",
        "decillion",
        "undecillion",
        "duodecillion",
        "tredecillion",
        "quattuordecillion",
        "quinquadecillion",
        "sedecillion",
        "septendecillion",
        "octodecillion",
        "novendecillion",
        "vigintillion",
        "unvigintillion",
        "duovigintillion",
        "tresvigintillion",
        "quattuorvigintillion",
        "quinquavigintillion",
        "sesvigintillion",
        "septemvigintillion",
        "octovigintillion",
        "novemvigintillion",
        "trigintillion",
        "untrigintillion",
        "duotrigintillion",
        "trestrigintillion",
        "quattuortrigintillion",
        "quinquatrigintillion",
        "sestrigintillion",
        "septentrigintillion",
        "octotrigintillion",
        "noventrigintillion",
        "quadragintillion",
        "unquadragintillion",
        "duoquadragintillion",
        "tresquadragintillion",
        "quattuorquadragintillion",
        "quinquaquadragintillion",
        "sesquadragintillion",
        "septenquadragintillion",
        "octoquadragintillion",
        "novenquadragintillion",
        "quinquagintillion",
        "unquinquagintillion",
        "duoquinquagintillion",
        "tresquinquagintillion",
        "quattuorquinquagintillion",
        "quinquaquinquagintillion",
        "sesquinquagintillion",
        "septenquinquagintillion",
        "octoquinquagintillion",
        "novenquinquagintillion",
        "sexagintillion",
        "unsexagintillion",
        "duosexagintillion",
        "tresexagintillion",
        "quattuorsexagintillion",
        "quinquasexagintillion",
        "sesexagintillion",
        "septensexagintillion",
        "octosexagintillion",
        "novensexagintillion",
        "septuagintillion",
        "unseptuagintillion",
        "duoseptuagintillion",
        "treseptuagintillion",
        "quattuorseptuagintillion",
        "quinquaseptuagintillion",
        "seseptuagintillion",
        "septenseptuagintillion",
        "octoseptuagintillion",
        "novenseptuagintillion",
        "octogintillion",
        "unoctogintillion",
        "duooctogintillion",
        "tresoctogintillion",
        "quattuoroctogintillion",
        "quinquaoctogintillion",
        "sexoctogintillion",
        "septemoctogintillion",
        "octooctogintillion",
        "novemoctogintillion",
        "nonagintillion",
        "unnonagintillion",
        "duononagintillion",
        "trenonagintillion",
        "quattuornonagintillion",
        "quinquanonagintillion",
        "senonagintillion",
        "septenonagintillion",
        "octononagintillion",
        "novenonagintillion",
        "centillion",
        "uncentillion",
        "duocentillion",
        "trescentillion",
        "quattuorcentillion",
        "quinquacentillion",
        "sexcentillion",
        "septencentillion",
        "octocentillion",
        "novencentillion",
        "decicentillion",
        "undecicentillion",
        "duodecicentillion",
        "tredecicentillion",
        "quattuordecicentillion",
        "quinquadecicentillion",
        "sedecicentillion",
        "septendecicentillion",
        "octodecicentillion",
        "novendecicentillion",
        "viginticentillion",
        "unviginticentillion",
        "duoviginticentillion",
        "tresviginticentillion",
        "quattuorviginticentillion",
        "quinquaviginticentillion",
        "sesviginticentillion",
        "septemviginticentillion",
        "octoviginticentillion",
        "novemviginticentillion",
        "trigintacentillion",
        "untrigintacentillion",
        "duotrigintacentillion",
        "trestrigintacentillion",
        "quattuortrigintacentillion",
        "quinquatrigintacentillion",
        "sestrigintacentillion",
        "septentrigintacentillion",
        "octotrigintacentillion",
        "noventrigintacentillion",
        "quadragintacentillion",
        "unquadragintacentillion",
        "duoquadragintacentillion",
        "tresquadragintacentillion",
        "quattuorquadragintacentillion",
        "quinquaquadragintacentillion",
        "sesquadragintacentillion",
        "septenquadragintacentillion",
        "octoquadragintacentillion",
        "novenquadragintacentillion",
        "quinquagintacentillion",
        "unquinquagintacentillion",
        "duoquinquagintacentillion",
        "tresquinquagintacentillion",
        "quattuorquinquagintacentillion",
        "quinquaquinquagintacentillion",
        "sesquinquagintacentillion",
        "septenquinquagintacentillion",
        "octoquinquagintacentillion",
        "novenquinquagintacentillion",
        "sexagintacentillion",
        "unsexagintacentillion",
        "duosexagintacentillion",
        "tresexagintacentillion",
        "quattuorsexagintacentillion",
        "quinquasexagintacentillion",
        "sesexagintacentillion",
        "septensexagintacentillion",
        "octosexagintacentillion",
        "novensexagintacentillion",
        "septuagintacentillion",
        "unseptuagintacentillion",
        "duoseptuagintacentillion",
        "treseptuagintacentillion",
        "quattuorseptuagintacentillion",
        "quinquaseptuagintacentillion",
        "seseptuagintacentillion",
        "septenseptuagintacentillion",
        "octoseptuagintacentillion",
        "novenseptuagintacentillion",
        "octogintacentillion",
        "unoctogintacentillion",
        "duooctogintacentillion",
        "tresoctogintacentillion",
        "quattuoroctogintacentillion",
        "quinquaoctogintacentillion",
        "sexoctogintacentillion",
        "septemoctogintacentillion",
        "octooctogintacentillion",
        "novemoctogintacentillion",
        "nonagintacentillion",
        "unnonagintacentillion",
        "duononagintacentillion",
        "trenonagintacentillion",
        "quattuornonagintacentillion",
        "quinquanonagintacentillion",
        "senonagintacentillion",
        "septenonagintacentillion",
        "octononagintacentillion",
        "novenonagintacentillion",
        "ducentillion",
        "unducentillion",
        "duoducentillion",
        "treducentillion",
        "quattuorducentillion",
        "quinquaducentillion",
        "seducentillion",
        "septenducentillion",
        "octoducentillion",
        "novenducentillion",
        "deciducentillion",
        "undeciducentillion",
        "duodeciducentillion",
        "tredeciducentillion",
        "quattuordeciducentillion",
        "quinquadeciducentillion",
        "sedeciducentillion",
        "septendeciducentillion",
        "octodeciducentillion",
        "novendeciducentillion",
        "vigintiducentillion",
        "unvigintiducentillion",
        "duovigintiducentillion",
        "tresvigintiducentillion",
        "quattuorvigintiducentillion",
        "quinquavigintiducentillion",
        "sesvigintiducentillion",
        "septemvigintiducentillion",
        "octovigintiducentillion",
        "novemvigintiducentillion",
        "trigintaducentillion",
        "untrigintaducentillion",
        "duotrigintaducentillion",
        "trestrigintaducentillion",
        "quattuortrigintaducentillion",
        "quinquatrigintaducentillion",
        "sestrigintaducentillion",
        "septentrigintaducentillion",
        "octotrigintaducentillion",
        "noventrigintaducentillion",
        "quadragintaducentillion",
        "unquadragintaducentillion",
        "duoquadragintaducentillion",
        "tresquadragintaducentillion",
        "quattuorquadragintaducentillion",
        "quinquaquadragintaducentillion",
        "sesquadragintaducentillion",
        "septenquadragintaducentillion",
        "octoquadragintaducentillion",
        "novenquadragintaducentillion",
        "quinquagintaducentillion",
        "unquinquagintaducentillion",
        "duoquinquagintaducentillion",
        "tresquinquagintaducentillion",
        "quattuorquinquagintaducentillion",
        "quinquaquinquagintaducentillion",
        "sesquinquagintaducentillion",
        "septenquinquagintaducentillion",
        "octoquinquagintaducentillion",
        "novenquinquagintaducentillion",
        "sexagintaducentillion",
        "unsexagintaducentillion",
        "duosexagintaducentillion",
        "tresexagintaducentillion",
        "quattuorsexagintaducentillion",
        "quinquasexagintaducentillion",
        "sesexagintaducentillion",
        "septensexagintaducentillion",
        "octosexagintaducentillion",
        "novensexagintaducentillion",
        "septuagintaducentillion",
        "unseptuagintaducentillion",
        "duoseptuagintaducentillion",
        "treseptuagintaducentillion",
        "quattuorseptuagintaducentillion",
        "quinquaseptuagintaducentillion",
        "seseptuagintaducentillion",
        "septenseptuagintaducentillion",
        "octoseptuagintaducentillion",
        "novenseptuagintaducentillion",
        "octogintaducentillion",
        "unoctogintaducentillion",
        "duooctogintaducentillion",
        "tresoctogintaducentillion",
        "quattuoroctogintaducentillion",
        "quinquaoctogintaducentillion",
        "sexoctogintaducentillion",
        "septemoctogintaducentillion",
        "octooctogintaducentillion",
        "novemoctogintaducentillion",
        "nonagintaducentillion",
        "unnonagintaducentillion",
        "duononagintaducentillion",
        "trenonagintaducentillion",
        "quattuornonagintaducentillion",
        "quinquanonagintaducentillion",
        "senonagintaducentillion",
        "septenonagintaducentillion",
        "octononagintaducentillion",
        "novenonagintaducentillion",
        "trecentillion",
        "untrecentillion",
        "duotrecentillion",
        "trestrecentillion",
        "quattuortrecentillion",
        "quinquatrecentillion",
        "sestrecentillion",
        "septentrecentillion",
        "octotrecentillion",
        "noventrecentillion",
        "decitrecentillion",
        "undecitrecentillion",
        "duodecitrecentillion",
        "tredecitrecentillion",
        "quattuordecitrecentillion",
        "quinquadecitrecentillion",
        "sedecitrecentillion",
        "septendecitrecentillion",
        "octodecitrecentillion",
        "novendecitrecentillion",
        "vigintitrecentillion",
        "unvigintitrecentillion",
        "duovigintitrecentillion",
        "tresvigintitrecentillion",
        "quattuorvigintitrecentillion",
        "quinquavigintitrecentillion",
        "sesvigintitrecentillion",
        "septemvigintitrecentillion",
        "octovigintitrecentillion",
        "novemvigintitrecentillion",
        "trigintatrecentillion",
        "untrigintatrecentillion",
        "duotrigintatrecentillion",
        "trestrigintatrecentillion",
        "quattuortrigintatrecentillion",
        "quinquatrigintatrecentillion",
        "sestrigintatrecentillion",
        "septentrigintatrecentillion",
        "octotrigintatrecentillion",
        "noventrigintatrecentillion",
        "quadragintatrecentillion",
        "unquadragintatrecentillion",
        "duoquadragintatrecentillion",
        "tresquadragintatrecentillion",
        "quattuorquadragintatrecentillion",
        "quinquaquadragintatrecentillion",
        "sesquadragintatrecentillion",
        "septenquadragintatrecentillion",
        "octoquadragintatrecentillion",
        "novenquadragintatrecentillion",
        "quinquagintatrecentillion",
        "unquinquagintatrecentillion",
        "duoquinquagintatrecentillion",
        "tresquinquagintatrecentillion",
        "quattuorquinquagintatrecentillion",
        "quinquaquinquagintatrecentillion",
        "sesquinquagintatrecentillion",
        "septenquinquagintatrecentillion",
        "octoquinquagintatrecentillion",
        "novenquinquagintatrecentillion",
        "sexagintatrecentillion",
        "unsexagintatrecentillion",
        "duosexagintatrecentillion",
        "tresexagintatrecentillion",
        "quattuorsexagintatrecentillion",
        "quinquasexagintatrecentillion",
        "sesexagintatrecentillion",
        "septensexagintatrecentillion",
        "octosexagintatrecentillion",
        "novensexagintatrecentillion",
        "septuagintatrecentillion",
        "unseptuagintatrecentillion",
        "duoseptuagintatrecentillion",
        "treseptuagintatrecentillion",
        "quattuorseptuagintatrecentillion",
        "quinquaseptuagintatrecentillion",
        "seseptuagintatrecentillion",
        "septenseptuagintatrecentillion",
        "octoseptuagintatrecentillion",
        "novenseptuagintatrecentillion",
        "octogintatrecentillion",
        "unoctogintatrecentillion",
        "duooctogintatrecentillion",
        "tresoctogintatrecentillion",
        "quattuoroctogintatrecentillion",
        "quinquaoctogintatrecentillion",
        "sexoctogintatrecentillion",
        "septemoctogintatrecentillion",
        "octooctogintatrecentillion",
        "novemoctogintatrecentillion",
        "nonagintatrecentillion",
        "unnonagintatrecentillion",
        "duononagintatrecentillion",
        "trenonagintatrecentillion",
        "quattuornonagintatrecentillion",
        "quinquanonagintatrecentillion",
        "senonagintatrecentillion",
        "septenonagintatrecentillion",
        "octononagintatrecentillion",
        "novenonagintatrecentillion",
        "quadringentillion",
        "unquadringentillion",
        "duoquadringentillion",
        "tresquadringentillion",
        "quattuorquadringentillion",
        "quinquaquadringentillion",
        "sesquadringentillion",
        "septenquadringentillion",
        "octoquadringentillion",
        "novenquadringentillion",
        "deciquadringentillion",
        "undeciquadringentillion",
        "duodeciquadringentillion",
        "tredeciquadringentillion",
        "quattuordeciquadringentillion",
        "quinquadeciquadringentillion",
        "sedeciquadringentillion",
        "septendeciquadringentillion",
        "octodeciquadringentillion",
        "novendeciquadringentillion",
        "vigintiquadringentillion",
        "unvigintiquadringentillion",
        "duovigintiquadringentillion",
        "tresvigintiquadringentillion",
        "quattuorvigintiquadringentillion",
        "quinquavigintiquadringentillion",
        "sesvigintiquadringentillion",
        "septemvigintiquadringentillion",
        "octovigintiquadringentillion",
        "novemvigintiquadringentillion",
        "trigintaquadringentillion",
        "untrigintaquadringentillion",
        "duotrigintaquadringentillion",
        "trestrigintaquadringentillion",
        "quattuortrigintaquadringentillion",
        "quinquatrigintaquadringentillion",
        "sestrigintaquadringentillion",
        "septentrigintaquadringentillion",
        "octotrigintaquadringentillion",
        "noventrigintaquadringentillion",
        "quadragintaquadringentillion",
        "unquadragintaquadringentillion",
        "duoquadragintaquadringentillion",
        "tresquadragintaquadringentillion",
        "quattuorquadragintaquadringentillion",
        "quinquaquadragintaquadringentillion",
        "sesquadragintaquadringentillion",
        "septenquadragintaquadringentillion",
        "octoquadragintaquadringentillion",
        "novenquadragintaquadringentillion",
        "quinquagintaquadringentillion",
        "unquinquagintaquadringentillion",
        "duoquinquagintaquadringentillion",
        "tresquinquagintaquadringentillion",
        "quattuorquinquagintaquadringentillion",
        "quinquaquinquagintaquadringentillion",
        "sesquinquagintaquadringentillion",
        "septenquinquagintaquadringentillion",
        "octoquinquagintaquadringentillion",
        "novenquinquagintaquadringentillion",
        "sexagintaquadringentillion",
        "unsexagintaquadringentillion",
        "duosexagintaquadringentillion",
        "tresexagintaquadringentillion",
        "quattuorsexagintaquadringentillion",
        "quinquasexagintaquadringentillion",
        "sesexagintaquadringentillion",
        "septensexagintaquadringentillion",
        "octosexagintaquadringentillion",
        "novensexagintaquadringentillion",
        "septuagintaquadringentillion",
        "unseptuagintaquadringentillion",
        "duoseptuagintaquadringentillion",
        "treseptuagintaquadringentillion",
        "quattuorseptuagintaquadringentillion",
        "quinquaseptuagintaquadringentillion",
        "seseptuagintaquadringentillion",
        "septenseptuagintaquadringentillion",
        "octoseptuagintaquadringentillion",
        "novenseptuagintaquadringentillion",
        "octogintaquadringentillion",
        "unoctogintaquadringentillion",
        "duooctogintaquadringentillion",
        "tresoctogintaquadringentillion",
        "quattuoroctogintaquadringentillion",
        "quinquaoctogintaquadringentillion",
        "sexoctogintaquadringentillion",
        "septemoctogintaquadringentillion",
        "octooctogintaquadringentillion",
        "novemoctogintaquadringentillion",
        "nonagintaquadringentillion",
        "unnonagintaquadringentillion",
        "duononagintaquadringentillion",
        "trenonagintaquadringentillion",
        "quattuornonagintaquadringentillion",
        "quinquanonagintaquadringentillion",
        "senonagintaquadringentillion",
        "septenonagintaquadringentillion",
        "octononagintaquadringentillion",
        "novenonagintaquadringentillion",
        "quingentillion",
        "unquingentillion",
        "duoquingentillion",
        "tresquingentillion",
        "quattuorquingentillion",
        "quinquaquingentillion",
        "sesquingentillion",
        "septenquingentillion",
        "octoquingentillion",
        "novenquingentillion",
        "deciquingentillion",
        "undeciquingentillion",
        "duodeciquingentillion",
        "tredeciquingentillion",
        "quattuordeciquingentillion",
        "quinquadeciquingentillion",
        "sedeciquingentillion",
        "septendeciquingentillion",
        "octodeciquingentillion",
        "novendeciquingentillion",
        "vigintiquingentillion",
        "unvigintiquingentillion",
        "duovigintiquingentillion",
        "tresvigintiquingentillion",
        "quattuorvigintiquingentillion",
        "quinquavigintiquingentillion",
        "sesvigintiquingentillion",
        "septemvigintiquingentillion",
        "octovigintiquingentillion",
        "novemvigintiquingentillion",
        "trigintaquingentillion",
        "untrigintaquingentillion",
        "duotrigintaquingentillion",
        "trestrigintaquingentillion",
        "quattuortrigintaquingentillion",
        "quinquatrigintaquingentillion",
        "sestrigintaquingentillion",
        "septentrigintaquingentillion",
        "octotrigintaquingentillion",
        "noventrigintaquingentillion",
        "quadragintaquingentillion",
        "unquadragintaquingentillion",
        "duoquadragintaquingentillion",
        "tresquadragintaquingentillion",
        "quattuorquadragintaquingentillion",
        "quinquaquadragintaquingentillion",
        "sesquadragintaquingentillion",
        "septenquadragintaquingentillion",
        "octoquadragintaquingentillion",
        "novenquadragintaquingentillion",
        "quinquagintaquingentillion",
        "unquinquagintaquingentillion",
        "duoquinquagintaquingentillion",
        "tresquinquagintaquingentillion",
        "quattuorquinquagintaquingentillion",
        "quinquaquinquagintaquingentillion",
        "sesquinquagintaquingentillion",
        "septenquinquagintaquingentillion",
        "octoquinquagintaquingentillion",
        "novenquinquagintaquingentillion",
        "sexagintaquingentillion",
        "unsexagintaquingentillion",
        "duosexagintaquingentillion",
        "tresexagintaquingentillion",
        "quattuorsexagintaquingentillion",
        "quinquasexagintaquingentillion",
        "sesexagintaquingentillion",
        "septensexagintaquingentillion",
        "octosexagintaquingentillion",
        "novensexagintaquingentillion",
        "septuagintaquingentillion",
        "unseptuagintaquingentillion",
        "duoseptuagintaquingentillion",
        "treseptuagintaquingentillion",
        "quattuorseptuagintaquingentillion",
        "quinquaseptuagintaquingentillion",
        "seseptuagintaquingentillion",
        "septenseptuagintaquingentillion",
        "octoseptuagintaquingentillion",
        "novenseptuagintaquingentillion",
        "octogintaquingentillion",
        "unoctogintaquingentillion",
        "duooctogintaquingentillion",
        "tresoctogintaquingentillion",
        "quattuoroctogintaquingentillion",
        "quinquaoctogintaquingentillion",
        "sexoctogintaquingentillion",
        "septemoctogintaquingentillion",
        "octooctogintaquingentillion",
        "novemoctogintaquingentillion",
        "nonagintaquingentillion",
        "unnonagintaquingentillion",
        "duononagintaquingentillion",
        "trenonagintaquingentillion",
        "quattuornonagintaquingentillion",
        "quinquanonagintaquingentillion",
        "senonagintaquingentillion",
        "septenonagintaquingentillion",
        "octononagintaquingentillion",
        "novenonagintaquingentillion",
        "sescentillion",
        "unsescentillion",
        "duosescentillion",
        "tresescentillion",
        "quattuorsescentillion",
        "quinquasescentillion",
        "sesescentillion",
        "septensescentillion",
        "octosescentillion",
        "novensescentillion",
        "decisescentillion",
        "undecisescentillion",
        "duodecisescentillion",
        "tredecisescentillion",
        "quattuordecisescentillion",
        "quinquadecisescentillion",
        "sedecisescentillion",
        "septendecisescentillion",
        "octodecisescentillion",
        "novendecisescentillion",
        "vigintisescentillion",
        "unvigintisescentillion",
        "duovigintisescentillion",
        "tresvigintisescentillion",
        "quattuorvigintisescentillion",
        "quinquavigintisescentillion",
        "sesvigintisescentillion",
        "septemvigintisescentillion",
        "octovigintisescentillion",
        "novemvigintisescentillion",
        "trigintasescentillion",
        "untrigintasescentillion",
        "duotrigintasescentillion",
        "trestrigintasescentillion",
        "quattuortrigintasescentillion",
        "quinquatrigintasescentillion",
        "sestrigintasescentillion",
        "septentrigintasescentillion",
        "octotrigintasescentillion",
        "noventrigintasescentillion",
        "quadragintasescentillion",
        "unquadragintasescentillion",
        "duoquadragintasescentillion",
        "tresquadragintasescentillion",
        "quattuorquadragintasescentillion",
        "quinquaquadragintasescentillion",
        "sesquadragintasescentillion",
        "septenquadragintasescentillion",
        "octoquadragintasescentillion",
        "novenquadragintasescentillion",
        "quinquagintasescentillion",
        "unquinquagintasescentillion",
        "duoquinquagintasescentillion",
        "tresquinquagintasescentillion",
        "quattuorquinquagintasescentillion",
        "quinquaquinquagintasescentillion",
        "sesquinquagintasescentillion",
        "septenquinquagintasescentillion",
        "octoquinquagintasescentillion",
        "novenquinquagintasescentillion",
        "sexagintasescentillion",
        "unsexagintasescentillion",
        "duosexagintasescentillion",
        "tresexagintasescentillion",
        "quattuorsexagintasescentillion",
        "quinquasexagintasescentillion",
        "sesexagintasescentillion",
        "septensexagintasescentillion",
        "octosexagintasescentillion",
        "novensexagintasescentillion",
        "septuagintasescentillion",
        "unseptuagintasescentillion",
        "duoseptuagintasescentillion",
        "treseptuagintasescentillion",
        "quattuorseptuagintasescentillion",
        "quinquaseptuagintasescentillion",
        "seseptuagintasescentillion",
        "septenseptuagintasescentillion",
        "octoseptuagintasescentillion",
        "novenseptuagintasescentillion",
        "octogintasescentillion",
        "unoctogintasescentillion",
        "duooctogintasescentillion",
        "tresoctogintasescentillion",
        "quattuoroctogintasescentillion",
        "quinquaoctogintasescentillion",
        "sexoctogintasescentillion",
        "septemoctogintasescentillion",
        "octooctogintasescentillion",
        "novemoctogintasescentillion",
        "nonagintasescentillion",
        "unnonagintasescentillion",
        "duononagintasescentillion",
        "trenonagintasescentillion",
        "quattuornonagintasescentillion",
        "quinquanonagintasescentillion",
        "senonagintasescentillion",
        "septenonagintasescentillion",
        "octononagintasescentillion",
        "novenonagintasescentillion",
        "septingentillion",
        "unseptingentillion",
        "duoseptingentillion",
        "treseptingentillion",
        "quattuorseptingentillion",
        "quinquaseptingentillion",
        "seseptingentillion",
        "septenseptingentillion",
        "octoseptingentillion",
        "novenseptingentillion",
        "deciseptingentillion",
        "undeciseptingentillion",
        "duodeciseptingentillion",
        "tredeciseptingentillion",
        "quattuordeciseptingentillion",
        "quinquadeciseptingentillion",
        "sedeciseptingentillion",
        "septendeciseptingentillion",
        "octodeciseptingentillion",
        "novendeciseptingentillion",
        "vigintiseptingentillion",
        "unvigintiseptingentillion",
        "duovigintiseptingentillion",
        "tresvigintiseptingentillion",
        "quattuorvigintiseptingentillion",
        "quinquavigintiseptingentillion",
        "sesvigintiseptingentillion",
        "septemvigintiseptingentillion",
        "octovigintiseptingentillion",
        "novemvigintiseptingentillion",
        "trigintaseptingentillion",
        "untrigintaseptingentillion",
        "duotrigintaseptingentillion",
        "trestrigintaseptingentillion",
        "quattuortrigintaseptingentillion",
        "quinquatrigintaseptingentillion",
        "sestrigintaseptingentillion",
        "septentrigintaseptingentillion",
        "octotrigintaseptingentillion",
        "noventrigintaseptingentillion",
        "quadragintaseptingentillion",
        "unquadragintaseptingentillion",
        "duoquadragintaseptingentillion",
        "tresquadragintaseptingentillion",
        "quattuorquadragintaseptingentillion",
        "quinquaquadragintaseptingentillion",
        "sesquadragintaseptingentillion",
        "septenquadragintaseptingentillion",
        "octoquadragintaseptingentillion",
        "novenquadragintaseptingentillion",
        "quinquagintaseptingentillion",
        "unquinquagintaseptingentillion",
        "duoquinquagintaseptingentillion",
        "tresquinquagintaseptingentillion",
        "quattuorquinquagintaseptingentillion",
        "quinquaquinquagintaseptingentillion",
        "sesquinquagintaseptingentillion",
        "septenquinquagintaseptingentillion",
        "octoquinquagintaseptingentillion",
        "novenquinquagintaseptingentillion",
        "sexagintaseptingentillion",
        "unsexagintaseptingentillion",
        "duosexagintaseptingentillion",
        "tresexagintaseptingentillion",
        "quattuorsexagintaseptingentillion",
        "quinquasexagintaseptingentillion",
        "sesexagintaseptingentillion",
        "septensexagintaseptingentillion",
        "octosexagintaseptingentillion",
        "novensexagintaseptingentillion",
        "septuagintaseptingentillion",
        "unseptuagintaseptingentillion",
        "duoseptuagintaseptingentillion",
        "treseptuagintaseptingentillion",
        "quattuorseptuagintaseptingentillion",
        "quinquaseptuagintaseptingentillion",
        "seseptuagintaseptingentillion",
        "septenseptuagintaseptingentillion",
        "octoseptuagintaseptingentillion",
        "novenseptuagintaseptingentillion",
        "octogintaseptingentillion",
        "unoctogintaseptingentillion",
        "duooctogintaseptingentillion",
        "tresoctogintaseptingentillion",
        "quattuoroctogintaseptingentillion",
        "quinquaoctogintaseptingentillion",
        "sexoctogintaseptingentillion",
        "septemoctogintaseptingentillion",
        "octooctogintaseptingentillion",
        "novemoctogintaseptingentillion",
        "nonagintaseptingentillion",
        "unnonagintaseptingentillion",
        "duononagintaseptingentillion",
        "trenonagintaseptingentillion",
        "quattuornonagintaseptingentillion",
        "quinquanonagintaseptingentillion",
        "senonagintaseptingentillion",
        "septenonagintaseptingentillion",
        "octononagintaseptingentillion",
        "novenonagintaseptingentillion",
        "octingentillion",
        "unoctingentillion",
        "duooctingentillion",
        "tresoctingentillion",
        "quattuoroctingentillion",
        "quinquaoctingentillion",
        "sexoctingentillion",
        "septemoctingentillion",
        "octooctingentillion",
        "novemoctingentillion",
        "decioctingentillion",
        "undecioctingentillion",
        "duodecioctingentillion",
        "tredecioctingentillion",
        "quattuordecioctingentillion",
        "quinquadecioctingentillion",
        "sedecioctingentillion",
        "septendecioctingentillion",
        "octodecioctingentillion",
        "novendecioctingentillion",
        "vigintioctingentillion",
        "unvigintioctingentillion",
        "duovigintioctingentillion",
        "tresvigintioctingentillion",
        "quattuorvigintioctingentillion",
        "quinquavigintioctingentillion",
        "sesvigintioctingentillion",
        "septemvigintioctingentillion",
        "octovigintioctingentillion",
        "novemvigintioctingentillion",
        "trigintaoctingentillion",
        "untrigintaoctingentillion",
        "duotrigintaoctingentillion",
        "trestrigintaoctingentillion",
        "quattuortrigintaoctingentillion",
        "quinquatrigintaoctingentillion",
        "sestrigintaoctingentillion",
        "septentrigintaoctingentillion",
        "octotrigintaoctingentillion",
        "noventrigintaoctingentillion",
        "quadragintaoctingentillion",
        "unquadragintaoctingentillion",
        "duoquadragintaoctingentillion",
        "tresquadragintaoctingentillion",
        "quattuorquadragintaoctingentillion",
        "quinquaquadragintaoctingentillion",
        "sesquadragintaoctingentillion",
        "septenquadragintaoctingentillion",
        "octoquadragintaoctingentillion",
        "novenquadragintaoctingentillion",
        "quinquagintaoctingentillion",
        "unquinquagintaoctingentillion",
        "duoquinquagintaoctingentillion",
        "tresquinquagintaoctingentillion",
        "quattuorquinquagintaoctingentillion",
        "quinquaquinquagintaoctingentillion",
        "sesquinquagintaoctingentillion",
        "septenquinquagintaoctingentillion",
        "octoquinquagintaoctingentillion",
        "novenquinquagintaoctingentillion",
        "sexagintaoctingentillion",
        "unsexagintaoctingentillion",
        "duosexagintaoctingentillion",
        "tresexagintaoctingentillion",
        "quattuorsexagintaoctingentillion",
        "quinquasexagintaoctingentillion",
        "sesexagintaoctingentillion",
        "septensexagintaoctingentillion",
        "octosexagintaoctingentillion",
        "novensexagintaoctingentillion",
        "septuagintaoctingentillion",
        "unseptuagintaoctingentillion",
        "duoseptuagintaoctingentillion",
        "treseptuagintaoctingentillion",
        "quattuorseptuagintaoctingentillion",
        "quinquaseptuagintaoctingentillion",
        "seseptuagintaoctingentillion",
        "septenseptuagintaoctingentillion",
        "octoseptuagintaoctingentillion",
        "novenseptuagintaoctingentillion",
        "octogintaoctingentillion",
        "unoctogintaoctingentillion",
        "duooctogintaoctingentillion",
        "tresoctogintaoctingentillion",
        "quattuoroctogintaoctingentillion",
        "quinquaoctogintaoctingentillion",
        "sexoctogintaoctingentillion",
        "septemoctogintaoctingentillion",
        "octooctogintaoctingentillion",
        "novemoctogintaoctingentillion",
        "nonagintaoctingentillion",
        "unnonagintaoctingentillion",
        "duononagintaoctingentillion",
        "trenonagintaoctingentillion",
        "quattuornonagintaoctingentillion",
        "quinquanonagintaoctingentillion",
        "senonagintaoctingentillion",
        "septenonagintaoctingentillion",
        "octononagintaoctingentillion",
        "novenonagintaoctingentillion",
        "nongentillion",
        "unnongentillion",
        "duonongentillion",
        "trenongentillion",
        "quattuornongentillion",
        "quinquanongentillion",
        "senongentillion",
        "septenongentillion",
        "octonongentillion",
        "novenongentillion",
        "decinongentillion",
        "undecinongentillion",
        "duodecinongentillion",
        "tredecinongentillion",
        "quattuordecinongentillion",
        "quinquadecinongentillion",
        "sedecinongentillion",
        "septendecinongentillion",
        "octodecinongentillion",
        "novendecinongentillion",
        "vigintinongentillion",
        "unvigintinongentillion",
        "duovigintinongentillion",
        "tresvigintinongentillion",
        "quattuorvigintinongentillion",
        "quinquavigintinongentillion",
        "sesvigintinongentillion",
        "septemvigintinongentillion",
        "octovigintinongentillion",
        "novemvigintinongentillion",
        "trigintanongentillion",
        "untrigintanongentillion",
        "duotrigintanongentillion",
        "trestrigintanongentillion",
        "quattuortrigintanongentillion",
        "quinquatrigintanongentillion",
        "sestrigintanongentillion",
        "septentrigintanongentillion",
        "octotrigintanongentillion",
        "noventrigintanongentillion",
        "quadragintanongentillion",
        "unquadragintanongentillion",
        "duoquadragintanongentillion",
        "tresquadragintanongentillion",
        "quattuorquadragintanongentillion",
        "quinquaquadragintanongentillion",
        "sesquadragintanongentillion",
        "septenquadragintanongentillion",
        "octoquadragintanongentillion",
        "novenquadragintanongentillion",
        "quinquagintanongentillion",
        "unquinquagintanongentillion",
        "duoquinquagintanongentillion",
        "tresquinquagintanongentillion",
        "quattuorquinquagintanongentillion",
        "quinquaquinquagintanongentillion",
        "sesquinquagintanongentillion",
        "septenquinquagintanongentillion",
        "octoquinquagintanongentillion",
        "novenquinquagintanongentillion",
        "sexagintanongentillion",
        "unsexagintanongentillion",
        "duosexagintanongentillion",
        "tresexagintanongentillion",
        "quattuorsexagintanongentillion",
        "quinquasexagintanongentillion",
        "sesexagintanongentillion",
        "septensexagintanongentillion",
        "octosexagintanongentillion",
        "novensexagintanongentillion",
        "septuagintanongentillion",
        "unseptuagintanongentillion",
        "duoseptuagintanongentillion",
        "treseptuagintanongentillion",
        "quattuorseptuagintanongentillion",
        "quinquaseptuagintanongentillion",
        "seseptuagintanongentillion",
        "septenseptuagintanongentillion",
        "octoseptuagintanongentillion",
        "novenseptuagintanongentillion",
        "octogintanongentillion",
        "unoctogintanongentillion",
        "duooctogintanongentillion",
        "tresoctogintanongentillion",
        "quattuoroctogintanongentillion",
        "quinquaoctogintanongentillion",
        "sexoctogintanongentillion",
        "septemoctogintanongentillion",
        "octooctogintanongentillion",
        "novemoctogintanongentillion",
        "nonagintanongentillion",
        "unnonagintanongentillion",
        "duononagintanongentillion",
        "trenonagintanongentillion",
        "quattuornonagintanongentillion",
        "quinquanonagintanongentillion",
        "senonagintanongentillion",
        "septenonagintanongentillion",
        "octononagintanongentillion",
        "novenonagintanongentillion",
    };

    for (suffixes, 0..) |expected, i| {
        var buf: [64]u8 = undefined;
        var writer: Writer = .fixed(&buf);
        try writeLongSuffix(&writer, @intCast(i));
        try t.expectEqualStrings(expected, buf[0..writer.end]);
    }
}
