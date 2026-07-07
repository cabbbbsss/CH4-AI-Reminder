//
//  InsightView-k.swift
//  Eve
//
//  Created by Ketut Agus Cahyadi Nanda on 07/07/26.
//

import SwiftUI

struct InsightView: View {
  @Environment(\.dismiss) var dismiss
  //
  var body: some View {
    ZStack {
      Color(hex: "#E0ECF7").ignoresSafeArea()
      
      VStack(spacing: 0) {
        // Top Nav
        HStack {
          Button(action: {
            dismiss()
          }) {
            Image(systemName: "chevron.backward.circle.fill")
              .font(.system(size: 32))
              .foregroundColor(Color(hex: "#1D3557"))
              .background(Circle().fill(Color.white))
          }
          
          Spacer()
          
          Text("Insight")
            .font(.system(size: 17, weight: .bold))
            .foregroundColor(.black)
          
          Spacer()
          
          // placeholder to balance the back button
          Color.clear.frame(width: 32, height: 32)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        
        // Character + Chat Bubble
        HStack(alignment: .center, spacing: 16) {
          // Robot Face Group
          ZStack {
            Circle()
              .fill(Color.clear)
              .frame(width: 79, height: 79)
            
            Circle()
              .fill(Color.white)
              .frame(width: 70, height: 70)
            
            // Screen
            Ellipse()
              .fill(Color(hex: "#1A1916"))
              .frame(width: 54, height: 36)
              .offset(y: -2)
            
            // Face details
            VStack(spacing: 4) {
              HStack(spacing: 14) {
                Ellipse().fill(Color(hex: "#E0ECF7")).frame(width: 5, height: 3)
                Ellipse().fill(Color(hex: "#E0ECF7")).frame(width: 5, height: 3)
              }
              Rectangle().fill(Color(hex: "#E0ECF7")).frame(width: 13, height: 2)
            }
            .offset(y: -2)
          }
          
          // Chat Bubble
          ZStack(alignment: .leading) {
            // The triangle pointing left
            Path { path in
              path.move(to: CGPoint(x: 10, y: 15))
              path.addLine(to: CGPoint(x: 0, y: 25))
              path.addLine(to: CGPoint(x: 10, y: 35))
            }
            .fill(Color.white)
            .offset(x: -8)
            
            Text("Here’s what I’ve learned\nabout you!")
              .font(.system(size: 13, weight: .bold))
              .foregroundColor(Color(hex: "#1D3557"))
              .padding(.horizontal, 16)
              .padding(.vertical, 12)
              .background(Color.white)
              .cornerRadius(12)
          }
          Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 24)
        
        // Dark Blue Container
        ZStack(alignment: .top) {
          Color(hex: "#1D3557")
            .cornerRadius(32, corners: [.topLeft, .topRight])
            .ignoresSafeArea(edges: .bottom)
          
          VStack {
            ScrollView(showsIndicators: false) {
              VStack(spacing: 32) {
                InsightRow(text: "You go to Max & Nine every Wednesday.")
                InsightRow(text: "You usually go to Resto Bintang 67 on Saturday afternoons.")
                InsightRow(text: "You often study on the cafe on weekdays.")
                InsightRow(text: "You often study on the cafe on weekdays.")
                InsightRow(text: "You often study on the cafe on weekdays.")
              }
              .padding(.top, 40)
              .padding(.horizontal, 32)
            }
            
            // Button
            NavigationLink(destination: HistoryView()) {
              Text("View History")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color(hex: "#E0ECF7"))
                .frame(width: 200, height: 44)
                .background(Color(hex: "#368BC8"))
                .cornerRadius(22)
            }
            .padding(.bottom, 40)
            .padding(.top, 20)
          }
        }
      }
    }
    .navigationBarHidden(true)
  }
}

struct InsightRow: View {
  var text: String
  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      Image(systemName: "checkmark.circle")
        .font(.system(size: 20))
        .foregroundColor(Color(hex: "#EDF3FA"))
        .padding(.top, 2)
      
      Text(text)
        .font(.system(size: 18, weight: .medium))
        .foregroundColor(Color(hex: "#E8F3FF"))
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

#Preview {
  NavigationStack {
    InsightView()
  }
}
