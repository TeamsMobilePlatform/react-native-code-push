//
//  CodePushBaseCore.swift
//  CodePush
//
//  Copyright © 2018 MSFT. All rights reserved.
//

import Foundation

/**
 * Base core for CodePush.
 */
class CodePushBaseCore {
    
    /**
     * Deployment key for checking for updates.
     */
    var deploymentKey: String
    
    /**
     * CodePush base directory.
     */
    var baseDirectory: URL
    
    /**
     * CodePush server URL.
     */
    var serverUrl: String
    
    /**
     * Current app name.
     */
    var appName: String
    
    /**
     * Current app version.
     */
    var appVersion: String
    
    /**
     * Current state of CodePush update.
     */
    var state: CodePushState
    
    /**
     * Various utilities.
     */
    var utilities: CodePushUtilities
    
    /**
     * Used managers.
     */
    var managers: CodePushManagers
    
    /**
     * Entry point for application.
     */
    var appEntryPoint: String

    /**
     * Creates instance of ```CodePushBaseCore```. Default constructor.
     *
     * Parameter deploymentKey         deployment key.
     * Parameter appSecret             the value of app secret from AppCenter portal to configure Crashes sdk.
     *                                 Pass ```nil``` if you don't need Crashes integration for tracking exceptions.
     * Parameter isDebugMode           indicates whether application is running in debug mode.
     * Parameter baseDirectory         Base directory for CodePush files.
     * Parameter serverUrl             CodePush server url.
     * Parameter appName               application name.
     * Parameter appVersion            application version.
     * Parameter appEntryPointProvider instance of ```CodePushAppEntryPointProvider```.
     * Parameter platformUtils         instance of ```CodePushPlatformUtils```.
     * Throws: CodePushInitializeError if error occurred during the initialization.
     */
    init(_ deploymentKey: String,
         _ appSecret: String,
         _ isDebugMode: Bool,
         _ baseDirectory: URL?,
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
            throw CodePushErrors.initialization(cause: "Failed to retrieve the app entry point")
        }

        /* Initialize utilities. */
        let fileUtils = FileUtils.sharedInstance
        let utils = CodePushUtils.sharedInstance
        let updateUtils = CodePushUpdateUtils.sharedInstance
        self.utilities = CodePushUtilities(utils, fileUtils, updateUtils, platformUtils)

        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        self.baseDirectory = baseDirectory != nil ? baseDirectory! :
            self.utilities.fileUtils.appendPathComponent(atBasePath: documentsDir,
                                                         withComponent: CodePushConstants.CodePushFolderPrefix)

        /* Initialize managers. */
        let updateManager = CodePushUpdateManager(self.baseDirectory, platformUtils, fileUtils, utils, updateUtils, nil)
        let settingsManager = CodePushSettingsManager(utils, nil)

        let acquisitionManager = CodePushAcquisitionManager(utilities.utils, utilities.fileUtils)
        self.managers = CodePushManagers(updateManager, acquisitionManager, settingsManager)

        let configuration = try getNativeConfiguration()
        managers.updateManager.codePushConfiguration = configuration
        managers.settingsManager.codePushConfiguration = configuration

        try initializeUpdateAfterRestart()
    }

    /**
     * Initializes update after app restart.
     *
     * Throws: CodePushGetPackageException    if error occurred during the getting current package.
     * Throws: CodePushPlatformUtilsException if error occurred during usage of ```CodePushPlatformUtils```.
     * Throws: CodePushRollbackException      if error occurred during rolling back of package.
     */
    func initializeUpdateAfterRestart() throws {

        /* Reset the state which indicates that the app was just freshly updated. */
        state.didUpdate = false
        let pendingUpdate = try managers.settingsManager.getPendingUpdate()
        if pendingUpdate != nil {
            let packageMetadata = try managers.updateManager.getCurrentPackage()
            if (packageMetadata == nil || !utilities.platformUtils.isPackageLatest(packageMetadata!, appVersion) &&
                appVersion == packageMetadata?.appVersion) {
                return
            }
            let updateIsLoading = pendingUpdate?.pendingUpdateIsLoading
            if updateIsLoading! {

                /* Pending update was initialized, but notifyApplicationReady was not called.
                 * Therefore, deduce that it is a broken update and rollback. */
                state.needToReportRollback = true
                try rollbackPackage()
            } else {

                /* There is in fact a new update running for the first
                 * time, so update the local state to ensure the client knows. */
                state.didUpdate = true

                /* Mark that we tried to initialize the new update, so that if it crashes,
                 * we will know that we need to rollback when the app next starts. */
                managers.settingsManager.removePendingUpdate()
            }
        }
    }

    /**
     * Asks the CodePush service whether the configured app deployment has an update available
     * using the configured deployment key.
     *
     * Parameter completion - completion handler.
     * Returns: ```CodePushRemotePackage``` if there is an update, ```nil``` otherwise.
     * Throws: Result will throw an exception if an error occurred at any point during the update check.
     */
    func checkForUpdate(callback completion: @escaping (Result<CodePushRemotePackage?>) -> Void) {
        var configuration: CodePushConfiguration
        do {
            configuration = try getNativeConfiguration()
        } catch {
            completion(Result { throw error })
            return
        }
        checkForUpdate(withKey: configuration.deploymentKey!, callback: completion)
    }

    /**
     * Checks whether an update with the following hash has failed.
     *
     * Parameter packageHash hash to check.
     * Returns: ```true``` if there is a failed update with provided hash, ```false``` otherwise.
     */
    func existsFailedUpdate(fromHash packageHash: String) throws -> Bool {
        return try managers.settingsManager.existsFailedUpdate(withHash: packageHash)
    }

    /**
     * Gets native CodePush configuration.
     *
     * Returns: native CodePush configuration.
     * Throws: Initialization error if error occurs during version retrieval
     */
    func getNativeConfiguration() throws -> CodePushConfiguration {
        let config = CodePushConfiguration()
        config.appName = !self.appName.isEmpty ? self.appName : CodePushConstants.CodePushDefaultAppName
        config.appVersion = !self.appVersion.isEmpty ? self.appVersion : try getAppVersion()
        config.clientUniqueId = (UIDevice.current.identifierForVendor ?? UUID()).uuidString
        config.deploymentKey = self.deploymentKey
        config.baseDirectory = self.baseDirectory
        config.serverUrl = !self.serverUrl.isEmpty ? self.serverUrl : CodePushConstants.CodePushServer
        return config
    }

    /**
     * Retrieves the app version from the Bundle
     * Returns: The Short Version String from the application bundle
    */
    private func getAppVersion() throws -> String {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            else { throw CodePushErrors.initialization(cause: "Failed to retrieve version from Bundle") }
        return version
    }

    /**
     * Asks the CodePush service whether the configured app deployment has an update available
     * using specified deployment key.
     *
     * Parameter deploymentKey - deployment key to use.
     * Parameter completion - completion handler
     * Returns: remote package info if there is an update, ```nil``` otherwise.
     */
    func checkForUpdate(withKey deploymentKey: String,
                        callback completion: @escaping (Result<CodePushRemotePackage?>) -> Void) {

        var configuration: CodePushConfiguration
        do {
            configuration = try getNativeConfiguration()
        } catch {
            completion(Result { throw CodePushErrors.checkForUpdate(cause: error) })
            return
        }

        configuration.deploymentKey = !deploymentKey.isEmpty ? deploymentKey : configuration.deploymentKey
        do {
            let localPackage = try getUpdateMetadata(inUpdateState: .latest)
            var queryPackage = localPackage
            if !self.appVersion.isEmpty {
                queryPackage = CodePushLocalPackage.createEmptyPackageForUpdateQuery(withVersion: self.appVersion)
            } else if queryPackage == nil{
                queryPackage = CodePushLocalPackage.createEmptyPackageForUpdateQuery(withVersion: configuration.appVersion)
            }
            CodePushAcquisitionManager(utilities.utils, utilities.fileUtils)
                .queryUpdate(withConfig: configuration, withPackage: queryPackage!,
                             callback: { result in
                                completion( Result {
                                    let update = try result.resolve()
                                    if update == nil || update?.packageHash == localPackage?.packageHash {
                                        return nil
                                    } else {
                                        return update
                                    }
                                })
                })
        } catch {
            completion (Result { throw CodePushErrors.checkForUpdate(cause: error) })
        }
    }

    /**
     * Synchronizes your app assets with the latest release to the configured deployment.
     *
     * Returns: ```Result``` - ```true``` if sync succeeded. ```false``` if there was nothing to sync
     */
    func sync(callback completion: @escaping (Result<Bool>) -> Void) {
        self.sync(withOptions: CodePushSyncOptions(), callback: completion)
    }

    /**
     * Synchronizes your app assets with the latest release to the configured deployment.
     *
     * Parameter synchronizationOptions sync options.
     * Returns: ```true``` if sync succeeded. ```false``` if there was nothing to sync
     */
    func sync(withOptions syncOptions: CodePushSyncOptions,
              callback completion: @escaping (Result<Bool>) -> Void) {
        if syncOptions.deploymentKey.isEmpty {
            syncOptions.deploymentKey = deploymentKey
        }
        if syncOptions.installMode == nil {
            syncOptions.installMode = .onNextRestart
        }
        if syncOptions.mandatoryInstallMode == nil {
            syncOptions.mandatoryInstallMode = .immediate
        }
        if syncOptions.checkFrequency == nil {
            syncOptions.checkFrequency = .onAppStart
        }

        var configuration: CodePushConfiguration
        do {
            configuration = try getNativeConfiguration()
        } catch {
            completion(Result { throw CodePushErrors.sync(cause: error) })
            return
        }

        if !syncOptions.deploymentKey.isEmpty {
            configuration.deploymentKey = syncOptions.deploymentKey
        }

        checkForUpdate(withKey: syncOptions.deploymentKey, callback: { result in
            do {
                let remotePackage = try result.resolve()
                if remotePackage == nil {
                    completion(Result { return false })
                } else {
                    self.doDownloadAndInstall(package: remotePackage!, withOptions: syncOptions,
                                              withConfig: configuration, callback: { result in
                        completion(Result { return try result.resolve() })
                    })
                }
            } catch {
                completion(Result { throw CodePushErrors.sync(cause: error) })
            }
        })
    }

    /**
     * Downloads and installs update.
     *
     * Parameter remotePackage update to use.
     * Parameter syncOptions   sync options.
     * Parameter configuration configuration to use.
     * Parameter completion completion handler
     */
    func doDownloadAndInstall(package remotePackage: CodePushRemotePackage,
                              withOptions syncOptions: CodePushSyncOptions,
                              withConfig configuration: CodePushConfiguration,
                              callback completion: @escaping (Result<Bool>) -> Void) {
        downloadUpdate(package: remotePackage, callback: { result in
            completion ( Result {
                let localPackage = try result.resolve()
                return try self.installUpdate(withPackage: localPackage)
            })
        })
    }

    /**
     * Downloads update.
     *
     * Parameter updatePackage update to download.
     * Parameter completion - completion handler
     * Returns: resulted local package or error
     */
    func downloadUpdate(package updatePackage: CodePushRemotePackage,
                        callback completion: @escaping (Result<CodePushLocalPackage>) -> Void) {

        let downloadUrl = updatePackage.downloadURL

        managers
            .updateManager
            .downloadPackage(withHash: updatePackage.packageHash!,
                             atUrl: downloadUrl!,
                             callback: { result in
                                completion ( Result {
                                    do {
                                        let downloadResult = try result.resolve()
                                        var appEntryPoint: String = ""

                                        // Create the directory if it doesn't exist
                                        let newUpdateFolderPath = self.managers.updateManager.getPackageFolderPath(withHash: updatePackage.packageHash!)
                                        try self.utilities.fileUtils.createDirectoryIfNotExists(path: newUpdateFolderPath)

                                        // Move the file to our app working directory
                                        let fileName = downloadResult.isZip ? CodePushConstants.ZipFileName : self.appEntryPoint
                                        let newUpdateDirectory = self.utilities.fileUtils.appendPathComponent(atBasePath: newUpdateFolderPath,
                                                                                                              withComponent: fileName)
                                        try self.utilities.fileUtils.moveFile(file: downloadResult.downloadFile,
                                                                              toDestination: newUpdateDirectory)
                                        if downloadResult.isZip {
                                            // The download is a zip, unzip it and merge the contents with the current package
                                            try self.managers.updateManager.unzipPackage(withPackage: newUpdateDirectory,
                                                                                         toDestination: newUpdateFolderPath)
                                            let appName = try self.getNativeConfiguration().appName
                                            appEntryPoint = try self.managers.updateManager.mergeDiff(newUpdate: newUpdateFolderPath,
                                                                                                      entryPoint: self.appEntryPoint,
                                                                                                      withApp: appName!)
                                        }

                                        // Create the localpackage and write the metadata to app.json
                                        let newPackage = CodePushLocalPackage.createLocalPackage(wasFailedInstall: false,
                                                                                                 isFirstRun: false,
                                                                                                 isPending: true,
                                                                                                 withEntryPoint: appEntryPoint,
                                                                                                 fromPackage: updatePackage)

                                        let newUpdateMetadataPath = self.utilities.fileUtils.appendPathComponent(atBasePath: newUpdateFolderPath,
                                                                                                                 withComponent: CodePushConstants.PackageFileName)
                                        try self.utilities.utils.writeObjectToJsonFile(withObject: newPackage,
                                                                                       atPath: newUpdateMetadataPath)
                                        return newPackage
                                    } catch {
                                        try self.managers.settingsManager.saveFailedUpdate(forPackage: updatePackage)
                                        throw CodePushErrors.download(cause: error)
                                    }
                                })
            })

    }

    /**
     * Installs update.
     *
     * Parameter updatePackage             update to install.
     * Throws: Install error if error occurs during installation of package
     */
    func installUpdate(withPackage updatePackage: CodePushLocalPackage) throws -> Bool {

        let removeCurrent = try managers.settingsManager.isPendingUpdate(withHash: nil)

        try managers.updateManager
            .installPackage(packageHash: updatePackage.packageHash, removeCurrentUpdate: removeCurrent)

        let pendingHash = updatePackage.packageHash
        if (pendingHash?.isEmpty)! {
            throw CodePushErrors.install(cause: "Update to install has no hash value")
        } else {
            let pendingUpdate = CodePushPendingUpdate()
            pendingUpdate.pendingUpdateHash =  pendingHash
            pendingUpdate.pendingUpdateIsLoading = false
            try managers.settingsManager.savePendingUpdate(forUpdate: pendingUpdate)
        }
        return true
    }

    /**
     * Retrieves the metadata for an installed update (e.g. description, mandatory)
     * whose state matches the specified ```updateState``` parameter.
     *
     * Parameter updateState current update state.
     * Returns: installed update metadata or ```nil```
     * Throws: Error if fails to retrieve the metadata associated with the desired state
     */
    public func getUpdateMetadata(inUpdateState updateState: CodePushUpdateState) throws -> CodePushLocalPackage? {
        let currentPackage = try managers.updateManager.getCurrentPackage()

        if currentPackage == nil {
            return nil
        }

        var currentUpdateIsPending = false
        if !(currentPackage!.packageHash?.isEmpty)! {
            let currentHash = currentPackage!.packageHash
            currentUpdateIsPending = try managers.settingsManager.isPendingUpdate(withHash: currentHash!)
        }
        if updateState == .pending && !currentUpdateIsPending {

            /* The caller wanted a pending update but there isn't currently one. */
            return nil
        } else if updateState == .running && currentUpdateIsPending {

            /* The caller wants the running update, but the current one is pending,
             so we need to grab the previous. */
            let previousPackage = try managers.updateManager.getPreviousPackage()
            return previousPackage
        } else {
            /* Enable differentiating pending vs. non-pending updates */
            let packageHash = currentPackage!.packageHash
            currentPackage!.failedInstall = try managers.settingsManager.existsFailedUpdate(withHash: packageHash!)
            currentPackage!.isFirstRun = try isFirstRun(withHash: packageHash!)
            currentPackage!.isPending = currentUpdateIsPending
            return currentPackage
        }
    }

    /**
     * Indicates whether update with specified packageHash is running for the first time.
     *
     * Parameter packageHash package hash for check.
     * Returns: ```true```, if application is running for the first time, ```false``` otherwise.
     * Throws: Error if fails to resolve the current package
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
     * Throws: Error if fails to resolve the currentPackage
     */
    func rollbackPackage() throws {
        let failedPackage = try managers.updateManager.getCurrentPackage()
        if failedPackage != nil {
            try managers.settingsManager.saveFailedUpdate(forPackage: failedPackage!)
            try managers.updateManager.rollbackPackage()
            managers.settingsManager.removePendingUpdate()
        }
    }

    /**
     * Gets the path of the installed package
     * Returns: The directory of the installed package
     */
    public func getCurrentPackagePath() throws -> URL? {
        return try managers.updateManager.getCurrentPackagePath()
    }

    /**
     * Gets the path of the previously installed package
     * Returns: The directory of the previously installed package
     */
    public func getPreviousPackagePath() throws -> URL? {
        return try managers.updateManager.getPreviousPackagePath()
    }
}
