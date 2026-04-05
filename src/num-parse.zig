const std = @import("std");
const mem = std.mem;
const ascii = std.ascii;
const fmt = std.fmt;
const math = std.math;

const ParseIntError = error{
    InvalidCharacter,
    UnknownSuffix,
    NoNumber,
    Overflow,
    Underflow,
};

/// Parses `string` as a base 10 integer of type `T`.
/// Numbers can be written with a decimal dot and a suffix denoting their order
/// of magnitude.
///
/// Three types of suffixes can be used:
///  * Short suffixes (e.g. "1k", "2M", "3Qa")
///  * Long suffixes (e.g. "1 thousand", "2 million", "3 quadrillion")
///  * E-suffixes (scientific/engineering suffixes, e.g "1e3, 2e6, 3e15")
///
/// All the suffixes are case insensetive, and short and long ones allow
/// whitespace between them and the number.
/// E-suffixes don't allow whitespace and must be positive.
pub fn parseInt(T: type, string: []const u8) ParseIntError!T {
    const type_info = switch (@typeInfo(T)) {
        .int => |info| info,
        else => @compileError("found type " ++ @typeName(T) ++ ", parseInt only supports integers"),
    };
    const TempT = @Type(.{ .int = .{ .bits = @max(type_info.bits, 8), .signedness = .unsigned } });

    // Parse the string into a more managable format
    // Most of the more complex functionality is handled in this function
    const chunks: IntChunks = try .init(string);

    // At least one of these two needs to exist
    if (chunks.integer == null and chunks.decimal == null) return error.NoNumber;

    const integer =
        if (chunks.integer) |str| blk: {
            const int = fmt.parseUnsigned(TempT, str, 10) catch |err|
                return convertError(err, chunks.sign);
            if (int == 0) break :blk 0;
            const pow_of_10 = try math.powi(TempT, 10, chunks.order_of_magnitude orelse
                return convertError(error.Overflow, chunks.sign));
            break :blk math.mul(TempT, int, pow_of_10) catch |err|
                return convertError(err, chunks.sign);
        } else 0;

    const decimal =
        if (chunks.decimal) |str| blk: {
            const trailing_zeros_start = (mem.lastIndexOfAny(u8, str, digits[1..]) orelse break :blk 0) + 1;
            const unwrapped_oom = chunks.order_of_magnitude orelse return convertError(error.Overflow, chunks.sign);
            const end = @min(trailing_zeros_start, unwrapped_oom);
            if (end == 0) break :blk 0;
            // Can't overflow as end can't be greater than
            // chunks.order_of_magnitude due to the line above
            const oom = unwrapped_oom - end;

            const dec = fmt.parseUnsigned(TempT, str[0..end], 10) catch |err|
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
    if (result == @as(TempT, @intCast(math.maxInt(T))) + 1 and chunks.sign == .neg) return math.minInt(T);

    // Make sure the result can fit into T
    if (result > math.maxInt(T)) return convertError(error.Overflow, chunks.sign);

    const signed_result: T = @intCast(result);
    return if (chunks.sign == .pos)
        signed_result
    else
        -signed_result;
}

fn convertError(err: fmt.ParseIntError, sign: IntChunks.Sign) ParseIntError {
    return switch (err) {
        error.Overflow => switch (sign) {
            .pos => error.Overflow,
            .neg => error.Underflow,
        },
        error.InvalidCharacter => error.InvalidCharacter,
    };
}

const IntChunks = struct {
    integer: ?[]const u8,
    decimal: ?[]const u8,

    sign: Sign,
    order_of_magnitude: ?u8,

    const Sign = enum { pos, neg };

    pub fn init(string_: []const u8) ParseIntError!IntChunks {
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

            // If there is no suffix, or the suffix is an e-suffix
            if (suffix_start == string.len) {
                if (mem.lastIndexOfAny(u8, string, "eE")) |idx| {
                    if (idx == num_start) return error.NoNumber;
                    const oom = fmt.parseUnsigned(u8, string[idx + 1 ..], 10) catch |err|
                        switch (err) {
                            error.InvalidCharacter => return convertError(err, sign),
                            error.Overflow => null,
                        };
                    break :blk .{ oom, idx };
                } else break :blk .{ 0, string.len };
            }

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
    for (short_suffixes, long_suffixes, 1..) |short, long, i| {
        if (ascii.eqlIgnoreCase(string, short) or ascii.eqlIgnoreCase(string, long)) {
            return @intCast(i * 3);
        }
    }
    return error.UnknownSuffix;
}

const short_suffixes: [11][]const u8 = .{ "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" };
const long_suffixes: [11][]const u8 = .{
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
};

const allowed_whitespace = " \t";
const digits = "0123456789";

const t = std.testing;

test "Int: Basic parsing" {
    try t.expectEqual(123, parseInt(i32, "123"));
    try t.expectEqual(123, parseInt(i32, "+123"));
    try t.expectEqual(-123, parseInt(i32, "-123"));

    try t.expectEqual(123, parseInt(u32, "123"));
    try t.expectEqual(123, parseInt(u32, "+123"));
}

test "Int: Multiple signs" {
    try t.expectError(error.InvalidCharacter, parseInt(i32, "++123"));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "--123"));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "+-123"));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "-+123"));
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
    try t.expectError(error.NoNumber, parseInt(i32, "ten"));
    try t.expectError(error.NoNumber, parseInt(i32, ""));
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
    try t.expectError(error.UnknownSuffix, parseInt(i32, "123 H"));
    try t.expectError(error.UnknownSuffix, parseInt(i32, "123 asdf"));
    try t.expectError(error.UnknownSuffix, parseInt(i32, "123 thousaand"));

    try t.expectError(error.InvalidCharacter, parseInt(i32, "123 abc def"));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "123 thousand thousand"));

    try t.expectError(error.NoNumber, parseInt(i32, "Million"));
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

    try t.expectError(error.NoNumber, parseInt(i32, "."));
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
}

test "Int: Invalid e-suffixes" {
    try t.expectError(error.InvalidCharacter, parseInt(i32, "123 e3"));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "123e 3"));

    try t.expectError(error.InvalidCharacter, parseInt(i32, "123e+3"));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "123e-3"));

    try t.expectError(error.NoNumber, parseInt(i32, "e123"));
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
fn parseFloat(T: type, string: []const u8) ParseFloatError!T {
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
    order_of_magnitude: u8,

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
            break :blk .{ try parseSuffix(suffix_str), true };
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
