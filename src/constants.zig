const builtin = @import("builtin");

/// Architecture-dependent atomic integer sizes.
/// Use these aliases for any atomic counters to ensure compatibility
/// across 32-bit and 64-bit targets (e.g., x86 vs x86_64).
/// fixes: https://github.com/muhammad-fiaz/logly.zig/issues/11
pub const AtomicUnsigned = switch (builtin.target.cpu.arch) {
    .x86_64 => u64,
    .aarch64 => u64,
    .riscv64 => u64,
    .powerpc64 => u64,
    .x86 => u32,
    .arm => u32,
    else => u32,
};

pub const AtomicSigned = switch (builtin.target.cpu.arch) {
    .x86_64 => i64,
    .aarch64 => i64,
    .riscv64 => i64,
    .powerpc64 => i64,
    .x86 => i32,
    .arm => i32,
    else => i32,
};

// For convenience expose the native pointer-sized unsigned integer
pub const NativeUint = switch (builtin.target.cpu.arch) {
    .x86_64 => u64,
    .aarch64 => u64,
    .riscv64 => u64,
    .powerpc64 => u64,
    else => u32,
};

// For convenience expose the native pointer-sized signed integer
pub const NativeInt = switch (builtin.target.cpu.arch) {
    .x86_64 => i64,
    .aarch64 => i64,
    .riscv64 => i64,
    .powerpc64 => i64,
    else => i32,
};
