const std = @import("std");
const mem = std.mem;
const ascii = std.ascii;
const fmt = std.fmt;
const math = std.math;

const suffixes = @import("suffixes");

const ParseIntError = error{
    InvalidCharacter,
    Overflow,
    Underflow,
};

/// Parses `string` as a base 10 integer of type `T`.
/// Numbers can be written with a decimal dot and a suffix denoting their order of
/// magnitude.
///
/// Three types of suffixes can be used:
///  * Short suffixes (e.g. "1k", "2M", "3Qa")
///  * Long suffixes (e.g. "1 thousand", "2 million", "3 quadrillion")
///  * E-suffixes (scientific/engineering suffixes, e.g "1e3, 2e6, 3e15")
///
/// All the suffixes are case insensetive. Short and long suffixes allow whitespace
/// between them and the number, e-suffixes do not.
pub fn parseInt(T: type, string: []const u8) ParseIntError!T {
    const type_info = switch (@typeInfo(T)) {
        .int => |info| info,
        else => @compileError("found type " ++ @typeName(T) ++ ", parseInt only supports integers"),
    };
    const TempT = @Int(type_info.signedness, @max(type_info.bits, 64));

    // Break up the string into more manageble parts
    const chunks, const consumed = try intChunks(string);
    // Check that we consumed the whole string
    if (consumed != string.len) return error.InvalidCharacter;

    // Actualy parse the string into a number
    const number = switch (chunks.sign) {
        .pos => try parseIntWithDecimalPoint(TempT, chunks.number, .pos, @intFromEnum(chunks.oom)),
        .neg => try parseIntWithDecimalPoint(TempT, chunks.number, .neg, @intFromEnum(chunks.oom)),
    };

    const err = switch (chunks.sign) {
        .pos => error.Overflow,
        .neg => error.Underflow,
    };
    // Downcast (if T was less than 64 bits)
    return math.cast(T, number) orelse err;
}

const Sign = enum { pos, neg };
const OrderOfMagnitude = enum(i64) {
    pos_inf = math.maxInt(i64),
    neg_inf = math.minInt(i64),
    _,
};

const IntChunks = struct {
    number: []const u8,

    sign: Sign,
    oom: OrderOfMagnitude,
};

pub fn intChunks(string_: []const u8) ParseIntError!struct { IntChunks, usize } {
    var string = string_;

    const signs_end = mem.findNone(u8, string, "+-") orelse return error.InvalidCharacter;
    const signs_str = string[0..signs_end];
    const negative = mem.countScalar(u8, signs_str, '-') % 2 == 1;
    const sign: Sign = if (negative) .neg else .pos;
    string = string[signs_end..];

    const num_end = mem.findNone(u8, string, digits ++ ".") orelse string.len;
    const number = string[0..num_end];
    string = string[num_end..];

    // We index into string in the if below so first make sure we even can do that
    if (string.len == 0) {
        return .{ .{
            .number = number,
            .sign = sign,
            .oom = @enumFromInt(0),
        }, string.ptr - string_.ptr };
    }

    // Consume e-suffix and return
    if (string[0] == 'e' or string[0] == 'E') {
        string = string[1..];
        if (string.len == 0) return error.InvalidCharacter;
        const suffix_sign: Sign, const start_idx: usize = switch (string[0]) {
            '+' => .{ .pos, 1 },
            '-' => .{ .neg, 1 },
            else => .{ .pos, 0 },
        };
        const suffix_end = mem.findNonePos(u8, string, start_idx, digits) orelse string.len;
        const oom: OrderOfMagnitude =
            @enumFromInt(fmt.parseInt(i64, string[0..suffix_end], 10) catch |err| switch (err) {
                error.Overflow => switch (suffix_sign) {
                    .pos => @intFromEnum(OrderOfMagnitude.pos_inf),
                    .neg => @intFromEnum(OrderOfMagnitude.neg_inf),
                },
                error.InvalidCharacter => return err,
            });
        string = string[suffix_end..];
        return .{ .{
            .number = number,
            .sign = sign,
            .oom = oom,
        }, string.ptr - string_.ptr };
    }

    // Consume long/short suffix and return
    if (mem.findNone(u8, string, allowed_whitespace)) |suffix_start| {
        const suffix_str = string[suffix_start..];
        const suffix_info = parseSuffix(suffix_str);
        string = string[suffix_start + suffix_info.consumed ..];
        return .{ .{
            .number = number,
            .sign = sign,
            .oom = @enumFromInt(suffix_info.oom),
        }, string.ptr - string_.ptr };
    }

    return .{ .{
        .number = number,
        .sign = sign,
        .oom = @enumFromInt(0),
    }, string.ptr - string_.ptr };
}

/// Parses `string` as a number of type `T` with sign `sign`. The string can
/// contain a decimal point, which in combination with `oom` determines how much of
/// the number will get parsed. If the length to be parsed is greater than the
/// length of the string, the function behaves as if the string was padded with
/// zeros to the right.
///
/// Asserts `string` is made up exclusively of decimal digits and points, and
/// returns an error if there is more than one decimal point.
///
/// See the test below for examples.
pub fn parseIntWithDecimalPoint(T: type, string: []const u8, comptime sign: Sign, oom: i64) ParseIntError!T {
    // Deal with numberless strings
    if (string.len == 0) return error.InvalidCharacter;
    if (string.len == 1 and string[0] == '.') return error.InvalidCharacter;

    const dot_idx = mem.findScalar(u8, string, '.') orelse string.len;
    // Make sure there is at most one '.'
    if (dot_idx != string.len and mem.findScalar(u8, string[dot_idx + 1 ..], '.') != null) {
        return error.InvalidCharacter;
    }
    const cutoff = math.lossyCast(usize, @as(i64, @intCast(dot_idx)) +| oom);

    const acc, const err = switch (sign) {
        .pos => .{ math.add, error.Overflow },
        .neg => .{ math.sub, error.Underflow },
    };

    var result: T = 0;
    var consumed_digits: usize = 0;
    for (string) |char| {
        if (consumed_digits == cutoff) break;
        const digit = switch (char) {
            '0'...'9' => char - '0',
            '.' => continue,
            // This function should only ever receive strings made of decimal digits and dots
            else => unreachable,
        };
        result = math.mul(T, result, 10) catch return err;
        result = acc(T, result, digit) catch return err;

        // Probably safe to assume a string isn't gonna be bigger than a usize
        consumed_digits += 1;
    } else {
        if (result == 0) return 0;

        // Cant underflow as consumed digits is at most equal to cuoff
        const remaining = cutoff - consumed_digits;
        const remaining_t = math.cast(T, remaining) orelse return err;
        const multiplier = math.powi(T, 10, remaining_t) catch return err;
        result = math.mul(T, result, multiplier) catch return err;
    }

    return result;
}

test "parseIntWithDecimalPoint" {
    // Basic parsing
    try t.expectEqual(123, parseIntWithDecimalPoint(i32, "123", .pos, 0));
    try t.expectEqual(-123, parseIntWithDecimalPoint(i32, "123", .neg, 0));
    // Parsing with decimal point and oom
    try t.expectEqual(123, parseIntWithDecimalPoint(i32, "123.", .pos, 0));
    try t.expectEqual(123_000, parseIntWithDecimalPoint(i32, "123.", .pos, 3));
    try t.expectEqual(123_000, parseIntWithDecimalPoint(i32, "123", .pos, 3));
    // Negative oom
    try t.expectEqual(12, parseIntWithDecimalPoint(i32, "123", .pos, -1));
    try t.expectEqual(0, parseIntWithDecimalPoint(i32, "123", .pos, -3));
    try t.expectEqual(0, parseIntWithDecimalPoint(i32, "123", .pos, -10));
    // Leading dot
    try t.expectEqual(0, parseIntWithDecimalPoint(i32, ".123", .pos, 0));
    try t.expectEqual(0, parseIntWithDecimalPoint(i32, ".123", .pos, -1));
    try t.expectEqual(123, parseIntWithDecimalPoint(i32, ".123", .pos, 3));
    try t.expectEqual(123_000, parseIntWithDecimalPoint(i32, ".123", .pos, 6));
    // More dot and oom shenanigans
    try t.expectEqual(123, parseIntWithDecimalPoint(i32, "123.456", .pos, 0));
    try t.expectEqual(12345, parseIntWithDecimalPoint(i32, "123.456", .pos, 2));
    try t.expectEqual(123_456_000, parseIntWithDecimalPoint(i32, "123.456", .pos, 6));
    try t.expectEqual(1, parseIntWithDecimalPoint(i32, "123.456", .pos, -2));
    try t.expectEqual(0, parseIntWithDecimalPoint(i32, "123.456", .pos, -3));
    try t.expectEqual(0, parseIntWithDecimalPoint(i32, "123.456", .pos, -10));
    // Leading and trailing zeros
    try t.expectEqual(123, parseIntWithDecimalPoint(i32, "000000000000123.456000000000000", .pos, 0));
    // 0 with oom that would overflow T
    try t.expectEqual(0, parseIntWithDecimalPoint(i32, "0", .pos, 999));

    // Overflow and underflow
    try t.expectError(error.Overflow, parseIntWithDecimalPoint(i32, "123", .pos, 999));
    try t.expectError(error.Underflow, parseIntWithDecimalPoint(i32, "123", .neg, 999));
    // Multiple dots
    try t.expectError(error.InvalidCharacter, parseIntWithDecimalPoint(i32, "123.4.56", .pos, 0));
    try t.expectError(error.InvalidCharacter, parseIntWithDecimalPoint(i32, "123.456.", .pos, 0));
    try t.expectError(error.InvalidCharacter, parseIntWithDecimalPoint(i32, ".123.", .pos, 0));
    try t.expectError(error.InvalidCharacter, parseIntWithDecimalPoint(i32, "123..", .pos, 0));
    // No number
    try t.expectError(error.InvalidCharacter, parseIntWithDecimalPoint(i32, "", .pos, 0));
    try t.expectError(error.InvalidCharacter, parseIntWithDecimalPoint(i32, ".", .pos, 0));
    try t.expectError(error.InvalidCharacter, parseIntWithDecimalPoint(i32, "..", .pos, 0));
}

fn parseSuffix(string_: []const u8) struct { oom: i64, consumed: usize } {
    const suffix_end = mem.findNone(u8, string_, ascii.letters) orelse string_.len;
    const string = string_[0..suffix_end];

    // i64 to prevent panic when multiplying by 3 below would overflow a u10
    const n: i64 =
        suffixes.parseShortSuffix(string) orelse
        suffixes.parseLongSuffix(string) orelse
        return .{ .oom = 0, .consumed = 0 };
    return .{ .oom = @intCast(n * 3 + 3), .consumed = suffix_end };
}

// Still needed for parseFloat
fn parseSuffix_old(string: []const u8) !u64 {
    const n =
        suffixes.parseShortSuffix(string) orelse
        suffixes.parseLongSuffix(string) orelse
        return error.UnknownSuffix;
    return @intCast(n * 3 + 3);
}

const allowed_whitespace = " \t";
const digits = "0123456789";

const t = std.testing;

test "Int: Basic parsing" {
    try t.expectEqual(123, parseInt(i32, "123"));
    try t.expectEqual(123, parseInt(i32, "+123"));
    try t.expectEqual(-123, parseInt(i32, "-123"));

    try t.expectEqual(123, parseInt(u32, "123"));
    try t.expectEqual(123, parseInt(u32, "+123"));

    try t.expectError(error.InvalidCharacter, parseInt(u32, " 123"));
    try t.expectError(error.InvalidCharacter, parseInt(u32, "123\n"));
}

test "Int: Multiple signs" {
    try t.expectEqual(123, parseInt(i32, "++123"));
    try t.expectEqual(123, parseInt(i32, "--123"));
    try t.expectEqual(-123, parseInt(i32, "+-123"));
    try t.expectEqual(-123, parseInt(i32, "-+123"));
    try t.expectEqual(123, parseInt(i32, "++++++++++123"));
    try t.expectEqual(123, parseInt(i32, "----------123"));
}

test "Int: Overflows" {
    try t.expectError(error.Overflow, parseInt(i32, "999999999999"));
    try t.expectError(error.Underflow, parseInt(i32, "-999999999999"));
    try t.expectError(error.Underflow, parseInt(u32, "-123"));
}

test "Int: Leading zeros" {
    try t.expectEqual(123, parseInt(i32, "0000123"));
    try t.expectEqual(123, parseInt(i32, "+0000123"));
    try t.expectEqual(-123, parseInt(i32, "-0000123"));
}

test "Int: Parsing zero" {
    try t.expectEqual(0, parseInt(i32, "0"));
    try t.expectEqual(0, parseInt(i32, "-0"));
    try t.expectEqual(0, parseInt(i32, "+0"));

    try t.expectEqual(0, parseInt(u32, "-0"));
}

test "Int: Parsing limits" {
    try t.expectEqual(-128, parseInt(i8, "-128"));
    try t.expectEqual(127, parseInt(i8, "127"));
    try t.expectEqual(0, parseInt(u8, "0"));
    try t.expectEqual(255, parseInt(u8, "255"));

    try t.expectEqual(127, parseInt(i8, "0.127 k"));
    try t.expectEqual(127, parseInt(i8, "0.000127000 M"));
    try t.expectEqual(-128, parseInt(i8, "-0.128 k"));
    try t.expectEqual(-128, parseInt(i8, "-0.000128000 M"));

    try t.expectError(error.Underflow, parseInt(i8, "-129"));
    try t.expectError(error.Overflow, parseInt(i8, "128"));
    try t.expectError(error.Underflow, parseInt(u8, "-1"));
    try t.expectError(error.Overflow, parseInt(u8, "256"));

    try t.expectEqual(32767, parseInt(i16, "32767"));
    try t.expectEqual(32767, parseInt(i16, "32.767 k"));
    try t.expectEqual(-32768, parseInt(i16, "-32768"));
    try t.expectEqual(-32768, parseInt(i16, "-32.768 k"));

    try t.expectError(error.Overflow, parseInt(i16, "32768"));
    try t.expectError(error.Overflow, parseInt(i16, "32.768 k"));
    try t.expectError(error.Underflow, parseInt(i16, "-32769"));
    try t.expectError(error.Underflow, parseInt(i16, "-32.769 k"));

    try t.expectEqual(1023, parseInt(i11, "1023"));
    try t.expectEqual(-1024, parseInt(i11, "-1024"));
    try t.expectError(error.Overflow, parseInt(i11, "1024"));
    try t.expectError(error.Underflow, parseInt(i11, "-1025"));
}

test "Int: Invalid characters" {
    try t.expectError(error.InvalidCharacter, parseInt(i32, "12asdf456"));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "ten"));
    try t.expectError(error.InvalidCharacter, parseInt(i32, ""));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "123/456"));
}

test "Int: Underscores not supported" {
    try t.expectError(error.InvalidCharacter, parseInt(i32, "1_2_3"));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "123_"));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "_123"));
}

test "Int: Ten is greater than max(T)" {
    try t.expectEqual(3, parseInt(u2, "3"));
    try t.expectEqual(3, parseInt(i3, "3"));
    try t.expectEqual(-4, parseInt(i3, "-4"));

    try t.expectError(error.Underflow, parseInt(u2, "-1"));
}

test "Int: Basic suffix functionality" {
    try t.expectEqual(123_000, parseInt(i32, "123k"));
    try t.expectEqual(123_000, parseInt(i32, "+123k"));
    try t.expectEqual(-123_000, parseInt(i32, "-123k"));
    try t.expectEqual(123_000_000, parseInt(i32, "123M"));
    try t.expectEqual(123_000_000_000, parseInt(i64, "123B"));
}

test "Int: Spaces and tabs before suffix are allowed" {
    try t.expectEqual(123_000, parseInt(i32, "123 k"));
    try t.expectEqual(123_000, parseInt(i32, "123    k"));
    try t.expectEqual(123_000, parseInt(i32, "123\tk"));
    try t.expectEqual(123_000, parseInt(i32, "123  \tk"));

    try t.expectError(error.InvalidCharacter, parseInt(i32, "123\nk"));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "123\rk"));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "123  \n k"));
}

test "Int: Suffixes are case insensetive" {
    try t.expectEqual(123_000, parseInt(i32, "123 K"));
    try t.expectEqual(123_000_000, parseInt(i32, "123 m"));
    try t.expectEqual(123_000_000_000_000_000, parseInt(i64, "123 qa"));
    try t.expectEqual(123_000_000_000_000_000, parseInt(i64, "123 qA"));
}

test "Int: Long suffixes" {
    try t.expectEqual(123_000, parseInt(i32, "123 thousand"));
    try t.expectEqual(123_000, parseInt(i32, "123thousand"));
    try t.expectEqual(123_000_000, parseInt(i32, "123 MILLION"));
    try t.expectEqual(123_000_000_000, parseInt(i64, "123 BiLLIoN"));
}

test "Int: Invalid suffixes" {
    try t.expectError(error.InvalidCharacter, parseInt(i32, "123 H"));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "123 asdf"));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "123 thousaand"));

    try t.expectError(error.InvalidCharacter, parseInt(i32, "123 abc def"));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "123 thousand thousand"));

    try t.expectError(error.InvalidCharacter, parseInt(i32, "Million"));
}

test "Int: Base and exponent less then max(T), but their multiple is over" {
    try t.expectError(error.Overflow, parseInt(i16, "100k"));
    try t.expectError(error.Underflow, parseInt(i16, "-100k"));
}

test "Int: Basic decimal dot functionality" {
    try t.expectEqual(123, parseInt(i32, "123.0"));
    try t.expectEqual(123, parseInt(i32, "123.0000"));

    try t.expectEqual(123, parseInt(i32, "0.123 k"));
    try t.expectEqual(123_456, parseInt(i32, "123.456 k"));
    try t.expectEqual(123_456, parseInt(i32, "123.456789 k"));
}

test "Int: Rounding towards zero" {
    try t.expectEqual(123, parseInt(i32, "123.4"));
    try t.expectEqual(123, parseInt(i32, "123.5"));
    try t.expectEqual(123, parseInt(i32, "123.6"));

    try t.expectEqual(-123, parseInt(i32, "-123.4"));
    try t.expectEqual(-123, parseInt(i32, "-123.5"));
    try t.expectEqual(-123, parseInt(i32, "-123.6"));

    try t.expectEqual(123, parseInt(i32, "0.1234 k"));
    try t.expectEqual(-123, parseInt(i32, "-0.1234 k"));
}

test "Int: Trailing and leading dot are allowed" {
    try t.expectEqual(123, parseInt(i32, "123."));
    try t.expectEqual(123_000, parseInt(i32, "123.k"));
    try t.expectEqual(123_000, parseInt(i32, "123. k"));
    try t.expectEqual(123, parseInt(i32, ".123 k"));
    try t.expectEqual(-123, parseInt(i32, "-.123 k"));

    try t.expectError(error.InvalidCharacter, parseInt(i32, "."));
}

test "Int: Prefixes not allowed after dot" {
    try t.expectError(error.InvalidCharacter, parseInt(i32, "123.+456"));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "123.-456"));
}

test "Int: Trailing zeros don't cause overflow" {
    try t.expectEqual(123, parseInt(i8, ".123000 k"));
    try t.expectEqual(123, parseInt(i8, ".000123000 M"));
}

test "Int: Integer and decimal part less then max(T), but their sum is over" {
    try t.expectError(error.Overflow, parseInt(i16, "32.999k"));
    try t.expectError(error.Underflow, parseInt(i16, "-32.999k"));
}

test "Int: E-suffixes" {
    try t.expectEqual(123_000, parseInt(i32, "123e3"));
    try t.expectEqual(-123_000, parseInt(i32, "-123e3"));
    try t.expectEqual(123_000_000, parseInt(i32, "123e6"));
    try t.expectEqual(123_000_000, parseInt(i64, "0.123e9"));
    try t.expectEqual(123, parseInt(i32, "12.3e1"));
    try t.expectEqual(0, parseInt(i32, "0e200"));

    try t.expectEqual(1230, parseInt(i32, "123e+1"));
    try t.expectEqual(12, parseInt(i32, "123e-1"));
}

test "Int: Invalid e-suffixes" {
    try t.expectError(error.InvalidCharacter, parseInt(i32, "123 e3"));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "123e 3"));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "e123"));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "123e"));
}

test "Int: E-suffix overflow" {
    try t.expectError(error.Overflow, parseInt(i32, "1e100000"));
    try t.expectError(error.Underflow, parseInt(i32, "-1e100000"));

    try t.expectEqual(0, parseInt(i32, "0e10000000000"));
}

const ParseFloatError = error{
    InvalidCharacter,
    UnknownSuffix,
    NoNumber,
};

/// Parses `string` as a base 10 float of type `T`.
/// Numbers can be written with a decimal dot and a suffix denoting their order
/// of magnitude.
///
/// Three types of suffixes can be used:
///  * Short suffixes (e.g. "1k", "2M", "3Qa")
///  * Long suffixes (e.g. "1 thousand", "2 million", "3 quadrillion")
///  * E-suffixes (scientific/engineering suffixes, e.g "1e3, 2e6, 3e15")
///
/// All the suffixes are case insensetive.
/// Short and long suffixes allow whitespace between them and the number,
/// e-suffixes don't.
pub fn parseFloat(T: type, string: []const u8) ParseFloatError!T {
    if (@typeInfo(T) != .float) {
        @compileError("found type " ++ @typeName(T) ++ ", parseInt only supports integers");
    }

    const chunks: FloatChunks = try .init(string);

    const pow_of_10 = math.pow(T, 10, @floatFromInt(chunks.order_of_magnitude));
    const value = try fmt.parseFloat(T, chunks.number);

    return value * pow_of_10;
}

const FloatChunks = struct {
    number: []const u8,
    order_of_magnitude: u64,

    pub fn init(string_: []const u8) ParseFloatError!FloatChunks {
        const string = mem.trim(u8, string_, &ascii.whitespace);

        if (string.len == 0) return error.NoNumber;

        // Deal with special cases at the start
        const num_start: usize = if (string[0] == '+' or string[0] == '-') 1 else 0;
        if (ascii.eqlIgnoreCase(string[num_start..], "inf") or
            ascii.eqlIgnoreCase(string[num_start..], "infinity") or
            ascii.eqlIgnoreCase(string[num_start..], "nan"))
        {
            return .{ .number = string, .order_of_magnitude = 0 };
        }

        const num_end = mem.indexOfNone(u8, string, digits ++ "Ee+-.") orelse string.len;

        const oom, const has_suffix = blk: {
            const suffix_start = if (mem.lastIndexOfNone(u8, string, ascii.letters)) |idx|
                idx + 1
            else
                return error.NoNumber;
            // Make there is only allowed whitespace between two the end of the number and start of the suffix
            if (mem.indexOfNone(u8, string[num_end..suffix_start], allowed_whitespace) != null) return error.InvalidCharacter;
            const suffix_str = mem.trim(u8, string[suffix_start..], allowed_whitespace);
            if (suffix_str.len == 0) break :blk .{ 0, false };
            break :blk .{ try parseSuffix_old(suffix_str), true };
        };

        const number = string[0..num_end];

        // Make sure there is at least one actual digit
        if (mem.indexOfAny(u8, number, digits) == null) return error.NoNumber;

        // Make sure only one kind of suffix is present
        if (has_suffix and mem.indexOfAny(u8, number, "Ee") != null) return error.InvalidCharacter;

        // Multiple dots, Es, or minuses or pluses in invalid places get
        // checked for by fmt.parseFloat anyway, so there's no need to check
        // for those here

        return .{
            .number = number,
            .order_of_magnitude = oom,
        };
    }
};

test "Float: Basic float parsing" {
    try t.expectEqual(123, parseFloat(f32, "123"));
    try t.expectEqual(123, parseFloat(f32, "+123"));
    try t.expectEqual(-123, parseFloat(f32, "-123"));
    try t.expectEqual(123, parseFloat(f32, "123.0"));
    try t.expectEqual(123.456, parseFloat(f32, "123.456"));

    try t.expectEqual(123, parseFloat(f32, "123."));
    try t.expectEqual(0.123, parseFloat(f32, ".123"));
    try t.expectEqual(-0.123, parseFloat(f32, "-.123"));
    try t.expectEqual(123_000, parseFloat(f32, "123.e3"));

    try t.expectError(error.InvalidCharacter, parseFloat(f32, "++123"));
    try t.expectError(error.InvalidCharacter, parseFloat(f32, "--123"));
    try t.expectError(error.InvalidCharacter, parseFloat(f32, "+-123"));
    try t.expectError(error.InvalidCharacter, parseFloat(f32, "-+123"));

    try t.expectEqual(123, parseFloat(f32, "0000123"));
    try t.expectEqual(123, parseFloat(f32, "+0000123"));
    try t.expectEqual(-123, parseFloat(f32, "-0000123"));

    try t.expectEqual(0.0, parseFloat(f32, "0"));
    try t.expectEqual(0.0, parseFloat(f32, "+0"));
    try t.expectEqual(-0.0, parseFloat(f32, "-0"));
}

test "Float: Overflows, infinity, NaN" {
    try t.expectEqual(math.inf(f32), parseFloat(f32, "999999999999999999999999999999999999999999"));
    try t.expectEqual(-math.inf(f32), parseFloat(f32, "-999999999999999999999999999999999999999999"));

    try t.expectEqual(math.inf(f32), parseFloat(f32, "inf"));
    try t.expectEqual(math.inf(f32), parseFloat(f32, "+INF"));
    try t.expectEqual(-math.inf(f32), parseFloat(f32, "-iNf"));

    try t.expectEqual(math.inf(f32), parseFloat(f32, "infinity"));
    try t.expectEqual(math.inf(f32), parseFloat(f32, "InFInItY"));

    try t.expect(math.isNan(try parseFloat(f32, "nan")));
    try t.expect(math.isNan(try parseFloat(f32, "-NaN")));
}

test "Float: Invalid characters" {
    try t.expectError(error.InvalidCharacter, parseFloat(f32, "12asdf456"));
    try t.expectError(error.InvalidCharacter, parseFloat(f32, "123/456"));
    try t.expectError(error.InvalidCharacter, parseFloat(f32, "123..456"));
    try t.expectError(error.InvalidCharacter, parseFloat(f32, "123.45.6"));
    try t.expectError(error.InvalidCharacter, parseFloat(f32, "123e4.56"));

    try t.expectError(error.NoNumber, parseFloat(f32, "ten"));
    try t.expectError(error.NoNumber, parseFloat(f32, ""));

    try t.expectError(error.InvalidCharacter, parseFloat(f32, "1_2_3"));
    try t.expectError(error.InvalidCharacter, parseFloat(f32, "123_"));
    try t.expectError(error.InvalidCharacter, parseFloat(f32, "_123"));
}

test "Float: E-suffixes" {
    try t.expectEqual(123, parseFloat(f32, "1.23e2"));
    try t.expectEqual(123, parseFloat(f32, "1.23E2"));
    try t.expectEqual(123, parseFloat(f32, "12.3e1"));
    try t.expectEqual(123, parseFloat(f32, "0.00123e5"));
    try t.expectEqual(123, parseFloat(f32, "0.00123e+5"));
    try t.expectEqual(123, parseFloat(f32, "123000e-3"));

    try t.expectEqual(math.inf(f32), parseFloat(f32, "123e9999999999999999999999"));
    try t.expectEqual(0, parseFloat(f32, "0e9999999999999999999999"));
    try t.expectEqual(0, parseFloat(f32, "123e-9999999999999999999999"));
}

test "Float: Long and short suffixes" {
    try t.expectEqual(123_000, parseFloat(f32, "123k"));
    try t.expectEqual(123_000, parseFloat(f32, "+123k"));
    try t.expectEqual(-123_000, parseFloat(f32, "-123k"));
    try t.expectEqual(123_000_000, parseFloat(f32, "123M"));
    try t.expectEqual(123_000_000_000, parseFloat(f64, "123B"));
    try t.expectEqual(123_000_000_000_000_000, parseFloat(f64, "123qa"));
    try t.expectEqual(123_000_000_000_000_000, parseFloat(f64, "123qA"));
    try t.expectEqual(123456.789, parseFloat(f32, "123.456789k"));

    try t.expectEqual(123_000, parseFloat(f32, "123 thousand"));
    try t.expectEqual(123_000, parseFloat(f32, "123thousand"));
    try t.expectEqual(123_000_000, parseFloat(f32, "123 MILLION"));
    try t.expectEqual(123_000_000_000, parseFloat(f64, "123 BiLLIoN"));

    try t.expectEqual(123_000, parseFloat(f32, "123 k"));
    try t.expectEqual(123_000, parseFloat(f32, "123    K"));
    try t.expectEqual(123_000, parseFloat(f32, "123\tk"));
    try t.expectEqual(123_000, parseFloat(f32, "123  \tk"));

    try t.expectError(error.InvalidCharacter, parseFloat(f32, "123\nk"));
    try t.expectError(error.InvalidCharacter, parseFloat(f32, "123\rk"));
    try t.expectError(error.InvalidCharacter, parseFloat(f32, "123  \n k"));

    try t.expectError(error.UnknownSuffix, parseFloat(f32, "123 H"));
    try t.expectError(error.UnknownSuffix, parseFloat(f32, "123 asdf"));
    try t.expectError(error.UnknownSuffix, parseFloat(f32, "123 thousaand"));

    try t.expectError(error.InvalidCharacter, parseFloat(f32, "123 abc def"));
    try t.expectError(error.InvalidCharacter, parseFloat(f32, "123 thousand thousand"));

    try t.expectError(error.NoNumber, parseFloat(f32, "Million"));

    try t.expectError(error.InvalidCharacter, parseFloat(f32, "123e3 k"));
    try t.expectError(error.InvalidCharacter, parseFloat(f32, "123e3 million"));
}
