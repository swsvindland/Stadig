import Testing
@testable import FoodDatabase

@Suite("Barcodes")
struct BarcodeTests {
    @Test("barcode identity preserves leading zeroes and validates check digits")
    func identity() {
        for code in ["036000291452", "0036000291452", "00036000291452", " 036000291452\n"] {
            #expect(Barcode.keys(for: code) == ["00036000291452"], "\(code)")
            #expect(Barcode.isValid(code))
        }
        for code in ["036000291453", "abcd", "36000291452", "123", "00036000291452 OR 1=1", ""] {
            #expect(Barcode.keys(for: code).isEmpty, "\(code)")
            #expect(!Barcode.isValid(code))
        }
    }

    @Test("UPC-E codes expand to UPC-A, first when the scanner read a UPC-E symbol")
    func upcE() {
        // 04252614 is UPC-E for 042100005264.
        #expect(Barcode.expandUPCE("04252614") == "042100005264")
        #expect(Barcode.checkDigitValid("042100005264"))
        #expect(Barcode.keys(for: "04252614", symbology: .upcE).first == "00042100005264")
        #expect(Barcode.keys(for: "04252614", symbology: .ean8) == (Barcode.checkDigitValid("04252614") ? ["00000004252614"] : []))
        #expect(Barcode.keys(for: "04252614").contains("00042100005264"))
        // Each last digit places the manufacturer and product digits differently.
        #expect(Barcode.expandUPCE("01234505") == "012000003455")
        #expect(Barcode.expandUPCE("01234531") == "012300000451")
        #expect(Barcode.expandUPCE("01234544") == "012340000054")
        #expect(Barcode.expandUPCE("01234515") == "012100003455")
        #expect(Barcode.expandUPCE("01234556") == "012345000056")
    }

    @Test("EAN-8 and ITF-14 codes are keyed as printed")
    func otherLengths() {
        #expect(Barcode.keys(for: "96385074") == ["00000096385074"])
        #expect(Barcode.keys(for: "10036000291459") == ["10036000291459"])
    }
}
