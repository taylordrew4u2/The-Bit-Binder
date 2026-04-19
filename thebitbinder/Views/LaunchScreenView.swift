//
//  LaunchScreenView.swift
//  thebitbinder
//
//  Simple, clean launch screen with staggered entrance.
//

import SwiftUI

struct LaunchScreenView: View {
    var statusText: String = "Loading..."
    var userName: String = "there"
    
    @State private var iconVisible = false
    @State private var titleVisible = false
    @State private var subtitleVisible = false
    @State private var loadingVisible = false

    var body: some View {
        ZStack {
            // Clean background with subtle gradient
            LinearGradient(
                colors: [
                    Color(UIColor.systemBackground),
                    Color(UIColor.secondarySystemBackground).opacity(0.5)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()
                
                // App icon with gentle scale-in
                Image("BitBuddyIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .scaleEffect(iconVisible ? 1 : 0.6)
                    .opacity(iconVisible ? 1 : 0)

                VStack(spacing: 10) {
                    Text("BitBinder")
                        .font(.largeTitle.weight(.bold))
                        .foregroundColor(.primary)
                        .opacity(titleVisible ? 1 : 0)
                        .offset(y: titleVisible ? 0 : 8)

                    Text("Your material, organized")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .opacity(subtitleVisible ? 1 : 0)
                        .offset(y: subtitleVisible ? 0 : 6)
                    
                    if !userName.isEmpty && userName != "there" {
                        Text("Welcome back, \(userName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                            .opacity(subtitleVisible ? 1 : 0)
                    }
                }
                
                Spacer()
                
                // Loading indicator — appears last
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.regular)
                    
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                }
                .opacity(loadingVisible ? 1 : 0)
                .padding(.bottom, 60)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                iconVisible = true
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.15)) {
                titleVisible = true
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.3)) {
                subtitleVisible = true
            }
            withAnimation(.easeOut(duration: 0.3).delay(0.5)) {
                loadingVisible = true
            }
        }
    }
}

#Preview {
    LaunchScreenView(statusText: "Syncing with iCloud...")
}

#Preview("With Name") {
    LaunchScreenView(statusText: "Loading your jokes...", userName: "Taylor")
}