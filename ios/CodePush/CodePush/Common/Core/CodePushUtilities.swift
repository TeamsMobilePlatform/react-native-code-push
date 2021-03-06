//
//  CodePushUtilities.swift
//  CodePush
//
//  Copyright © 2018 MSFT. All rights reserved.
//

import Foundation

/**
 * Encapsulates utilities that ```CodePushBaseCore``` is using.
 */
class CodePushUtilities {

    /**
     * Instance of ```CodePushUtils```.
     */
    var utils: CodePushUtils

    /**
     * Instance of ```FileUtils.
     */
    var fileUtils: FileUtils

    /**
     * Instance of ```CodePushUpdateUtils```.
     */
    var updateUtils: CodePushUpdateUtils

    /**
     * Instance of ```CodePushPlatformUtils```.
     */
    var platformUtils: CodePushPlatformUtils

    /**
     * Creates instance of CodePushUtilities
     */
    init(_ utils: CodePushUtils, _ fileUtils: FileUtils, _ updateUtils: CodePushUpdateUtils,
         _ platformUtils: CodePushPlatformUtils) {
        self.utils = utils
        self.fileUtils = fileUtils
        self.updateUtils = updateUtils
        self.platformUtils = platformUtils
    }
}
