//
//  CodePushUtils.swift
//  CodePush
//
//  Copyright © 2018 MSFT. All rights reserved.
//

import Foundation

/**
 * Common utils for each platform.
 */
class CodePushUtils {

    /**
     * Returns the CodePushUtils Singleton
     */
    static let sharedInstance = CodePushUtils()

    /**
     * Instance of fileUtils to work with
     */
    var fileUtils: FileUtils

    /**
     * Encoder used to encode objects to JSON
     */
    var encoder: JSONEncoder
    
    /**
     * Decoder used to convert JSON to objects
     */
    var decoder: JSONDecoder

    private init() {
        self.fileUtils = FileUtils.sharedInstance
        self.encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        self.decoder = JSONDecoder()
    }

    /**
     * Parses JSON from file.
     *
     * Parameter filePath path to file.
     * Returns: parsed JSON instance.
     * Throws: Error if fails to read from the file system
     */
    func getJsonObjectFromFile(atPath filePath: URL) throws -> Data {
        let contents = try fileUtils.readFileToString(atPath: filePath)
        return contents.data(using: .utf8)!
    }

    /**
     * Converts Object instance to JSON string.
     *
     * Parameter object instance.
     * Returns: the json string.
     * Throws: Error if the encoder fails to encode the object
     */
    func convertObjectToJsonString<T>(withObject object: T) throws -> String where T: Codable {
        let data = try encoder.encode(object)
        return String(data: data, encoding: .utf8)!
    }

    /**
     * Gets information from json file and converts it to an object of specified type.
     *
     * Parameter filePath path to file with json contents.
     * Returns: object of type T.
     * Throws: Error if fails to read the object from the file,
     * or if the decoder fails to decode the object
     */
    func getObjectFromJsonFile<T>(_ filePath: URL) throws -> T where T: Codable {
        let json = try getJsonObjectFromFile(atPath: filePath)
        return try decoder.decode(T.self, from: json)
    }

    /**
     * Saves object of specified type to a file as json string.
     *
     * Parameter object   object to be saved.
     * Parameter filePath path to file.
     * Parameter <T>      the type of the desired object.
     * Throws: Error if fails to encode the object, or write the object to the file system.
     */
    func writeObjectToJsonFile<T>(withObject object: T, atPath filePath: URL) throws where T: Codable {
        let jsonString = try convertObjectToJsonString(withObject: object)
        try fileUtils.writeToFile(withContent: jsonString, atPath: filePath)
    }

    /**
     * Writes JSON to file.
     *
     * Parameter json     JSON object instance.
     * Parameter filePath path to file.
     * Throws: Error if fails to write to the file system.
     */
    func writeJsonToFile(withJson json: Data, atPath filePath: URL) throws {
        let jsonString = String(data: json, encoding: .utf8)
        try fileUtils.writeToFile(withContent: jsonString!, atPath: filePath)
    }

    /**
     * Converts Object instance to JSON.
     *
     * Parameter object JSON instance.
     * Returns: JSON instance.
     * Throws: Error if the encoder fails to encode the object.
     */
    func convertObjectToJsonObject<T>(withObject object: T) throws -> Data where T: Codable {
        return try encoder.encode(object)
    }

    /**
     * Converts json string to specified class.
     *
     * Parameter stringObject JSON string.
     * Returns: instance of T.
     * Throws: error if decoder fails to decode the JSON.
     */
    func convertStringToObject<T>(withString json: String) throws -> T where T: Codable {
        let data = json.data(using: .utf8)
        return try decoder.decode(T.self, from: data!)
    }

    /**
     * Converts object to an array of query items
     *
     * Parameter object      object.
     * Returns: an array of query items
     */
    func getQueryItems(fromObject object: AnyObject) -> [URLQueryItem] {
        let mirror = Mirror(reflecting: object)
        return mirror.children.filter { field in        
            if case Optional<Any>.some(_) = field.value {
                return true
            } else {
                return false
            }
        }.map { child -> URLQueryItem in
            return URLQueryItem(name: child.label!, value: child.value as? String)
        }
    }
}
