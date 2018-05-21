//
//  CodePushReactNativeCore.swift
//  CodePush
//
//  Copyright © 2018 MSFT. All rights reserved.
//

import Foundation


class CodePushReactNativeCore: CodePushBaseCore {
    
    /**
     * Default file name for javascript bundle.
     */
    static let DEFAULT_JS_BUNDLE_NAME = "index.android.bundle"
    
    init(_ deploymentKey: String,
         _ serverUrl: String,
         _ appSecret: String,
         _ appName: String,
         _ appVersion: String,
         _ baseDirectory: String,
         _ appEntryPointProvider: CodePushReactAppEntryPointProvider,
         _ platformUtils: ReactPlatformUtils) throws {
        try super.init(deploymentKey,
                   appSecret, false, baseDirectory, serverUrl, appName, appVersion, appEntryPointProvider, platformUtils)
    }
}
