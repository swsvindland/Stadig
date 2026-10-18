import ExerciseLibrary
import Foundation
import LiftEngine
import SystemCore
import Testing

@testable import LiftTrack

/// The numbers on every screen, and what typing one in does. The test plan pins English and the US.
@MainActor
@Suite("Format and entry")
struct FormatTests {
    @Test("Loads read by how the exercise is loaded")
    func loads() {
        #expect(Format.load(82.5, unit: .kg) == "82.5 kg")
        #expect(Format.load(nil, unit: .kg) == "Pick a weight")
        #expect(Format.load(0, unit: .kg, basis: .bodyweightPlus) == "Bodyweight")
        #expect(Format.load(10, unit: .kg, basis: .bodyweightPlus) == "+10 kg")
        #expect(Format.load(20, unit: .kg, basis: .assisted) == "20 kg assist")
        #expect(Format.load(0, unit: .kg, basis: .assisted) == "Bodyweight")
        #expect(Format.load(12, unit: .kg, basis: .perHand) == "12 kg each")
        #expect(Format.load(40, unit: .kg, basis: .none) == "")
        #expect(Format.load(100, unit: .lb) == "220.46 lb")
    }

    @Test("Weights and lengths in the person's units, a dash when unknown")
    func weightsAndLengths() {
        #expect(Format.weight(82.46, unit: .kg) == "82.5 kg")
        #expect(Format.weight(nil, unit: .kg) == "—")
        #expect(Format.length(2.54, unit: .inch) == "1 in")
        #expect(Format.length(nil, unit: .cm) == "—")
    }

    @Test("Durations and clocks at the minute's edges")
    func durations() {
        #expect(Format.duration(45) == "45 s")
        #expect(Format.duration(59) == "59 s")
        #expect(Format.duration(60) == "1 min")
        #expect(Format.duration(61) == "1:01")
        #expect(Format.duration(150) == "2:30")
        #expect(Format.clock(125) == "2:05")
        #expect(Format.clock(0) == "0:00")
        #expect(Format.clock(-5) == "0:00")
    }

    @Test("Temperatures, rounded, in either unit")
    func temperatures() {
        #expect(Format.temperature(80, fahrenheit: false) == "80°C")
        #expect(Format.temperature(88.4, fahrenheit: false) == "88°C")
        #expect(Format.temperature(80, fahrenheit: true) == "176°F")
        #expect(Format.rir(0) == "to failure")
        #expect(Format.rir(2) == "2 in reserve")
    }

    @Test("The thermometer steps 2 °C or 5 °F at a time, onto round readings")
    func thermometerSteps() {
        let celsius = Thermometer(celsius: 80, fahrenheit: false) { _ in }
        #expect(celsius.step(by: 1) == 82)
        #expect(celsius.step(by: -1) == 78)
        let fahrenheit = Thermometer(celsius: 80, fahrenheit: true) { _ in }
        #expect(Format.temperature(fahrenheit.step(by: 1), fahrenheit: true) == "180°F")
        #expect(Format.temperature(fahrenheit.step(by: -1), fahrenheit: true) == "170°F")
        // From an odd reading, onto the 5 °F grid.
        let odd = Thermometer(celsius: (183 - 32) * 5 / 9, fahrenheit: true) { _ in }
        #expect(Format.temperature(odd.step(by: 1), fahrenheit: true) == "190°F")
    }

    @Test("A typed load is rounded to what the gym can make, and slips are refused")
    func typedLoads() {
        let kg = Gym.preset(.fullGym, unit: .kg).increments(for: .barbell)
        #expect(LoadControl.typedLoad("100", increments: kg) == 100)
        #expect(LoadControl.typedLoad("102,5", increments: kg) == 102.5)
        #expect(LoadControl.typedLoad(" 60 ", increments: kg) == 60)
        #expect(LoadControl.typedLoad("-5", increments: kg) == nil)
        #expect(LoadControl.typedLoad("abc", increments: kg) == nil)
        #expect(LoadControl.typedLoad("", increments: kg) == nil)
        // A few extra digits: past anything anyone lifts (the engine's limit), and the plate maths would stall on it.
        #expect(LoadControl.typedLoad("100000", increments: kg) == nil)
        let limit = Int(GymIncrements.maximumLoadKg)
        #expect(LoadControl.typedLoad("\(limit)", increments: kg) != nil)
        #expect(LoadControl.typedLoad("\(limit + 1)", increments: kg) == nil)
        let lb = Gym.preset(.fullGym, unit: .lb).increments(for: .barbell)
        #expect(LoadControl.typedLoad("3400", increments: lb) == nil)
        let typed = LoadControl.typedLoad("225", increments: lb)
        #expect(typed.map { Format.load($0, unit: .lb) } == "225 lb")
    }

    @Test("Typed reps are whole numbers from 0 to 100")
    func typedReps() {
        #expect(Stepperish.typedReps("12") == 12)
        #expect(Stepperish.typedReps("0") == 0)
        #expect(Stepperish.typedReps("150") == 100)
        #expect(Stepperish.typedReps("-1") == nil)
        #expect(Stepperish.typedReps("8.5") == nil)
        #expect(Stepperish.typedReps("") == nil)
    }
}
