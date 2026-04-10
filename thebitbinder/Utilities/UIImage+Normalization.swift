//
//  UIImage+Normalization.swift
//  thebitbinder
//
//  Created by April 7, 2026.
//

import UIKit

extension UIImage {
    
    /// Corrects the orientation of a UIImage to ensure it is always `.up`.
    /// This is useful for images sourced from cameras or other inputs where orientation metadata may be present.
    ///
    /// - Returns: A new `UIImage` with orientation fixed to `.up`, or the original image if no correction is needed.
    func normalized() -> UIImage {
        // If the image is already in the correct orientation, no work is needed.
        guard imageOrientation != .up else {
            return self
        }
        
        // Begin a new image context to redraw the image.
        // Using UIGraphicsImageRenderer ensures the best quality and memory management.
        return UIGraphicsImageRenderer(size: size).image { _ in
            // The `draw` method respects the image's orientation and redraws it correctly.
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
