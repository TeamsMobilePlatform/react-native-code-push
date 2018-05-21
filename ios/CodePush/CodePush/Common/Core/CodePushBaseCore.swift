//
//  CodePushBaseCore.swift
//  CodePush
//
//  Copyright © 2018 MSFT. All rights reserved.
//

import Foundation

public class CodePushBaseCore {
    
    var deploymentKey: String
    var baseDirectory: String
    var serverUrl: String
    var appName: String
    var appVersion: String
    var state: CodePushState
    var utilities: CodePushUtilities
    var managers: CodePushManagers
    var appEntryPoint: String
    
    /**
     * Creates instance of {@link CodePushBaseCore}. Default constructor.
     * We pass {@link Application} and app secret here, too, because we can't initialize AppCenter in another constructor and then call this.
     * However, AppCenter must be initialized before creating anything else.
     *
     * @param deploymentKey         deployment key.
     * @param context               application context.
     * @param application           application instance (pass <code>null</code> if you don't need {@link Crashes} integration for tracking exceptions).
     * @param appSecret             the value of app secret from AppCenter portal to configure {@link Crashes} sdk.
     *                              Pass <code>null</code> if you don't need {@link Crashes} integration for tracking exceptions.
     * @param isDebugMode           indicates whether application is running in debug mode.
     * @param baseDirectory         Base directory for CodePush files.
     * @param serverUrl             CodePush server url.
     * @param appName               application name.
     * @param appVersion            application version.
     * @param appEntryPointProvider instance of {@link CodePushAppEntryPointProvider}.
     * @param platformUtils         instance of {@link CodePushPlatformUtils}.
     * @throws CodePushInitializeException error occurred during the initialization.
     */
    init(_ deploymentKey: String,
         _ appSecret: String,
         _ isDebugMode: Bool,
         _ baseDirectory: String,
         _ serverUrl: String,
         _ appName: String,
         _ appVersion: String,
         _ appEntryPointProvider: CodePushAppEntryPointProvider,
         _ platformUtils: CodePushPlatformUtils) throws {
        
        /* Initialize configuration. */
        self.deploymentKey = deploymentKey
        self.serverUrl = serverUrl
        self.appName = appName
        self.appVersion = appVersion
        
        /* Initialize state */
        self.state = CodePushState()
        
        do {
            self.appEntryPoint = try appEntryPointProvider.getAppEntryPoint()
        } catch {
            print(error)
            throw CodePushErrors.InitializationError
        }
        
        /* Initialize utilities. */
        let fileUtils = FileUtils.sharedInstance;
        let utils = CodePushUtils.sharedInstance;
        let updateUtils = CodePushUpdateUtils.sharedInstance;
        self.utilities = CodePushUtilities(utils, fileUtils, updateUtils, platformUtils)
        
        self.baseDirectory = !baseDirectory.isEmpty ? baseDirectory :
            self.utilities.fileUtils.appendPathComponent(atBasePath: FileManager.default.currentDirectoryPath,
                                                         withComponent: CodePushConstants.CodePushFolderPrefix)
        
        /* Initialize managers. */
        let updateManager = CodePushUpdateManager(self.baseDirectory, platformUtils, fileUtils, utils, updateUtils, nil)
        let settingsManager = CodePushSettingsManager(utils, nil)
        
        let acquisitionManager = CodePushAcquisitionManager(utilities.utils, utilities.fileUtils)
        self.managers = CodePushManagers(updateManager, acquisitionManager, settingsManager)
        
        let configuration = try getNativeConfiguration()
        managers.updateManager.codePushConfiguration = configuration
        managers.settingsManager.codePushConfiguration = configuration
    }
    
    func checkForUpdate(callback completion: @escaping (Result<CodePushRemotePackage?>) -> Void) {
        var configuration: CodePushConfiguration
        do {
            configuration = try getNativeConfiguration()
        } catch {
            completion(Result{throw error})
            return
        }
        checkForUpdate(withKey: configuration.deploymentKey!, callback: completion)
    }
    
    /**
     * Checks whether an update with the following hash has failed.
     *
     * @param packageHash hash to check.
     * @return <code>true</code> if there is a failed update with provided hash, <code>false</code> otherwise.
     */
    func existsFailedUpdate(fromHash packageHash: String) throws -> Bool {
        return try managers.settingsManager.existsFailedUpdate(withHash: packageHash)
    }
    
    /**
     * Indicates whether update with specified packageHash is running for the first time.
     *
     * @param packageHash package hash for check.
     * @return true, if application is running for the first time, false otherwise.
     * @throws CodePushNativeApiCallException if error occurred during the operation.
     */
    //    func isFirstRun(fromHash packageHash: String) -> Bool {
    //        return state.didUpdate! && !packageHash.isEmpty &&
    //            packageHash == managers.updateManager.getCurrentPackageHash()
    //    }
    
    /**
     * Gets native CodePush configuration.
     *
     * @return native CodePush configuration.
     */
    func getNativeConfiguration() throws -> CodePushConfiguration {
        let config = CodePushConfiguration()
        config.appName = !self.appName.isEmpty ? self.appName : CodePushConstants.CodePushDefaultAppName
        config.appVersion = !self.appVersion.isEmpty ? self.appVersion : try getAppVersion()
        config.clientUniqueId = "testDevice"//UIDevice.current.identifierForVendor!.uuidString
        config.deploymentKey = self.deploymentKey
        config.baseDirectory = self.baseDirectory
        config.serverUrl = !self.serverUrl.isEmpty ? self.serverUrl : CodePushConstants.CodePushServer
        //config.packageHash = utilities.updateUtils.getHashForBinaryContents()
        return config
    }
    
    private func getAppVersion() throws -> String {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                        else { throw CodePushErrors.InitializationError }
        return version
    }
    
    /**
     * Asks the CodePush service whether the configured app deployment has an update available
     * using specified deployment key.
     *
     * @param deploymentKey deployment key to use.
     * @return remote package info if there is an update, <code>null</code> otherwise.
     * @throws CodePushNativeApiCallException if error occurred during the execution of operation.
     */
    func checkForUpdate(withKey deploymentKey: String,
                        callback completion: @escaping (Result<CodePushRemotePackage?>) -> Void) {

        var configuration: CodePushConfiguration
        do {
            configuration = try getNativeConfiguration()
        } catch {
            completion(Result{throw error})
            return
        }
        
        configuration.deploymentKey = !deploymentKey.isEmpty ? deploymentKey : configuration.deploymentKey
        do {
            let localPackage = try getUpdateMetadata(inUpdateState: .LATEST)
            let queryPackage = localPackage != nil ? localPackage :
                CodePushLocalPackage.createEmptyPackageForUpdateQuery(withVersion: configuration.appVersion)
            CodePushAcquisitionManager(utilities.utils, utilities.fileUtils)
                .queryUpdate(withConfig: configuration, withPackage: queryPackage!,
                             callback: { result in
                                completion( Result {
                                    let update = try result.resolve()
                                    if (update == nil || update?.packageHash == localPackage?.packageHash) {
                                        return nil
                                    } else {
                                        return update
                                    }
                                })
                })
        } catch {
            completion (Result { throw error })
        }
    }
    
    /**
     * Synchronizes your app assets with the latest release to the configured deployment.
     *
     * @throws CodePushNativeApiCallException if error occurred during the execution of operation.
     */
    func sync(callback completion: @escaping (Result<Bool>) -> Void) {
        self.sync(withOptions: CodePushSyncOptions(), callback: completion)
    }
    
    /**
     * Synchronizes your app assets with the latest release to the configured deployment.
     *
     * @param synchronizationOptions sync options.
     * @throws CodePushNativeApiCallException if error occurred during the execution of operation.
     */
    func sync(withOptions syncOptions: CodePushSyncOptions,
              callback completion: @escaping (Result<Bool>) -> Void) {
        if (syncOptions.deploymentKey.isEmpty) {
            syncOptions.deploymentKey = deploymentKey
        }
        if (syncOptions.installMode == nil) {
            syncOptions.installMode = .ON_NEXT_RESTART
        }
        if (syncOptions.mandatoryInstallMode == nil) {
            syncOptions.mandatoryInstallMode = .IMMEDIATE
        }
        if (syncOptions.checkFrequency == nil) {
            syncOptions.checkFrequency = .ON_APP_START
        }
        
        var configuration: CodePushConfiguration
        do {
            configuration = try getNativeConfiguration()
        } catch {
            completion(Result{throw error})
            return
        }
        
        if (!syncOptions.deploymentKey.isEmpty) {
            configuration.deploymentKey = syncOptions.deploymentKey
        }
        
        //        checkForUpdate(withKey: syncOptions.deploymentKey, callback: { result in
        //                    do {
        //                        let remotePackage = try result.resolve()
        //                        self.doDownloadAndInstall(package: remotePackage!, withOptions: syncOptions, withConfig: configuration, callback: { result in
        //                            do {
        //                                let success = try result.resolve()
        //                            } catch { print(error) }
        //
        //                        })
        //                    } catch {
        //                        print(error)
        //                    }
        //            });
        
        
        let basePackage = CodePushPackage()
        basePackage.deploymentKey = "i4veHSlIOuyvuFKmGOD-Jcyp1uSXHkoQ4e-Tf"
        basePackage.packageHash = "12f376f76b1bfd68103aaa1db84ba5ea7284951e0af02aff33bf7aa880d9ec51"
        basePackage.label = "v14"
        basePackage.isMandatory = false
        basePackage.failedInstall = false
        basePackage.description = "version 1.0.8 working"
        basePackage.appVersion = "1"
        let remotePackage = CodePushRemotePackage.createRemotePackage(fromFailedInstall: false, size: 186598, atUrl: "https://codepush.blob.core.windows.net/storagev2/0GqmGWPkR6xVG8SvaF8QN3wLmbWE12058267-11c6-40ff-b975-6397a0cb8e3e", updateVersion: false, fromPackage: basePackage)
        
        self.doDownloadAndInstall(package: remotePackage, withOptions: syncOptions, withConfig: configuration, callback: { result in
            do {
                let success = try result.resolve()
                print(success)
            } catch { print(error) }
        })
    }
    
    /**
     * Downloads and installs update.
     *
     * @param remotePackage update to use.
     * @param syncOptions   sync options.
     * @param configuration configuration to use.
     * @throws CodePushNativeApiCallException if error occurred during the execution of operation.
     */
    func doDownloadAndInstall(package remotePackage: CodePushRemotePackage,
                              withOptions syncOptions: CodePushSyncOptions,
                              withConfig configuration: CodePushConfiguration,
                              callback completion: @escaping (Result<Bool>) -> Void) {
        downloadUpdate(package: remotePackage, callback: { result in
            completion (Result{
                let localPackage = try result.resolve()
                return try self.installUpdate(withPackage: localPackage)
            })
        })
    }
    
    /**
     * Downloads update.
     *
     * @param updatePackage update to download.
     * @return resulted local package or error
     */
    func downloadUpdate(package updatePackage: CodePushRemotePackage,
                        callback completion: @escaping (Result<CodePushLocalPackage>) -> Void) {
        
        let downloadUrl = updatePackage.downloadURL
        
        managers.updateManager
            .downloadPackage(withHash: updatePackage.packageHash!,
                             atUrl: downloadUrl!,
                             callback: { result in
                                completion ( Result {
                                    do {
                                        let package = try result.resolve()
                                        
                                        let newUpdateFolderPath = self.managers.updateManager.getPackageFolderPath(withHash: updatePackage.packageHash!)
                                        
                                        try self.utilities.fileUtils.createDirectoryIfNotExists(path: newUpdateFolderPath)
                                        
                                        let newUpdateMetadataPath = self.utilities.fileUtils.appendPathComponent(atBasePath: newUpdateFolderPath,
                                                                                                                 withComponent: CodePushConstants.PackageFileName)
                                        let newUpdateFilePath = self.utilities.fileUtils.appendPathComponent(atBasePath: newUpdateFolderPath,
                                                                                                             withComponent: self.appEntryPoint)
                                        
                                        try self.utilities.fileUtils.moveFile(file: package.downloadFile, toDestination: newUpdateFilePath)
                                        let newPackage = CodePushLocalPackage.createLocalPackage(wasFailedInstall: false, isFirstRun: false, isPending: true,
                                                                                                 isDebugOnly: false, withEntryPoint: self.appEntryPoint,
                                                                                                 fromPackage: updatePackage)
                                        
                                        try self.utilities.utils.writeObjectToJsonFile(withObject: newPackage, atPath: newUpdateMetadataPath)
                                        
                                        return newPackage
                                    } catch {
                                        try self.managers.settingsManager.saveFailedUpdate(forPackage: updatePackage)
                                        throw error
                                    }
                                })
            } )
        
    }
    
    /**
     * Installs update.
     *
     * @param updatePackage             update to install.
     * @param installMode               installation mode.
     * @param minimumBackgroundDuration minimum background duration value (see {@link CodePushSyncOptions#minimumBackgroundDuration}).
     * @throws CodePushNativeApiCallException if error occurred during the execution of operation.
     */
    func installUpdate(withPackage updatePackage: CodePushLocalPackage) throws -> Bool {
        try managers.updateManager.installPackage(packageHashToInstall: updatePackage.packageHash)
        return true
    }
    
    /**
     * Retrieves the metadata for an installed update (e.g. description, mandatory)
     * whose state matches the specified <code>updateState</code> parameter.
     *
     * @param updateState current update state.
     * @return installed update metadata.
     * @throws CodePushNativeApiCallException if error occurred during the operation.
     */
    func getUpdateMetadata(inUpdateState updateState: CodePushUpdateState) throws -> CodePushLocalPackage? {
        guard let currentPackage = managers.updateManager.getCurrentPackage() else { return nil }
        
        var currentUpdateIsPending = false
        if (!(currentPackage.packageHash?.isEmpty)!) {
            let currentHash = currentPackage.packageHash
            currentUpdateIsPending = try managers.settingsManager.isPendingUpdate(withHash: currentHash!)
        }
        if (updateState == .PENDING && !currentUpdateIsPending) {
            
            /* The caller wanted a pending update but there isn't currently one. */
            return nil
        } else if (updateState == .RUNNING && currentUpdateIsPending) {
            
            /* The caller wants the running update, but the current one is pending, so we need to grab the previous. */
            let previousPackage = managers.updateManager.getPreviousPackage()
            return previousPackage
        } else {
            /* Enable differentiating pending vs. non-pending updates */
            let packageHash = currentPackage.packageHash
            currentPackage.failedInstall = try managers.settingsManager.existsFailedUpdate(withHash: packageHash!)
            currentPackage.isFirstRun = try isFirstRun(withHash: packageHash!)
            currentPackage.isPending = currentUpdateIsPending
            return currentPackage
        }
    }
    
    /**
     * Indicates whether update with specified packageHash is running for the first time.
     *
     * @param packageHash package hash for check.
     * @return true, if application is running for the first time, false otherwise.
     * @throws CodePushNativeApiCallException if error occurred during the operation.
     */
    func isFirstRun(withHash packageHash: String) throws -> Bool {
        let currentPackageHash = try managers.updateManager.getCurrentPackageHash()
        return state.didUpdate!
            && !packageHash.isEmpty
            && packageHash == currentPackageHash
    }
    
    /**
     * Rolls back package.
     *
     * @throws CodePushGetPackageException if error occurred during getting current update.
     * @throws CodePushRollbackException   if error occurred during rolling back of package.
     * @throws CodePushMalformedDataException
     */
    func rollbackPackage() throws {
        let failedPackage = managers.updateManager.getCurrentPackage()
        try managers.settingsManager.saveFailedUpdate(forPackage: failedPackage!)
        try managers.updateManager.rollbackPackage()
        managers.settingsManager.removePendingUpdate()
    }
}
