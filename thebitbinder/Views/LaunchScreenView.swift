//
//  LaunchScreenView.swift
//  thebitbinder
//
//  Simple, clean launch screen.
//

import SwiftUI

struct LaunchScreenView: View {
    var statusText: String = "Loading..."
    var userName: String = "there"
    
    @State private var opacity: Double = 0
    @State private var scale: CGFloat = 0.95

    var body: some View {
        ZStack {
            // Clean background
            Color(UIColor.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Simple app icon representation
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.linearGradient(
                        colors: [.accentColor, .accentColor.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .symbolRenderingMode(.hierarchical)

                VStack(spacing: 8) {
                    Text("BitBinder")
                        .font(.largeTitle.weight(.bold))
                        .foregroundColor(.primary)

                    Text("Your material, organized")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if !userName.isEmpty && userName != "there" {
                        Text("Welcome back, \(userName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    }
                }
                
                // Loading indicator
                VStack(spacing: 8) {
                    ProgressView()
                    
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)
            }
            .scaleEffect(scale)
            .opacity(opacity)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                opacity = 1
                scale = 1
            }
        }
    }
}

#Preview {
    LaunchScreenView(statusText: "Syncing with iCloud...")
}