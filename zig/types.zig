//! Lists enums for communication between JS and WASM, or important misc ones.
pub const Command = enum(u32) { Reset, Begin, Exit, SendSeed };
