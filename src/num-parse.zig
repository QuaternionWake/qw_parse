const std = @import("std");

const ParseError = error{
    InvalidCharacter,
    UnknownSuffix,
    NoNumber,
    Overflow,
    Underflow,
};

pub fn parseInt(T: type, string: []const u8, base: u8) ParseError!T {
    _ = string;
    _ = base;
    return error.Unimplemented;
}

const t = std.testing;

test "Basic parsing" {
    try t.expectEqual(123, parseInt(i32, "123", 10));
    try t.expectEqual(123, parseInt(i32, "+123", 10));
    try t.expectEqual(-123, parseInt(i32, "-123", 10));

    try t.expectEqual(123, parseInt(u32, "123", 10));
    try t.expectEqual(123, parseInt(u32, "+123", 10));
}

test "Multiple signs" {
    try t.expectError(error.InvalidCharacter, parseInt(i32, "++123", 10));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "--123", 10));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "+-123", 10));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "-+123", 10));
}

test "Overflows" {
    try t.expectError(error.Overflow, parseInt(i32, "999999999999", 10));
    try t.expectError(error.Underflow, parseInt(i32, "-999999999999", 10));
    try t.expectError(error.Underflow, parseInt(u32, "-123", 10));
}

test "Leading zeros" {
    try t.expectEqual(123, parseInt(i32, "0000123", 10));
    try t.expectEqual(123, parseInt(i32, "+0000123", 10));
    try t.expectEqual(-123, parseInt(i32, "-0000123", 10));
}

test "Parsing zero" {
    try t.expectEqual(0, parseInt(i32, "0", 10));
    try t.expectEqual(0, parseInt(i32, "-0", 10));
    try t.expectEqual(0, parseInt(i32, "+0", 10));

    try t.expectEqual(0, parseInt(u32, "-0", 10));
}

test "Parsing limits" {
    try t.expectEqual(-128, parseInt(i8, "-128", 10));
    try t.expectEqual(127, parseInt(i8, "127", 10));
    try t.expectEqual(0, parseInt(u8, "0", 10));
    try t.expectEqual(255, parseInt(u8, "255", 10));
}

test "Other bases" {
    try t.expectEqual(9, parseInt(i32, "1001", 2));
    try t.expectEqual(38, parseInt(i32, "123", 5));
    try t.expectEqual(305, parseInt(i32, "A5", 30));
    try t.expectEqual(305, parseInt(i32, "a5", 30));
}

test "Invalid characters" {
    try t.expectError(error.InvalidCharacter, parseInt(i32, "1002", 2));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "12asdf456", 10));
    try t.expectError(error.NoNumber, parseInt(i32, "ten", 10));
    try t.expectError(error.NoNumber, parseInt(i32, "", 10));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "123/456", 10));
}

test "Inferred bases" {
    try t.expectEqual(0b1001, parseInt(i32, "0b1001", 0));
    try t.expectEqual(0o123, parseInt(i32, "0o123", 0));
    try t.expectEqual(0xA5, parseInt(i32, "0xA5", 0));
    try t.expectEqual(123, parseInt(i32, "123", 0));

    try t.expectEqual(0b1001, parseInt(i32, "0B1001", 0));
    try t.expectEqual(0o123, parseInt(i32, "0O123", 0));
    try t.expectEqual(0xA5, parseInt(i32, "0XA5", 0));

    try t.expectEqual(0b1001, parseInt(i32, "+0b1001", 0));
    try t.expectEqual(-0b1001, parseInt(i32, "-0b1001", 0));
    try t.expectEqual(123, parseInt(i32, "+123", 0));
    try t.expectEqual(-123, parseInt(i32, "-123", 0));
}

test "Invalid characters in inferred bases" {
    try t.expectError(error.InvalidCharacter, parseInt(i32, "0b1002", 0));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "12asdf456", 0));
}

test "Underscores not supported" {
    try t.expectError(error.InvalidCharacter, parseInt(i32, "1_2_3", 10));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "123_", 10));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "_123", 10));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "0x_123", 0));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "0_x123", 0));
}

test "Base greater than max(T)" {
    try t.expectEqual(3, parseInt(u2, "3", 10));
    try t.expectEqual(3, parseInt(u2, "3", 0));
    try t.expectEqual(3, parseInt(u2, "0x3", 0));
}

test "Basic suffix functionality" {
    try t.expectEqual(123_000, parseInt(i32, "123k", 10));
    try t.expectEqual(123_000, parseInt(i32, "+123k", 10));
    try t.expectEqual(-123_000, parseInt(i32, "-123k", 10));
    try t.expectEqual(123_000_000, parseInt(i32, "123M", 10));
    try t.expectEqual(123_000_000_000, parseInt(i64, "123B", 10));
}

test "Spaces and tabs before suffix are allowed" {
    try t.expectEqual(123_000, parseInt(i32, "123 k", 10));
    try t.expectEqual(123_000, parseInt(i32, "123    k", 10));
    try t.expectEqual(123_000, parseInt(i32, "123\tk", 10));
    try t.expectEqual(123_000, parseInt(i32, "123  \tk", 10));

    try t.expectError(error.InvalidCharacter, parseInt(i32, "123\nk", 10));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "123\rk", 10));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "123  \n k", 10));
}

test "Suffixes are case insensetive" {
    try t.expectEqual(123_000, parseInt(i32, "123 K", 10));
    try t.expectEqual(123_000_000, parseInt(i32, "123 m", 10));
    try t.expectEqual(123_000_000_000_000_000, parseInt(i64, "123 qa", 10));
    try t.expectEqual(123_000_000_000_000_000, parseInt(i64, "123 qA", 10));
}

test "Invalid suffixes" {
    try t.expectError(error.UnknownSuffix, parseInt(i32, "123 H", 10));
    try t.expectError(error.UnknownSuffix, parseInt(i32, "123 asdf", 10));

    try t.expectError(error.InvalidCharacter, parseInt(i32, "123 abc def", 10));
}

test "Base and exponent less then max(T), but their multiple is over" {
    try t.expectError(error.Overflow, parseInt(i16, "100k", 10));
    try t.expectError(error.Underflow, parseInt(i16, "-100k", 10));
}

test "Basic decimal dot functionality" {
    try t.expectEqual(123, parseInt(i32, "123.0", 10));
    try t.expectEqual(123, parseInt(i32, "123.0000", 10));

    try t.expectEqual(132, parseInt(i32, "0.123 k", 10));
    try t.expectEqual(132_456, parseInt(i32, "123.123 k", 10));
    try t.expectEqual(132_123, parseInt(i32, "123.123123 k", 10));
}

// test "Rounding" { // TODO: decide rounding behavior
//     try t.expectEqual(123, parse(i32, "123.4", 10));
//     try t.expectEqual(123, parse(i32, "123.5", 10));
//     try t.expectEqual(123, parse(i32, "123.6", 10));

//     try t.expectEqual(123, parse(i32, "-123.4", 10));
//     try t.expectEqual(123, parse(i32, "-123.5", 10));
//     try t.expectEqual(123, parse(i32, "-123.6", 10));
// }

test "Trailing and leading dot are allowed" {
    try t.expectEqual(123, parseInt(i32, "123.", 10));
    try t.expectEqual(123_000, parseInt(i32, "123.k", 10));
    try t.expectEqual(123_000, parseInt(i32, "123. k", 10));
    try t.expectEqual(123, parseInt(i32, ".123 k", 10));
    try t.expectEqual(-123, parseInt(i32, "-.123 k", 10));

    try t.expectError(error.NoNumber, parseInt(i32, ".", 10));
}

test "Prefixes not allowed after dot" {
    try t.expectError(error.InvalidCharacter, parseInt(i32, "123.+456", 10));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "123.-456", 10));
    try t.expectError(error.InvalidCharacter, parseInt(i32, "123.0x456", 0));
}

test "Trailing zeros don't cause overflow" {
    try t.expectEqual(123, parseInt(i8, ".123000 k", 10));
    try t.expectEqual(123, parseInt(i8, ".000123000 M", 10));
}

test "Integer and decimal part less then max(T), but their sum is over" {
    try t.expectError(error.Overflow, parseInt(i16, "32.999k", 10));
    try t.expectError(error.Underflow, parseInt(i16, "-32.999k", 10));
}
