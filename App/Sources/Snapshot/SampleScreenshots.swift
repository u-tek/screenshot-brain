import Media
import SwiftUI

/// Made-up screenshots for the sample items in design snapshots, drawn as simple app pages (and
/// one landscape photo), so cards and tiles show something shaped like the real thing. Without
/// them every screenshot slot renders empty, and layout bugs that only real images cause (a
/// photo the wrong shape for its card) never show up in a snapshot.
@MainActor
enum SampleScreenshots {
    private static var isRegistered = false

    static func register() {
        guard !isRegistered else { return }
        isRegistered = true
        var samples: [String: CGImage] = [:]
        let gig = page(
            title: "Mallrat",
            subtitle: "Butterfly Blue Tour",
            lines: ["Sun 11 October · Doors 7pm", "Enmore Theatre, Newtown", "$69.90"],
            button: "Get tickets",
            hero: [Color(red: 0.95, green: 0.42, blue: 0.2), Color(red: 0.35, green: 0.08, blue: 0.05)]
        )
        let market = page(
            title: "Night Market",
            subtitle: "Dixon St, Chinatown",
            lines: ["Fridays 5pm–11pm", "Street food · Live music", "Free entry"],
            button: "Directions",
            hero: [Color(red: 0.98, green: 0.7, blue: 0.3), Color(red: 0.45, green: 0.15, blue: 0.1)]
        )
        let shoes = page(
            title: "Salomon XT-6",
            subtitle: "Vanilla Ice / Almond Milk",
            lines: ["Sale ends Thursday", "Sizes 7–12", "$189.99  $269.99"],
            button: "Add to bag",
            hero: [Color(white: 0.92), Color(white: 0.7)]
        )
        let noodles = page(
            title: "Crispy chilli noodles",
            subtitle: "15 minutes · Serves 2",
            lines: ["200g wide rice noodles", "2 tbsp chilli crisp", "½ cup peanuts"],
            button: "Save recipe",
            hero: [Color(red: 0.85, green: 0.25, blue: 0.12), Color(red: 0.3, green: 0.1, blue: 0.05)]
        )
        samples["sample-Mallrat at the Enmore"] = gig
        samples["sample-Night market, Chinatown"] = market
        samples["sample-XT-6 sale ends"] = shoes
        samples["sample-Salomon XT-6"] = shoes
        samples["sample-Crispy chilli noodles"] = noodles
        // Landscape, to show a screenshot that's the wrong shape for its card.
        samples["sample-Ramen Ikkyu"] = photo()
        // Photos added to things done, for the did-it log.
        samples[MemoryPhotos.identifier(for: "sample-ramen.jpg")] = ramenPhoto()
        samples[MemoryPhotos.identifier(for: "sample-gig.jpg")] = gigPhoto()
        AssetImageLoader.samples = samples
    }

    private static func render(_ view: some View, size: CGSize) -> CGImage? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 2
        return renderer.cgImage
    }

    private static func page(title: String, subtitle: String, lines: [String], button: String, hero: [Color]) -> CGImage? {
        render(
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("9:41").font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Capsule().frame(width: 26, height: 12)
                }
                .padding(.horizontal, 28)
                .padding(.top, 18)
                .padding(.bottom, 14)
                ZStack {
                    LinearGradient(colors: hero, startPoint: .top, endPoint: .bottom)
                    Circle()
                        .fill(.black.opacity(0.55))
                        .frame(width: 120, height: 120)
                        .offset(y: 70)
                }
                .frame(height: 380)
                .clipped()
                VStack(alignment: .leading, spacing: 12) {
                    Text(title).font(.system(size: 32, weight: .bold))
                    Text(subtitle).font(.system(size: 18)).opacity(0.7)
                    ForEach(lines, id: \.self) { line in
                        Text(line).font(.system(size: 17)).opacity(0.85)
                    }
                    Text(button)
                        .font(.system(size: 17, weight: .semibold))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color(red: 0.95, green: 0.45, blue: 0.22)))
                        .padding(.top, 6)
                }
                .padding(24)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .background(Color(white: 0.07)),
            size: CGSize(width: 390, height: 844)
        )
    }

    /// A bowl of ramen from above, soft focus: something shaped like a phone photo of a meal.
    private static func ramenPhoto() -> CGImage? {
        render(
            ZStack {
                LinearGradient(colors: [Color(red: 0.22, green: 0.13, blue: 0.08), Color(red: 0.08, green: 0.05, blue: 0.03)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .fill(Color(red: 0.12, green: 0.1, blue: 0.09))
                    .frame(width: 470, height: 470)
                    .shadow(color: .black.opacity(0.6), radius: 30, y: 20)
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 0.98, green: 0.84, blue: 0.6), Color(red: 0.86, green: 0.6, blue: 0.32)], center: .center, startRadius: 0, endRadius: 200))
                    .frame(width: 400, height: 400)
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 1, green: 0.95, blue: 0.85), Color(red: 0.98, green: 0.7, blue: 0.2)], center: .center, startRadius: 0, endRadius: 50))
                    .frame(width: 100, height: 100)
                    .offset(x: -70, y: -50)
                Capsule()
                    .fill(Color(red: 0.55, green: 0.3, blue: 0.2))
                    .frame(width: 150, height: 60)
                    .rotationEffect(.degrees(-20))
                    .offset(x: 80, y: 60)
                Capsule()
                    .fill(Color(red: 0.25, green: 0.45, blue: 0.2))
                    .frame(width: 90, height: 18)
                    .rotationEffect(.degrees(35))
                    .offset(x: 10, y: -110)
            }
            .blur(radius: 3),
            size: CGSize(width: 640, height: 480)
        )
    }

    /// A gig from the crowd: a dark room, coloured stage light and heads in front.
    private static func gigPhoto() -> CGImage? {
        render(
            ZStack(alignment: .bottom) {
                Color(red: 0.04, green: 0.03, blue: 0.05)
                RadialGradient(colors: [Color(red: 0.95, green: 0.3, blue: 0.45), .clear], center: UnitPoint(x: 0.3, y: 0.15), startRadius: 0, endRadius: 320)
                RadialGradient(colors: [Color(red: 1, green: 0.62, blue: 0.25), .clear], center: UnitPoint(x: 0.75, y: 0.2), startRadius: 0, endRadius: 280)
                RadialGradient(colors: [Color(white: 1, opacity: 0.9), .clear], center: UnitPoint(x: 0.52, y: 0.42), startRadius: 0, endRadius: 60)
                HStack(alignment: .bottom, spacing: -30) {
                    ForEach(0..<7, id: \.self) { index in
                        Ellipse()
                            .fill(Color(red: 0.02, green: 0.02, blue: 0.03))
                            .frame(width: 130, height: index % 2 == 0 ? 190 : 160)
                    }
                }
                .offset(y: 70)
            }
            .blur(radius: 2),
            size: CGSize(width: 640, height: 480)
        )
    }

    private static func photo() -> CGImage? {
        render(
            ZStack {
                LinearGradient(colors: [Color(red: 0.3, green: 0.18, blue: 0.1), Color(red: 0.12, green: 0.07, blue: 0.04)], startPoint: .top, endPoint: .bottom)
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 0.95, green: 0.75, blue: 0.45), Color(red: 0.6, green: 0.3, blue: 0.12)], center: .center, startRadius: 0, endRadius: 170))
                    .frame(width: 340, height: 340)
                Text("RAMEN IKKYU")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 24)
            },
            size: CGSize(width: 640, height: 480)
        )
    }
}
