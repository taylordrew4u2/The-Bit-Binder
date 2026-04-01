//
//  DebugLog.swift
//  thebitbinder
//
//  Silences all print() calls in Release builds.
//  This module-level overload shadows Swift's standard library print(),
//  so every existing print() becomes a no-op in production without
//  touching any call sites.
//

#if !DEBUG
func print(_ items: Any..., separator: String = " ", terminator: String = "\n") { }
#endif
