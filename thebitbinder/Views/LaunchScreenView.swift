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

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color(UIColor.systemBackground),
                    Color(UIColor.secondarySystemBackground).opacity(0.65)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()
                
                launchIcon

                VStack(spacing: 10) {
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
                            .padding(.top, 4)
                    }
                }
                
                Spacer()
                
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.regular)
                    
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                }
                .padding(.bottom, 60)
            }
        }
    }

    @ViewBuilder
    private var launchIcon: some View {
        if UIImage(named: "BitBuddyIcon") != nil {
            Image("BitBuddyIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                    .frame(width: 80, height: 80)

                Image(systemName: "text.quote")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(.accentColor)
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
