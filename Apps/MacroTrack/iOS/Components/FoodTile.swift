import NutritionEngine
import SwiftUI

/// The square a food's marker sits in, the same wherever a food is listed or opened.
enum TileSize {
    /// A row in a list: the Log tab's cards, search, a meal's foods.
    static let row: CGFloat = 36
    /// A row in a table of many, on a wide screen.
    static let table: CGFloat = 28
    /// A food opened: its amount, details or numbers.
    static let header: CGFloat = 44
}

/// A food's marker, from its name, in its square. Decoration: the name beside it says what it is.
struct FoodTile: View {
    let name: String
    var size = TileSize.row
    /// For a row sitting straight on the page, which the inset colour would vanish into.
    var fill = Color.insetBackground

    var body: some View {
        Text(FoodMarker.of(name)).font(.system(size: size * 0.56)).tile(size, fill: fill)
    }
}

/// What a row of several foods has in place of a food's marker, so a list of both stays in line.
struct MealTile: View {
    var size = TileSize.row

    var body: some View {
        Image(systemName: "fork.knife").font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(Color.accentColor).tile(
            size, fill: .insetBackground)
    }
}

extension View {
    fileprivate func tile(_ size: CGFloat, fill: Color) -> some View {
        frame(width: size, height: size)
            .background(fill, in: .rect(cornerRadius: size * 0.3))
            .accessibilityHidden(true)
    }
}

/// A food's name and brand, with its marker: the marker follows the name as it's typed.
struct FoodNameFields: View {
    @Binding var name: String
    @Binding var brand: String
    /// "foodEditor": gives "foodEditor.name" and "foodEditor.brand".
    let identifier: String

    var body: some View {
        HStack(spacing: 12) {
            FoodTile(name: name, size: TileSize.header)
            VStack(spacing: 8) {
                TextField("Name", text: $name, prompt: Text("Name")).accessibilityIdentifier("\(identifier).name")
                Divider()
                TextField("Brand", text: $brand, prompt: Text("Brand")).accessibilityIdentifier("\(identifier).brand")
            }
            .labelsHidden()
        }
    }
}

/// The glyph of a button in a food's header. Every one gets the same box, because a box follows its
/// own glyph otherwise, and the row's top alignment then puts each glyph at a different height.
struct HeaderIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol).fontWeight(.semibold).frame(width: 30, height: 30).contentShape(.circle)
    }
}
