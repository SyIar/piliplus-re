import SwiftUI
import UIKit

struct HomeFeedLayoutMetrics {
    let mode: HomeFeedLayout
    let doubleColumns: [GridItem]
    let feedColumns: [GridItem]
    let feedSpacing: CGFloat
    let feedHorizontalPadding: CGFloat
    let singleColumnHorizontalPadding: CGFloat
    let singleColumnFixedCoverSize: CGSize?
    let doubleColumnFixedCoverSize: CGSize?
    let borderedSingleColumnCoverSize: CGSize?

    init(mode: HomeFeedLayout, containerWidth: CGFloat,
         allowsWideGrid: Bool = UIDevice.current.userInterfaceIdiom == .pad) {
        self.mode = mode
        let doubleColumnSpacing: CGFloat = 12
        let doubleColumnCoverHeightRatio: CGFloat = mode == .borderedDoubleColumn ? 10 / 16 : 9 / 16
        // Phones keep two columns, including landscape. Tablet windows add
        // columns only when each card can retain a comfortable reading width.
        let availableWidth = max(0, containerWidth - 24)
        let columnCount = allowsWideGrid
            ? min(4, max(2, Int((availableWidth + doubleColumnSpacing) / (240 + doubleColumnSpacing))))
            : 2
        doubleColumns = Array(repeating: GridItem(.flexible(), spacing: doubleColumnSpacing), count: columnCount)
        singleColumnHorizontalPadding = 16

        switch mode {
        case .singleColumn, .borderedSingleColumn:
            feedColumns = [
                GridItem(.flexible(minimum: 0), spacing: 0)
            ]
            feedSpacing = 0
            feedHorizontalPadding = 0
        case .doubleColumn:
            feedColumns = doubleColumns
            feedSpacing = 16
            feedHorizontalPadding = 12
        case .borderedDoubleColumn:
            feedColumns = doubleColumns
            feedSpacing = 18
            feedHorizontalPadding = 12
        }

        let singleWidth = containerWidth - singleColumnHorizontalPadding * 2
        if singleWidth > 0 {
            singleColumnFixedCoverSize = CGSize(width: singleWidth, height: singleWidth * 9 / 16)
        } else {
            singleColumnFixedCoverSize = nil
        }

        let doubleWidth = (containerWidth - (feedHorizontalPadding * 2)
            - doubleColumnSpacing * CGFloat(columnCount - 1)) / CGFloat(columnCount)
        if doubleWidth > 0 {
            doubleColumnFixedCoverSize = CGSize(width: doubleWidth, height: doubleWidth * doubleColumnCoverHeightRatio)
        } else {
            doubleColumnFixedCoverSize = nil
        }

        if singleWidth > 0 {
            borderedSingleColumnCoverSize = CGSize(width: 140, height: 88)
        } else {
            borderedSingleColumnCoverSize = nil
        }
    }
}
