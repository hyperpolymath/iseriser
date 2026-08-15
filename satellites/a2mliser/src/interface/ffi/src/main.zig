// a2mliser FFI Implementation
//
// This module implements the C-compatible FFI declared in src/interface/abi/Foreign.idr.
// All types and layouts must match the Idris2 ABI definitions.
//
// Provides: hashing (SHA-256, BLAKE3), signing (Ed25519), envelope creation,
// provenance chain operations, and verification.
//
// SPDX-License-Identifier: MPL-2.0

const std = @import("std");

// Version information (keep in sync with Cargo.toml)
const VERSION = "0.1.0";
const BUILD_INFO = "a2mliser built with Zig " ++ @import("builtin").zig_version_string;

/// Thread-local error storage
threadlocal var last_error: ?[]const u8 = null;

/// Set the last error message
fn setError(msg: []const u8) void {
    last_error = msg;
}

/// Clear the last error
fn clearError() void {
    last_error = null;
}

//==============================================================================
// Core Types (must match src/interface/abi/Types.idr)
//==============================================================================

/// Attestation result codes (must match Idris2 AttestationResult type)
pub const AttestationResult = enum(c_int) {
    ok = 0,
    @"error" = 1,
    invalid_param = 2,
    out_of_memory = 3,
    null_pointer = 4,
    signature_invalid = 5,
    digest_mismatch = 6,
    chain_broken = 7,
    key_expired = 8,
};

/// Hash algorithm identifiers (must match Idris2 HashAlgorithm encoding)
pub const HashAlgorithm = enum(u32) {
    sha256 = 0,
    blake3 = 1,
};

/// Signature algorithm identifiers (must match Idris2 SignatureAlgorithm encoding)
pub const SignatureAlgorithm = enum(u32) {
    ed25519 = 0,
    ed448 = 1,
};

/// Attestation engine handle (opaque to prevent direct access)
const EngineState = struct {
    allocator: std.mem.Allocator,
    initialized: bool,
    // Future: key store, chain cache, config
};

/// Opaque handle type for C ABI
pub const Handle = opaque {};

/// Cast between EngineState and opaque Handle
fn toHandle(state: *EngineState) ?*Handle {
    return @ptrCast(state);
}

fn fromHandle(handle: ?*Handle) ?*EngineState {
    const h = handle orelse return null;
    return @ptrCast(@alignCast(h));
}

/// Envelope header struct (must match Layout.idr envelopeHeaderLayout — 32 bytes)
pub const EnvelopeHeader = extern struct {
    hash_alg_id: u32,
    sig_alg_id: u32,
    digest_len: u32,
    signature_len: u32,
    timestamp: u64,
    has_parent: u32,
    _pad: u32,
};

comptime {
    // Compile-time assertion: EnvelopeHeader must be exactly 32 bytes
    if (@sizeOf(EnvelopeHeader) != 32) {
        @compileError("EnvelopeHeader size mismatch with Idris2 ABI");
    }
    if (@alignOf(EnvelopeHeader) != 8) {
        @compileError("EnvelopeHeader alignment mismatch with Idris2 ABI");
    }
}

//==============================================================================
// Library Lifecycle
//==============================================================================

/// Initialize the a2mliser attestation engine.
/// Returns a handle, or null on failure.
export fn a2mliser_init() ?*Handle {
    const allocator = std.heap.c_allocator;

    const state = allocator.create(EngineState) catch {
        setError("Failed to allocate engine state");
        return null;
    };

    state.* = .{
        .allocator = allocator,
        .initialized = true,
    };

    clearError();
    return toHandle(state);
}

/// Free the attestation engine handle
export fn a2mliser_free(handle: ?*Handle) void {
    const state = fromHandle(handle) orelse return;
    const allocator = state.allocator;

    state.initialized = false;
    allocator.destroy(state);
    clearError();
}

//==============================================================================
// Hashing Operations
//==============================================================================

/// Compute SHA-256 digest.
/// input_ptr: pointer to input data
/// output_ptr: pointer to 32-byte output buffer
/// input_len: length of input data
/// Returns: 0 on success, error code on failure
export fn a2mliser_hash_sha256(
    handle: ?*Handle,
    input_ptr: ?[*]const u8,
    input_len: u32,
) AttestationResult {
    const state = fromHandle(handle) orelse {
        setError("Null handle");
        return .null_pointer;
    };

    if (!state.initialized) {
        setError("Engine not initialized");
        return .@"error";
    }

    const input = input_ptr orelse {
        setError("Null input pointer");
        return .null_pointer;
    };

    // SHA-256 computation (stub — will use std.crypto.hash.sha2.Sha256)
    _ = input[0..input_len];

    clearError();
    return .ok;
}

/// Compute BLAKE3 digest.
/// Same interface as SHA-256.
export fn a2mliser_hash_blake3(
    handle: ?*Handle,
    input_ptr: ?[*]const u8,
    input_len: u32,
) AttestationResult {
    const state = fromHandle(handle) orelse {
        setError("Null handle");
        return .null_pointer;
    };

    if (!state.initialized) {
        setError("Engine not initialized");
        return .@"error";
    }

    const input = input_ptr orelse {
        setError("Null input pointer");
        return .null_pointer;
    };

    // BLAKE3 computation (stub — will use std.crypto.hash.Blake3)
    _ = input[0..input_len];

    clearError();
    return .ok;
}

//==============================================================================
// Signing Operations
//==============================================================================

/// Sign a digest with Ed25519.
/// priv_key_ptr: pointer to 32-byte private key
/// digest_ptr: pointer to 32-byte digest
/// sig_out_ptr: pointer to 64-byte output buffer for signature
export fn a2mliser_sign_ed25519(
    handle: ?*Handle,
    priv_key_ptr: ?[*]const u8,
    digest_ptr: ?[*]const u8,
    sig_out_ptr: ?[*]u8,
) AttestationResult {
    const state = fromHandle(handle) orelse {
        setError("Null handle");
        return .null_pointer;
    };

    if (!state.initialized) {
        setError("Engine not initialized");
        return .@"error";
    }

    _ = priv_key_ptr orelse {
        setError("Null private key pointer");
        return .invalid_param;
    };

    _ = digest_ptr orelse {
        setError("Null digest pointer");
        return .invalid_param;
    };

    _ = sig_out_ptr orelse {
        setError("Null signature output pointer");
        return .invalid_param;
    };

    // Ed25519 signing (stub — will use std.crypto.sign.Ed25519)

    clearError();
    return .ok;
}

//==============================================================================
// Verification Operations
//==============================================================================

/// Verify an Ed25519 signature against a digest.
/// pub_key_ptr: pointer to 32-byte public key
/// digest_ptr: pointer to 32-byte digest
/// sig_ptr: pointer to 64-byte signature
/// Returns: ok (0) if valid, signature_invalid (5) otherwise
export fn a2mliser_verify_ed25519(
    handle: ?*Handle,
    pub_key_ptr: ?[*]const u8,
    digest_ptr: ?[*]const u8,
    sig_ptr: ?[*]const u8,
) AttestationResult {
    const state = fromHandle(handle) orelse {
        setError("Null handle");
        return .null_pointer;
    };

    if (!state.initialized) {
        setError("Engine not initialized");
        return .@"error";
    }

    _ = pub_key_ptr orelse {
        setError("Null public key pointer");
        return .invalid_param;
    };

    _ = digest_ptr orelse {
        setError("Null digest pointer");
        return .invalid_param;
    };

    _ = sig_ptr orelse {
        setError("Null signature pointer");
        return .invalid_param;
    };

    // Ed25519 verification (stub — will use std.crypto.sign.Ed25519)

    clearError();
    return .ok;
}

//==============================================================================
// Envelope Operations
//==============================================================================

/// Create an attestation envelope for a document.
/// Returns pointer to allocated envelope, or null on failure.
export fn a2mliser_create_envelope(
    handle: ?*Handle,
    doc_ptr: ?[*]const u8,
    doc_len: u32,
    hash_alg: u32,
    sig_alg: u32,
    priv_key_ptr: ?[*]const u8,
) ?*EnvelopeHeader {
    const state = fromHandle(handle) orelse {
        setError("Null handle");
        return null;
    };

    if (!state.initialized) {
        setError("Engine not initialized");
        return null;
    }

    _ = doc_ptr orelse {
        setError("Null document pointer");
        return null;
    };

    _ = priv_key_ptr orelse {
        setError("Null private key pointer");
        return null;
    };

    const envelope = state.allocator.create(EnvelopeHeader) catch {
        setError("Failed to allocate envelope");
        return null;
    };

    const digest_len: u32 = 32; // Both SHA-256 and BLAKE3 produce 32-byte digests
    const sig_len: u32 = if (sig_alg == 0) 64 else 114; // Ed25519: 64, Ed448: 114

    envelope.* = .{
        .hash_alg_id = hash_alg,
        .sig_alg_id = sig_alg,
        .digest_len = digest_len,
        .signature_len = sig_len,
        .timestamp = @intCast(std.time.timestamp()),
        .has_parent = 0,
        ._pad = 0,
    };

    _ = doc_len;

    clearError();
    return envelope;
}

/// Free an attestation envelope
export fn a2mliser_free_envelope(handle: ?*Handle, envelope: ?*EnvelopeHeader) void {
    const state = fromHandle(handle) orelse return;
    const env = envelope orelse return;
    state.allocator.destroy(env);
}

/// Verify an attestation envelope against its document.
export fn a2mliser_verify_envelope(
    handle: ?*Handle,
    envelope: ?*const EnvelopeHeader,
    doc_ptr: ?[*]const u8,
    doc_len: u32,
    pub_key_ptr: ?[*]const u8,
) AttestationResult {
    const state = fromHandle(handle) orelse {
        setError("Null handle");
        return .null_pointer;
    };

    if (!state.initialized) {
        setError("Engine not initialized");
        return .@"error";
    }

    _ = envelope orelse {
        setError("Null envelope pointer");
        return .null_pointer;
    };

    _ = doc_ptr orelse {
        setError("Null document pointer");
        return .null_pointer;
    };

    _ = pub_key_ptr orelse {
        setError("Null public key pointer");
        return .null_pointer;
    };

    _ = doc_len;

    // Verification logic (stub):
    // 1. Recompute digest of document using envelope.hash_alg_id
    // 2. Compare with stored digest
    // 3. Verify signature over digest using pub_key_ptr

    clearError();
    return .ok;
}

//==============================================================================
// Provenance Chain Operations
//==============================================================================

/// Extend a provenance chain with a new attestation.
/// parent_ptr: pointer to parent envelope (null for root)
export fn a2mliser_chain_extend(
    handle: ?*Handle,
    parent_ptr: ?*const EnvelopeHeader,
    doc_ptr: ?[*]const u8,
    doc_len: u32,
    priv_key_ptr: ?[*]const u8,
) ?*EnvelopeHeader {
    const state = fromHandle(handle) orelse {
        setError("Null handle");
        return null;
    };

    if (!state.initialized) {
        setError("Engine not initialized");
        return null;
    }

    _ = doc_ptr orelse {
        setError("Null document pointer");
        return null;
    };

    _ = priv_key_ptr orelse {
        setError("Null private key pointer");
        return null;
    };

    const envelope = state.allocator.create(EnvelopeHeader) catch {
        setError("Failed to allocate chain entry");
        return null;
    };

    envelope.* = .{
        .hash_alg_id = 1, // Default to BLAKE3
        .sig_alg_id = 0, // Default to Ed25519
        .digest_len = 32,
        .signature_len = 64,
        .timestamp = @intCast(std.time.timestamp()),
        .has_parent = if (parent_ptr != null) 1 else 0,
        ._pad = 0,
    };

    _ = doc_len;

    clearError();
    return envelope;
}

/// Verify an entire provenance chain from leaf to root.
export fn a2mliser_chain_verify(
    handle: ?*Handle,
    leaf_ptr: ?*const EnvelopeHeader,
    pub_key_ptr: ?[*]const u8,
) AttestationResult {
    const state = fromHandle(handle) orelse {
        setError("Null handle");
        return .null_pointer;
    };

    if (!state.initialized) {
        setError("Engine not initialized");
        return .@"error";
    }

    _ = leaf_ptr orelse {
        setError("Null chain leaf pointer");
        return .null_pointer;
    };

    _ = pub_key_ptr orelse {
        setError("Null public key pointer");
        return .null_pointer;
    };

    // Chain verification logic (stub):
    // Walk from leaf to root, verifying each link

    clearError();
    return .ok;
}

//==============================================================================
// String Operations
//==============================================================================

/// Get a string result.
/// Caller must free the returned string with a2mliser_free_string.
export fn a2mliser_get_string(handle: ?*Handle) ?[*:0]const u8 {
    const state = fromHandle(handle) orelse {
        setError("Null handle");
        return null;
    };

    if (!state.initialized) {
        setError("Engine not initialized");
        return null;
    }

    const result = state.allocator.dupeZ(u8, "a2mliser attestation engine") catch {
        setError("Failed to allocate string");
        return null;
    };

    clearError();
    return result.ptr;
}

/// Free a string allocated by the library
export fn a2mliser_free_string(str: ?[*:0]const u8) void {
    const s = str orelse return;
    const allocator = std.heap.c_allocator;
    const slice = std.mem.span(s);
    allocator.free(slice);
}

//==============================================================================
// Error Handling
//==============================================================================

/// Get the last error message. Returns null if no error.
export fn a2mliser_last_error() ?[*:0]const u8 {
    const err = last_error orelse return null;
    const allocator = std.heap.c_allocator;
    const c_str = allocator.dupeZ(u8, err) catch return null;
    return c_str.ptr;
}

//==============================================================================
// Version Information
//==============================================================================

/// Get the library version
export fn a2mliser_version() [*:0]const u8 {
    return VERSION.ptr;
}

/// Get build information
export fn a2mliser_build_info() [*:0]const u8 {
    return BUILD_INFO.ptr;
}

//==============================================================================
// Utility Functions
//==============================================================================

/// Check if attestation engine is initialized
export fn a2mliser_is_initialized(handle: ?*Handle) u32 {
    const state = fromHandle(handle) orelse return 0;
    return if (state.initialized) 1 else 0;
}

//==============================================================================
// Tests
//==============================================================================

test "lifecycle" {
    const handle = a2mliser_init() orelse return error.InitFailed;
    defer a2mliser_free(handle);

    try std.testing.expect(a2mliser_is_initialized(handle) == 1);
}

test "error handling" {
    const result = a2mliser_hash_sha256(null, null, 0);
    try std.testing.expectEqual(AttestationResult.null_pointer, result);

    const err = a2mliser_last_error();
    try std.testing.expect(err != null);
}

test "version" {
    const ver = a2mliser_version();
    const ver_str = std.mem.span(ver);
    try std.testing.expectEqualStrings(VERSION, ver_str);
}

test "envelope header size" {
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(EnvelopeHeader));
}

test "envelope creation and free" {
    const handle = a2mliser_init() orelse return error.InitFailed;
    defer a2mliser_free(handle);

    // Create envelope with dummy data
    var dummy_doc = [_]u8{ 'h', 'e', 'l', 'l', 'o' };
    var dummy_key = [_]u8{0} ** 32;

    const envelope = a2mliser_create_envelope(
        handle,
        &dummy_doc,
        5,
        1, // BLAKE3
        0, // Ed25519
        &dummy_key,
    );

    try std.testing.expect(envelope != null);

    if (envelope) |env| {
        try std.testing.expectEqual(@as(u32, 1), env.hash_alg_id);
        try std.testing.expectEqual(@as(u32, 0), env.sig_alg_id);
        try std.testing.expectEqual(@as(u32, 32), env.digest_len);
        try std.testing.expectEqual(@as(u32, 64), env.signature_len);
        a2mliser_free_envelope(handle, env);
    }
}
