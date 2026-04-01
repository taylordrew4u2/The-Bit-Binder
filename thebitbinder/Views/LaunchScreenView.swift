//
//  LaunchScreenView.swift
//  thebitbinder
//
//  Created on 12/3/25.
//

import SwiftUI

struct LaunchScreenView: View {
    var statusText: String = "Loading..."
    var userName: String = "there"
    
    @State private var mark: CGFloat = 0
    @State private var fade: Double  = 0

    var body: some View {
        ZStack {
            //  Paper background 
            AppTheme.Colors.paperCream.ignoresSafeArea()

            // Faint rules
            Canvas { ctx, size in
                var y: CGFloat = 32
                while y < size.height {
                    var p = Path()
                    p.move(to: .init(x: 0, y: y))
                    p.addLine(to: .init(x: size.width, y: y))
                    ctx.stroke(p, with: .color(AppTheme.Colors.paperLine), lineWidth: 0.6)
                    y += 32
                }
            }
            .ignoresSafeArea()

            // Red margin
            HStack {
                Rectangle()
                    .fill(AppTheme.Colors.marginRed)
                    .frame(width: 1.5)
                    .padding(.leading, 52)
                Spacer()
            }
            .ignoresSafeArea()

            //  Center mark 
            VStack(spacing: 28) {
                // Book mark — spine + pages
                ZStack {
                    // Shadow
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.black.opacity(0.12))
                        .frame(width: 76, height: 96)
                        .offset(y: 6)
                        .blur(radius: 8)

                    // Leather cover
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.Colors.leatherGradient)
                        .frame(width: 76, height: 92)

                    // Page stack highlight
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppTheme.Colors.paperCream)
                        .frame(width: 56, height: 80)
                        .offset(x: 4)

                    // Rule lines on page
                    VStack(spacing: 9) {
                        ForEach(0..<5) { _ in
                            Rectangle()
                                .fill(AppTheme.Colors.paperLine)
                                .frame(width: 38, height: 1)
                        }
                    }
                    .offset(x: 5)

                    // Spine shadow
                    Rectangle()
                        .fill(Color.black.opacity(0.18))
                        .frame(width: 10, height: 92)
                        .offset(x: -33)
                        .mask(
                            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: 10, height: 92)
                                .offset(x: -33)
                        )
                }
                .scaleEffect(0.88 + mark * 0.12)
                .opacity(mark)

                // Wordmark
                VStack(spacing: 6) {
                    Text("BitBinder")
                        .font(.system(size: 30, weight: .bold, design: .serif))
                        .foregroundColor(AppTheme.Colors.inkBlack)
                        .tracking(-0.5)

                    Text("shut up and write some jokes")
                        .font(.system(size: 13, weight: .regular, design: .serif))
                        .italic()
                        .foregroundColor(AppTheme.Colors.textTertiary)
                        .tracking(0.2)
                    
                    // Personalized greeting
                    Text("Welcome back, \(userName)")
                        .font(.caption)
                        .foregroundColor(AppTheme.Colors.textTertiary)
                        .padding(.top, 12)
                    
                    // Status text during loading
                    Text(statusText)
                        .font(.caption2)
                        .foregroundColor(AppTheme.Colors.textTertiary)
                        .opacity(0.7)
                        .padding(.top, 4)
                }
                .opacity(fade)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72).delay(0.05)) {
                mark = 1
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.22)) {
                fade = 1
            }
        }
    }
}

#Preview { LaunchScreenView(statusText: "Loading...") }
