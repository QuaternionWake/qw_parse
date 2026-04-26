const std = @import("std");
const Writer = std.Io.Writer;

const suffixes = @import("suffixes");

pub fn FormatInt(value: anytype, options: FormatOptions) IntFormatter(@TypeOf(value)) {
    return .{ .value = value, .options = options };
}

fn IntFormatter(T: type) type {
    return struct {
        value: T,
        options: FormatOptions,

        pub fn format(self: @This(), writer: *Writer) Writer.Error!void {
            switch (@typeInfo(T)) {
                .int, .comptime_int => {},
                else => @compileError("found type " ++ @typeName(T) ++ ", IntFormatter only supports integers"),
            }
            const number_info: NumberInfo(T) = .init(self.value);
            if (number_info.sign == .neg) {
                try writer.writeByte('-');
            } else if (self.options.force_sign) {
                try writer.writeByte('+');
            }
            if (number_info.oom < 3) {
                try writer.printInt(number_info.value, 10, .lower, .{});
                return;
            }
            const needs_fallback = self.options.suffix_type == .long or self.options.suffix_type == .short;
            if (!needs_fallback or number_info.oom / 3 - 1 <= suffixes.max_suffix) {
                try switch (self.options.suffix_type) {
                    .short => printShortOrLongSuffix(T, writer, number_info, self.options.precision, .short),
                    .long => printShortOrLongSuffix(T, writer, number_info, self.options.precision, .long),
                    .scientific => printScientificE(T, writer, number_info, self.options.precision),
                    .engineering => printEngineeringE(T, writer, number_info, self.options.precision),
                };
            } else {
                try switch (self.options.fallback_suffix_type) {
                    .scientific => printScientificE(T, writer, number_info, self.options.precision),
                    .engineering => printEngineeringE(T, writer, number_info, self.options.precision),
                };
            }
        }
    };
}

fn NumberInfo(T: type) type {
    return struct {
        value: UnsignedT,
        sign: enum { pos, neg },
        oom: u64,

        const UnsignedT = toUnsignedOrComptime(T);

        pub fn init(value: T) NumberInfo(T) {
            const sign = if (value < 0) .neg else .pos;
            const positive_value = positiveCast(value);
            const oom: u64 = @intCast(std.math.log10(positive_value));

            return .{
                .value = positive_value,
                .sign = sign,
                .oom = oom,
            };
        }
    };
}

fn printShortOrLongSuffix(
    T: type,
    writer: *Writer,
    number_info: NumberInfo(T),
    precision: u64,
    suffix: enum { short, long },
) Writer.Error!void {
    const dot_idx: i64 = @intCast(number_info.oom % 3);
    const n = number_info.oom / 3 - 1;
    const precision_ = if (precision < dot_idx + 1) @as(u64, @intCast(dot_idx + 1)) else precision;

    try printNDigits(@TypeOf(number_info.value), writer, number_info.value, precision_, dot_idx);
    switch (suffix) {
        .short => try suffixes.writeShortSuffix(writer, @intCast(n)),
        .long => {
            try writer.writeByte(' ');
            try suffixes.writeLongSuffix(writer, @intCast(n));
        },
    }
}

fn printScientificE(
    T: type,
    writer: *Writer,
    number_info: NumberInfo(T),
    precision: u64,
) Writer.Error!void {
    const precision_ = if (precision == 0) 1 else precision;

    try printNDigits(@TypeOf(number_info.value), writer, number_info.value, precision_, 0);
    try writer.writeByte('e');
    try writer.printInt(number_info.oom, 10, .lower, .{});
}

fn printEngineeringE(
    T: type,
    writer: *Writer,
    number_info: NumberInfo(T),
    precision: u64,
) Writer.Error!void {
    const dot_idx: i64 = @intCast(number_info.oom % 3);
    const oom = number_info.oom - @as(u64, @intCast(dot_idx));
    const precision_ = if (precision < dot_idx + 1) @as(u64, @intCast(dot_idx + 1)) else precision;

    try printNDigits(@TypeOf(number_info.value), writer, number_info.value, precision_, dot_idx);
    try writer.writeByte('E');
    try writer.printInt(oom, 10, .lower, .{});
}

fn printNDigits(T: type, writer: *Writer, value: T, n: usize, dot_idx: i64) Writer.Error!void {
    const RuntimeT = if (T == comptime_int) std.math.IntFittingRange(value, value) else T;
    const value_oom = if (value == 0) 0 else std.math.log10(value);
    var divisor: RuntimeT = std.math.powi(RuntimeT, 10, value_oom) catch unreachable;
    var val: RuntimeT = @intCast(value);
    var digits_written: usize = 0;
    var current_oom: usize = 0;
    var dot_written = false;

    if (dot_idx < 0) {
        try writer.writeByte('0');
        try writer.writeByte('.');
        digits_written += 1;
        dot_written = true;

        const n_zeros = @min(@as(usize, @intCast(-(dot_idx + 1))), n);
        try writer.splatByteAll('0', n_zeros);
        digits_written += n_zeros;
    }

    for (digits_written..n) |_| {
        const digit: u8 = @intCast(val / divisor);
        if (!dot_written and current_oom == dot_idx + 1) {
            try writer.writeByte('.');
            dot_written = true;
        }
        try writer.writeByte(digit + '0');

        val %= divisor;
        divisor /= 10;
        digits_written += 1;
        current_oom += 1;

        if (divisor == 0) break;
    }

    if (!dot_written and dot_idx < n - 1) {
        const n_zeros = @as(usize, @intCast(dot_idx)) - (digits_written - 1);
        try writer.splatByteAll('0', n_zeros);
        try writer.writeByte('.');
        digits_written += n_zeros;
    }

    try writer.splatByteAll('0', n - digits_written);
}

test "printNDigits" {
    const Formatter = struct {
        fn TestFormatter(T: type) type {
            return struct {
                value: T,
                n: usize,
                oom: i64,

                pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
                    try printNDigits(T, writer, self.value, self.n, self.oom);
                }
            };
        }

        fn Format(value: anytype, n: usize, oom: i64) TestFormatter(@TypeOf(value)) {
            return .{
                .value = value,
                .n = n,
                .oom = oom,
            };
        }
    };

    const value: u64 = 123456;
    try t.expectFmt("123.4", "{f}", .{Formatter.Format(value, 4, 2)});
    try t.expectFmt("1.234", "{f}", .{Formatter.Format(value, 4, 0)});
    try t.expectFmt("0.123", "{f}", .{Formatter.Format(value, 4, -1)});
    try t.expectFmt("0.001", "{f}", .{Formatter.Format(value, 4, -3)});
    try t.expectFmt("0.000", "{f}", .{Formatter.Format(value, 4, -4)});
    try t.expectFmt("1234", "{f}", .{Formatter.Format(value, 4, 6)});
    try t.expectFmt("1234", "{f}", .{Formatter.Format(value, 4, 3)});
    try t.expectFmt("123456000", "{f}", .{Formatter.Format(value, 9, 8)});
    try t.expectFmt("123456.000", "{f}", .{Formatter.Format(value, 9, 5)});
    try t.expectFmt("123456000.000", "{f}", .{Formatter.Format(value, 12, 8)});
}

fn positiveCast(x: anytype) toUnsignedOrComptime(@TypeOf(x)) {
    if (@TypeOf(x) == comptime_int) {
        const val = if (x < 0) -x else x;
        std.debug.assert(val >= 0);
        return val;
    }

    if (@typeInfo(@TypeOf(x)).int.signedness == .unsigned) return x;

    if (x >= 0) return @intCast(x);

    if (x == std.math.minInt(@TypeOf(x))) return @bitCast(x);

    return @intCast(-x);
}

fn toUnsignedOrComptime(T: type) type {
    if (T == comptime_int) {
        return comptime_int;
    } else if (@typeInfo(T) == .int) {
        return @Int(.unsigned, @typeInfo(T).int.bits);
    } else {
        @compileError("toUnsignedOrComptime only supports ints, found " ++ @typeName(T));
    }
}

pub const FormatOptions = struct {
    // TODO: consider renaming to n_digits
    precision: u64 = 3,
    suffix_type: SuffixType = .short,
    fallback_suffix_type: FallbackSuffixType = .scientific,
    force_sign: bool = false,
};

pub const SuffixType = enum { short, long, scientific, engineering };
pub const FallbackSuffixType = enum { scientific, engineering };

const t = std.testing;

test "Basic formatting" {
    try t.expectFmt("123", "{f}", .{FormatInt(123, .{})});
    try t.expectFmt("-123", "{f}", .{FormatInt(-123, .{})});

    try t.expectFmt("+123", "{f}", .{FormatInt(123, .{ .force_sign = true })});
    try t.expectFmt("-123", "{f}", .{FormatInt(-123, .{ .force_sign = true })});
}

test "Short suffixes" {
    try t.expectFmt("123k", "{f}", .{FormatInt(123_000, .{})});
    try t.expectFmt("-123k", "{f}", .{FormatInt(-123_000, .{})});
    try t.expectFmt("123M", "{f}", .{FormatInt(123_000_000, .{})});
    try t.expectFmt("123B", "{f}", .{FormatInt(123_000_000_000, .{})});

    try t.expectFmt("123k", "{f}", .{FormatInt(123_000, .{ .suffix_type = .short })});
    try t.expectFmt("-123k", "{f}", .{FormatInt(-123_000, .{ .suffix_type = .short })});
}

test "Long suffixes" {
    try t.expectFmt("123 thousand", "{f}", .{FormatInt(123_000, .{ .suffix_type = .long })});
    try t.expectFmt("-123 thousand", "{f}", .{FormatInt(-123_000, .{ .suffix_type = .long })});
    try t.expectFmt("123 million", "{f}", .{FormatInt(123_000_000, .{ .suffix_type = .long })});
    try t.expectFmt("123 billion", "{f}", .{FormatInt(123_000_000_000, .{ .suffix_type = .long })});
}

test "Precision" {
    // TODO: should the zeros be truncated?
    try t.expectFmt("123.456000k", "{f}", .{FormatInt(123_456, .{ .precision = 9 })});
    try t.expectFmt("123.456k", "{f}", .{FormatInt(123_456, .{ .precision = 6 })});
    try t.expectFmt("123.4k", "{f}", .{FormatInt(123_456, .{ .precision = 4 })});
    try t.expectFmt("123k", "{f}", .{FormatInt(123_456, .{ .precision = 3 })});
    try t.expectFmt("123k", "{f}", .{FormatInt(123_456, .{ .precision = 2 })});
    try t.expectFmt("123k", "{f}", .{FormatInt(123_456, .{ .precision = 1 })});
    try t.expectFmt("123k", "{f}", .{FormatInt(123_456, .{ .precision = 0 })});
    try t.expectFmt("123 thousand", "{f}", .{FormatInt(123_456, .{ .suffix_type = .long, .precision = 2 })});
    try t.expectFmt("123E3", "{f}", .{FormatInt(123_456, .{ .suffix_type = .engineering, .precision = 1 })});

    try t.expectFmt("1.23400k", "{f}", .{FormatInt(1_234, .{ .precision = 6 })});
    try t.expectFmt("1.2340k", "{f}", .{FormatInt(1_234, .{ .precision = 5 })});
    try t.expectFmt("1.234k", "{f}", .{FormatInt(1_234, .{ .precision = 4 })});
    try t.expectFmt("1.23k", "{f}", .{FormatInt(1_234, .{ .precision = 3 })});
    try t.expectFmt("1.2k", "{f}", .{FormatInt(1_234, .{ .precision = 2 })});
    try t.expectFmt("1k", "{f}", .{FormatInt(1_234, .{ .precision = 1 })});
    try t.expectFmt("1k", "{f}", .{FormatInt(1_234, .{ .precision = 0 })});

    try t.expectFmt("1", "{f}", .{FormatInt(1, .{ .precision = 100 })});
}

test "Scientific-e suffixes" {
    try t.expectFmt("1", "{f}", .{FormatInt(1, .{ .suffix_type = .scientific })});
    try t.expectFmt("12", "{f}", .{FormatInt(12, .{ .suffix_type = .scientific })});
    try t.expectFmt("123", "{f}", .{FormatInt(123, .{ .suffix_type = .scientific })});
    try t.expectFmt("1.23e3", "{f}", .{FormatInt(1_234, .{ .suffix_type = .scientific })});
    try t.expectFmt("1.23e4", "{f}", .{FormatInt(12_345, .{ .suffix_type = .scientific })});
    try t.expectFmt("1.23e5", "{f}", .{FormatInt(123_456, .{ .suffix_type = .scientific })});

    try t.expectFmt("1.23456000e5", "{f}", .{FormatInt(123_456, .{ .suffix_type = .scientific, .precision = 9 })});
    try t.expectFmt("1.23456e5", "{f}", .{FormatInt(123_456, .{ .suffix_type = .scientific, .precision = 6 })});
    try t.expectFmt("1.2345e5", "{f}", .{FormatInt(123_456, .{ .suffix_type = .scientific, .precision = 5 })});
    try t.expectFmt("1.234e5", "{f}", .{FormatInt(123_456, .{ .suffix_type = .scientific, .precision = 4 })});
    try t.expectFmt("1.23e5", "{f}", .{FormatInt(123_456, .{ .suffix_type = .scientific, .precision = 3 })});
    try t.expectFmt("1.2e5", "{f}", .{FormatInt(123_456, .{ .suffix_type = .scientific, .precision = 2 })});
    try t.expectFmt("1e5", "{f}", .{FormatInt(123_456, .{ .suffix_type = .scientific, .precision = 1 })});
    try t.expectFmt("1e5", "{f}", .{FormatInt(123_456, .{ .suffix_type = .scientific, .precision = 0 })});
}

test "Engineering-E suffixes" {
    try t.expectFmt("1", "{f}", .{FormatInt(1, .{ .suffix_type = .engineering })});
    try t.expectFmt("1.23E3", "{f}", .{FormatInt(1_234, .{ .suffix_type = .engineering })});
    try t.expectFmt("12.3E3", "{f}", .{FormatInt(12_345, .{ .suffix_type = .engineering })});
    try t.expectFmt("123E3", "{f}", .{FormatInt(123_456, .{ .suffix_type = .engineering })});
    try t.expectFmt("123.45E3", "{f}", .{FormatInt(123_456, .{ .suffix_type = .engineering, .precision = 5 })});
}

test "Fallback suffix" {
    try t.expectFmt("100NNgNntg", "{f}", .{FormatInt(try std.math.powi(u10000, 10, 3002), .{})});
    try t.expectFmt("1.00e3003", "{f}", .{FormatInt(try std.math.powi(u10000, 10, 3003), .{})});

    try t.expectFmt("100E3000", "{f}", .{FormatInt(try std.math.powi(u10000, 10, 3002), .{ .suffix_type = .engineering })});
    try t.expectFmt("1.00E3003", "{f}", .{FormatInt(try std.math.powi(u10000, 10, 3003), .{ .suffix_type = .engineering })});
}
