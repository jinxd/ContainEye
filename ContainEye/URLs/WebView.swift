//
//  WebView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 4/5/25.
//


import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    let view = WKWebView()

    init(url: URL) {
        view.load(URLRequest(url: url))
    }

    func makeUIView(context: Context) -> some UIView {
        view
    }
    func updateUIView(_ uiView: UIViewType, context: Context) {
    }
}