const std = @import("std");

const ParseError = error{
    InvalidCharacter,
    UnknownSuffix,
    NoNumber,
    Overflow,
    Underflow,
};

pub fn parseInt(T: type, string: []const u8) ParseError!T {
    _ = string;
    return error.Unimplemented;
}

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

    try t.expectEqual(132, parseInt(i32, "0.123 k"));
    try t.expectEqual(132_456, parseInt(i32, "123.123 k"));
    try t.expectEqual(132_123, parseInt(i32, "123.123123 k"));
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
