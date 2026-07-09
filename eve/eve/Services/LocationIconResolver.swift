//
//  LocationIconResolver.swift
//  Eve
//
//  Decides which SF Symbol represents a saved place.
//
//  Two layers, in order:
//  1. MapKit's own point-of-interest category on the confirmed pin —
//     deterministic and instant, used whenever the picked place carries one.
//  2. The on-device Foundation Model (see
//     `FoundationModelService.classifyPlaceIcon`) — fills the gap for plain
//     addresses, homes, and obscure places MapKit can't categorize. Its
//     output is validated against `catalog`, so the UI can never end up
//     with a nonexistent symbol name.
//

import Foundation
import MapKit

enum LocationIconResolver {

    static let defaultIcon = "mappin.and.ellipse"

    /// Every icon a place is allowed to use, with the meaning the model is
    /// told. One list drives both the AI instructions and output validation
    /// so the two can never drift apart.
    static let catalog: [(symbol: String, meaning: String)] = [
        ("house.fill", "a home, apartment, boarding house, or residence"),
        ("building.2.fill", "an office building or workplace"),
        ("briefcase.fill", "a coworking space or business venue"),
        ("graduationcap.fill", "a school, campus, university, or academy"),
        ("book.fill", "a library or bookstore"),
        ("fork.knife", "a restaurant, warung, or any place to eat"),
        ("cup.and.saucer.fill", "a cafe or coffee shop"),
        ("cart.fill", "a supermarket, grocery, or minimarket"),
        ("bag.fill", "a mall, shop, or retail store"),
        ("dumbbell.fill", "a gym or fitness center"),
        ("sportscourt.fill", "a sports venue, court, field, or stadium"),
        ("cross.case.fill", "a hospital, clinic, or doctor's office"),
        ("pill.fill", "a pharmacy or drugstore"),
        ("airplane", "an airport"),
        ("tram.fill", "a train/bus station or public transport stop"),
        ("fuelpump.fill", "a gas or EV charging station"),
        ("car.fill", "a parking area, car rental, or workshop"),
        ("tree.fill", "a park, garden, or outdoor/nature spot"),
        ("beach.umbrella.fill", "a beach or seaside resort"),
        ("film.fill", "a cinema or theater"),
        ("gamecontroller.fill", "an arcade or entertainment venue"),
        ("pawprint.fill", "a vet, pet shop, or zoo"),
        ("scissors", "a salon, barber, or spa"),
        ("building.columns.fill", "a bank, ATM, museum, or civic building"),
        ("envelope.fill", "a post office or courier point"),
        ("bed.double.fill", "a hotel, hostel, or villa"),
        (defaultIcon, "anything else or unclear"),
    ]

    static let allowedSymbols = Set(catalog.map(\.symbol))

    /// The "Allowed icons" section of the model's instructions, generated
    /// from `catalog` so the prompt always matches what validation accepts.
    static var promptCatalog: String {
        catalog.map { "- \($0.symbol) — \($0.meaning)" }.joined(separator: "\n")
    }

    /// Deterministic icon for a MapKit point-of-interest category, or nil
    /// when the category is missing/unmapped and the AI should decide.
    static func icon(for category: MKPointOfInterestCategory?) -> String? {

        guard let category else { return nil }

        switch category {
        case .airport: return "airplane"
        case .amusementPark: return "gamecontroller.fill"
        case .atm, .bank: return "building.columns.fill"
        case .bakery, .brewery, .restaurant, .winery: return "fork.knife"
        case .beach: return "beach.umbrella.fill"
        case .cafe: return "cup.and.saucer.fill"
        case .campground, .nationalPark, .park: return "tree.fill"
        case .carRental, .parking: return "car.fill"
        case .evCharger, .gasStation: return "fuelpump.fill"
        case .fitnessCenter: return "dumbbell.fill"
        case .foodMarket: return "cart.fill"
        case .hospital: return "cross.case.fill"
        case .hotel: return "bed.double.fill"
        case .library: return "book.fill"
        case .movieTheater, .theater: return "film.fill"
        case .museum: return "building.columns.fill"
        case .pharmacy: return "pill.fill"
        case .postOffice: return "envelope.fill"
        case .publicTransport: return "tram.fill"
        case .school, .university: return "graduationcap.fill"
        case .stadium: return "sportscourt.fill"
        case .store: return "bag.fill"
        case .zoo: return "pawprint.fill"
        default: return nil
        }

    }

}
