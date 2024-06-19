//
//  CacheSerializer.swift
//  Kingfisher
//
//  Created by Wei Wang on 2016/09/02.
//
//  Copyright (c) 2018 Wei Wang <onevcat@gmail.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

import Foundation
import UIKit
/// An `CacheSerializer` would be used to convert some data to an image object for
/// retrieving from disk cache and vice versa for storing to disk cache.
public protocol CacheSerializer {
    
    /// Get the serialized data from a provided image
    /// and optional original data for caching to disk.
    ///
    ///
    /// - parameter image:    The image needed to be serialized.
    /// - parameter original: The original data which is just downloaded. 
    ///                       If the image is retrieved from cache instead of
    ///                       downloaded, it will be `nil`.
    ///
    /// - returns: A data which will be stored to cache, or `nil` when no valid
    ///            data could be serialized.
    func data(with image: Image, original: Data?) -> Data?
    
    /// Get an image deserialized from provided data.
    ///
    /// - parameter data:    The data from which an image should be deserialized.
    /// - parameter options: Options for deserialization.
    ///
    /// - returns: An image deserialized or `nil` when no valid image 
    ///            could be deserialized.
    func image(with data: Data, options: KingfisherOptionsInfo?) -> Image?
}


/// `DefaultCacheSerializer` is a basic `CacheSerializer` used in default cache of
/// Kingfisher. It could serialize and deserialize PNG, JEPG and GIF images. For 
/// image other than these formats, a normalized `pngRepresentation` will be used.
public struct DefaultCacheSerializer: CacheSerializer {
    
    public static let `default` = DefaultCacheSerializer()
    private init() {}
    
    public func data(with image: Image, original: Data?) -> Data? {
        let imageFormat = original?.kf.imageFormat ?? .unknown
        
        var jpegData = image.kf.jpegRepresentation(compressionQuality: 1.0)
        
        if imageFormat == .JPEG {
            jpegData = self.addUserCommentToJpeg(jpeg: jpegData, original: original)
        }

        let data: Data?
        switch imageFormat {
        case .PNG: data = image.kf.pngRepresentation()
        case .JPEG: data = jpegData
        case .GIF: data = image.kf.gifRepresentation()
        case .unknown: data = original ?? image.kf.normalized.kf.pngRepresentation()
        }

        return data
    }
    
    
    public func addUserCommentToJpeg(jpeg:Data?, original: Data?) -> Data? {
        if let jpegData = jpeg, let originalData = original {
            let userComment = GeoTagImage.getMetaDataUserComment(from:originalData, needShowLog: true)
            if userComment != "" {
                let newData = GeoTagImage.mark(jpegData, userComment: userComment)
                return newData
            }
        }
        return jpeg
    }
    
    public func image(with data: Data, options: KingfisherOptionsInfo?) -> Image? {
        let options = options ?? KingfisherEmptyOptionsInfo
        return Kingfisher<Image>.image(
            data: data,
            scale: options.scaleFactor,
            preloadAllAnimationData: options.preloadAllAnimationData,
            onlyFirstFrame: options.onlyLoadFirstFrame)
    }
}


open class GeoTagImage: NSObject {
    
    /// Writes GPS data into the meta data.
    /// - Parameters:
    ///   - data: Coordinate meta data will be written to the copy of this data.
    ///   - coordinate: Cooordinates to write to meta data.
    @objc public static func mark(_ data: Data, userComment: String) -> Data {
        
        if userComment == "" {
            return data
        }
        
        var source: CGImageSource? = nil
        source = CGImageSourceCreateWithData((data as CFData?)!, nil)
        // Get all the metadata in the image
        let metadata = CGImageSourceCopyPropertiesAtIndex(source!, 0, nil) as? [AnyHashable: Any]
        // Make the metadata dictionary mutable so we can add properties to it
        var metadataAsMutable = metadata
        var EXIFDictionary = (metadataAsMutable?[(kCGImagePropertyExifDictionary as String)]) as? [AnyHashable: Any]
        var GPSDictionary = (metadataAsMutable?[(kCGImagePropertyGPSDictionary as String)]) as? [AnyHashable: Any]
        
        if !(EXIFDictionary != nil) {
            // If the image does not have an EXIF dictionary (not all images do), then create one.
            EXIFDictionary = [:]
        }
        if !(GPSDictionary != nil) {
            GPSDictionary = [:]
        }
        
        // add coordinates in the GPS Dictionary
        //    GPSDictionary![(kCGImagePropertyGPSLatitude as String)] = "12.123"
        //    GPSDictionary![(kCGImagePropertyGPSLongitude as String)] = "13.123"
        EXIFDictionary![(kCGImagePropertyExifUserComment as String)] = userComment
        
        
        // Add our modified EXIF data back into the image’s metadata
        metadataAsMutable!.updateValue(GPSDictionary!, forKey: kCGImagePropertyGPSDictionary)
        metadataAsMutable!.updateValue(EXIFDictionary!, forKey: kCGImagePropertyExifDictionary)
        
        // This is the type of image (e.g., public.jpeg)
        let UTI: CFString = CGImageSourceGetType(source!)!
        
        // This will be the data CGImageDestinationRef will write into
        let dest_data = NSMutableData()
        let destination: CGImageDestination = CGImageDestinationCreateWithData(dest_data as CFMutableData, UTI, 1, nil)!
        // Add the image contained in the image source to the destination, overidding the old metadata with our modified metadata
        CGImageDestinationAddImageFromSource(destination, source!, 0, (metadataAsMutable as CFDictionary?))
        
        // Tells the destination to write the image data and metadata into our data object.
        // It will return false if something goes wrong
        _ = CGImageDestinationFinalize(destination)
        
        return (dest_data as Data)
    }
    
    /// Prints the Meta Data from the Data.
    /// - Parameter data: Meta data will be printed of this object.
    @objc public static func getMetaDataUserComment(from data: Data, needShowLog: Bool = false) -> String {
        if let imageSource = CGImageSourceCreateWithData(data as CFData, nil) {
            let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil)
            if let dict = imageProperties as? [String: Any] {
                if(needShowLog) {
                    print(dict)
                }
                if let exif = dict[kCGImagePropertyExifDictionary as String] as? [String: Any], let userComment = exif[kCGImagePropertyExifUserComment as String] as? String {
                    return userComment
                }
            }
        }
        return ""
    }
}
