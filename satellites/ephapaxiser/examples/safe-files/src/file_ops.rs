// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Example source file for ephapaxiser analysis.
//
// This file demonstrates various resource usage patterns — some correct, some
// intentionally buggy — so that ephapaxiser can detect violations.

/// Correct usage: file is opened and properly closed.
fn correct_file_usage() {
    let fd = open("data.txt");
    // ... use the file ...
    close(fd);
}

/// BUG: Resource leak — file is opened but never closed.
fn leaky_file_usage() {
    let fd = open("leaked.txt");
    // ... forgot to close ...
}

/// BUG: Double-free — file is closed twice.
fn double_close() {
    let fd = open("double.txt");
    close(fd);
    close(fd);
}

/// Correct database usage: connection is opened and properly disconnected.
fn correct_db_usage() {
    let conn = connect("postgres://localhost/mydb");
    // ... query the database ...
    disconnect(conn);
}

/// BUG: Database connection leak.
fn leaky_db_usage() {
    let conn = connect("postgres://localhost/mydb");
    // ... forgot to disconnect ...
}
