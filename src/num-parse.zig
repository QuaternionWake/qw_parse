const std = @import("std");
const mem = std.mem;
const ascii = std.ascii;
const fmt = std.fmt;
const math = std.math;

const ParseError = error{
    InvalidCharacter,
    UnknownSuffix,
    NoNumber,
    Overflow,
    Underflow,
};

pub fn parseInt(T: type, string: []const u8) ParseError!T {
    const type_info = switch (@typeInfo(T)) {
        .int => |info| info,
        else => @compileError("found type " ++ @typeName(T) ++ ", parseInt only supports integers"),
    };
    const TempT = @Type(.{ .int = .{ .bits = @max(type_info.bits, 8), .signedness = .unsigned } });

    // Parse the string into a more managable format
    // Most of the more complex functionality is handled in this function
    const chunks: NumberChunks = try .init(string);

    // At least one of these two needs to exist
    if (chunks.integer == null and chunks.decimal == null) return error.NoNumber;

    const integer =
        if (chunks.integer) |str| blk: {
            const int = fmt.parseInt(TempT, str, 10) catch |err|
                return convertError(err, chunks.sign);
            if (int == 0) break :blk 0;
            const pow_of_10 = try math.powi(TempT, 10, chunks.order_of_magnitude);
            break :blk math.mul(TempT, int, pow_of_10) catch |err|
                return convertError(err, chunks.sign);
        } else 0;

    const decimal =
        if (chunks.decimal) |str| blk: {
            const trailing_zeros_start = (mem.lastIndexOfAny(u8, str, digits[1..]) orelse break :blk 0) + 1;
            const end = @min(trailing_zeros_start, chunks.order_of_magnitude);
            // Can't overflow as end can't be greater than
            // chunks.order_of_magnitude due to the line above
            const oom = chunks.order_of_magnitude - end;

            const dec = fmt.parseInt(TempT, str[0..end], 10) catch |err|
                return convertError(err, chunks.sign);
            const pow_of_10 = try math.powi(TempT, 10, oom);
            break :blk math.mul(TempT, dec, pow_of_10) catch |err|
                return convertError(err, chunks.sign);
        } else 0;

    const result = math.add(TempT, integer, decimal) catch |err|
        return convertError(err, chunks.sign);

    if (type_info.signedness == .unsigned) {
        if (chunks.sign == .neg and result != 0) return error.Underflow;
        return math.cast(T, result) orelse return error.Overflow;
    }

    // Handle case where we're parsing the smallest negative number for T,
    // whose positive counterpart can't fit in T
    if (result == @as(TempT, @intCast(math.maxInt(T))) + 1) return math.minInt(T);

    // Make sure the result can fit into T
    if (result > math.maxInt(T)) return convertError(error.Overflow, chunks.sign);

    const signed_result: T = @intCast(result);
    return if (chunks.sign == .pos)
        signed_result
    else
        -signed_result;
}

fn convertError(err: fmt.ParseIntError, sign: NumberChunks.Sign) ParseError {
    return switch (err) {
        error.Overflow => switch (sign) {
            .pos => error.Overflow,
            .neg => error.Underflow,
        },
        error.InvalidCharacter => error.InvalidCharacter,
    };
}

const NumberChunks = struct {
    integer: ?[]const u8,
    decimal: ?[]const u8,

    sign: Sign,
    order_of_magnitude: u8,

    const Sign = enum { pos, neg };

    pub fn init(string_: []const u8) ParseError!NumberChunks {
        const string = mem.trim(u8, string_, &std.ascii.whitespace);

        if (string.len == 0) return error.NoNumber;

        const sign: Sign, const num_start: usize = switch (string[0]) {
            '+' => .{ .pos, 1 },
            '-' => .{ .neg, 1 },
            else => .{ .pos, 0 },
        };

        const order_of_magnitude, const num_end = blk: {
            const suffix_start = if (mem.lastIndexOfNone(u8, string, ascii.letters)) |idx|
                idx + 1
            else
                return error.NoNumber;

            // If there is no suffix
            if (suffix_start == string.len) break :blk .{ 0, string.len };

            const num_end = mem.indexOfAny(u8, string, allowed_whitespace) orelse suffix_start;
            // Make sure there are no invalid characters between two separate chunks of whitespace
            if (mem.indexOfNone(u8, string[num_end..suffix_start], allowed_whitespace) != null) return error.InvalidCharacter;
            const order_of_magnitude = try parseSuffix(string[suffix_start..]);
            break :blk .{ order_of_magnitude, num_end };
        };

        const decimal_point = mem.indexOfScalar(u8, string, '.');

        const integer, const decimal = if (decimal_point) |dp| blk: {
            const integer = if (num_start != dp) string[num_start..dp] else null;
            const decimal = if (dp + 1 != num_end) string[dp + 1 .. num_end] else null;
            break :blk .{ integer, decimal };
        } else .{ string[num_start..num_end], null };

        // Make sure there are no invalid characters in the digit parts
        if (integer) |str| if (mem.indexOfNone(u8, str, digits) != null) return error.InvalidCharacter;
        if (decimal) |str| if (mem.indexOfNone(u8, str, digits) != null) return error.InvalidCharacter;

        return .{
            .integer = integer,
            .decimal = decimal,

            .sign = sign,
            .order_of_magnitude = order_of_magnitude,
        };
    }
};

fn parseSuffix(string: []const u8) !u8 {
    for (suffixes, 1..) |suffix, i| {
        if (ascii.eqlIgnoreCase(string, suffix)) {
            return @intCast(i * 3);
        }
    }
    return error.UnknownSuffix;
}

const suffixes: [11][]const u8 = .{ "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" };

const allowed_whitespace = " \t";
const digits = "0123456789";

const t = std.testing;

test "Basic parsing" {
    try t.expectEqual(123, parseInt(i32, "123"));
    try t.expectEqual(123, parseInt(i32, "+123"));
    try t.expectEqual(-123, parseInt(i32, "-123"));

    try t.expectEqual(123, parseInt(u32, "123"));
    try t.expectEqual(123, parseInt(u32, "+123"));
}

test "Multiple signs" {
    try t.expectError(error.InvalidCharacter, parseInt(i32, "++123"));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "--123"));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "+-123"));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "-+123"));
}

test "Overflows" {
    try t.expectError(error.Overflow, parseInt(i32, "999999999999"));
    try t.expectError(error.Underflow, parseInt(i32, "-999999999999"));
    try t.expectError(error.Underflow, parseInt(u32, "-123"));
}

test "Leading zeros" {
    try t.expectEqual(123, parseInt(i32, "0000123"));
    try t.expectEqual(123, parseInt(i32, "+0000123"));
    try t.expectEqual(-123, parseInt(i32, "-0000123"));
}

test "Parsing zero" {
    try t.expectEqual(0, parseInt(i32, "0"));
    try t.expectEqual(0, parseInt(i32, "-0"));
    try t.expectEqual(0, parseInt(i32, "+0"));

    try t.expectEqual(0, parseInt(u32, "-0"));
}

test "Parsing limits" {
    try t.expectEqual(-128, parseInt(i8, "-128"));
    try t.expectEqual(127, parseInt(i8, "127"));
    try t.expectEqual(0, parseInt(u8, "0"));
    try t.expectEqual(255, parseInt(u8, "255"));
}

test "Invalid characters" {
    try t.expectError(error.InvalidCharacter, parseInt(i32, "12asdf456"));
    try t.expectError(error.NoNumber, parseInt(i32, "ten"));
    try t.expectError(error.NoNumber, parseInt(i32, ""));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "123/456"));
}

test "Underscores not supported" {
    try t.expectError(error.InvalidCharacter, parseInt(i32, "1_2_3"));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "123_"));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "_123"));
}

test "Base greater than max(T)" {
    try t.expectEqual(3, parseInt(u2, "3"));
}

test "Basic suffix functionality" {
    try t.expectEqual(123_000, parseInt(i32, "123k"));
    try t.expectEqual(123_000, parseInt(i32, "+123k"));
    try t.expectEqual(-123_000, parseInt(i32, "-123k"));
    try t.expectEqual(123_000_000, parseInt(i32, "123M"));
    try t.expectEqual(123_000_000_000, parseInt(i64, "123B"));
}

test "Spaces and tabs before suffix are allowed" {
    try t.expectEqual(123_000, parseInt(i32, "123 k"));
    try t.expectEqual(123_000, parseInt(i32, "123    k"));
    try t.expectEqual(123_000, parseInt(i32, "123\tk"));
    try t.expectEqual(123_000, parseInt(i32, "123  \tk"));

    try t.expectError(error.InvalidCharacter, parseInt(i32, "123\nk"));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "123\rk"));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "123  \n k"));
}

test "Suffixes are case insensetive" {
    try t.expectEqual(123_000, parseInt(i32, "123 K"));
    try t.expectEqual(123_000_000, parseInt(i32, "123 m"));
    try t.expectEqual(123_000_000_000_000_000, parseInt(i64, "123 qa"));
    try t.expectEqual(123_000_000_000_000_000, parseInt(i64, "123 qA"));
}

test "Invalid suffixes" {
    try t.expectError(error.UnknownSuffix, parseInt(i32, "123 H"));
    try t.expectError(error.UnknownSuffix, parseInt(i32, "123 asdf"));

    try t.expectError(error.InvalidCharacter, parseInt(i32, "123 abc def"));
}

test "Base and exponent less then max(T), but their multiple is over" {
    try t.expectError(error.Overflow, parseInt(i16, "100k"));
    try t.expectError(error.Underflow, parseInt(i16, "-100k"));
}

test "Basic decimal dot functionality" {
    try t.expectEqual(123, parseInt(i32, "123.0"));
    try t.expectEqual(123, parseInt(i32, "123.0000"));

    try t.expectEqual(123, parseInt(i32, "0.123 k"));
    try t.expectEqual(123_456, parseInt(i32, "123.456 k"));
    try t.expectEqual(123_456, parseInt(i32, "123.456789 k"));
}

// test "Rounding" { // TODO: decide rounding behavior
// try t.expectEqual(123, parse(i32, "123.4"));
//     try t.expectEqual(123, parse(i32, "123.5"));
//     try t.expectEqual(123, parse(i32, "123.6"));

//     try t.expectEqual(123, parse(i32, "-123.4"));
//     try t.expectEqual(123, parse(i32, "-123.5"));
//     try t.expectEqual(123, parse(i32, "-123.6"));
// }

test "Trailing and leading dot are allowed" {
    try t.expectEqual(123, parseInt(i32, "123."));
    try t.expectEqual(123_000, parseInt(i32, "123.k"));
    try t.expectEqual(123_000, parseInt(i32, "123. k"));
    try t.expectEqual(123, parseInt(i32, ".123 k"));
    try t.expectEqual(-123, parseInt(i32, "-.123 k"));

    try t.expectError(error.NoNumber, parseInt(i32, "."));
}

test "Prefixes not allowed after dot" {
    try t.expectError(error.InvalidCharacter, parseInt(i32, "123.+456"));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "123.-456"));
}

test "Trailing zeros don't cause overflow" {
    try t.expectEqual(123, parseInt(i8, ".123000 k"));
    try t.expectEqual(123, parseInt(i8, ".000123000 M"));
}

test "Integer and decimal part less then max(T), but their sum is over" {
    try t.expectError(error.Overflow, parseInt(i16, "32.999k"));
    try t.expectError(error.Underflow, parseInt(i16, "-32.999k"));
}
