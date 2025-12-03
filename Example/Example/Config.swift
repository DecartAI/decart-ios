//
//  Config.swift
//  Example
//
//  Created by Alon Bar-el on 19/11/2025.
//

import DecartSDK
import Foundation

struct PromptPreset: Identifiable, Sendable {
	let id = UUID()
	let label: String
	let prompt: String
}

enum DecartConfig: Sendable {
	nonisolated static let apiKey = ProcessInfo.processInfo.environment["DECART_API_KEY"] ?? ""

	static func presets(for model: RealtimeModel) -> [PromptPreset] {
		switch model {
		case .mirage, .mirage_v2:
			return miragePresets
		case .lucy_v2v_720p_rt:
			return lucyEditPresets
		}
	}

	private static let miragePresets: [PromptPreset] = [
		PromptPreset(
			label: "Pirates",
			prompt: "Transform the image into Pirates of the Caribbean swashbuckling fantasy style while maintaining the same composition. Use weathered nautical browns and blues, supernatural green ghost effects and tropical Caribbean colors with golden treasure accents. Add water-damaged wooden ship textures, weathered pirate clothing with character-specific details and supernatural decay with ghostly material properties. Apply dramatic lantern and moonlight with supernatural transformation effects, reimagining the elements with historical pirate meets cursed treasure qualities while keeping the same overall arrangement."
		),
		PromptPreset(
			label: "Bee Hive",
			prompt: "Transform the image into a bee hive style with whimsical synthetic-2D animation while maintaining the original composition. Apply a color palette of warm yellows and rich browns reflecting organic honey and wax materials. Create soft, rounded shapes and playful designs with vibrant, saturated colors evoking a lively, bustling atmosphere. Use bright, cheerful lighting simulating sunlight filtering through the hive for a sense of warmth and activity while keeping all elements in their current positions."
		),
		PromptPreset(
			label: "Van Gogh",
			prompt: "Transform the image into Van Gogh painting style while maintaining the same composition. Use vibrant, emotionally expressive yellows, blues and greens with complementary color contrasts and pure unmixed pigments. Create swirling, directional brushwork with thick impasto application that suggests physical dimension. Make lighting appear to radiate from within objects with halos and auras around light sources, reimagining the elements with passionate Post-Impressionist qualities while keeping the same overall arrangement."
		),
		PromptPreset(
			label: "Yellow Cartoon",
			prompt: "Transform the image into The Simpsons animation style while maintaining the same composition. Use the iconic yellow skin tone with bright primary colors and suburban American color schemes in bold saturation. Apply flat cartoon rendering with bold outlines and simple shading techniques. Create bright television lighting with minimal shadows, keeping all elements in their original positions."
		),
		PromptPreset(
			label: "Cyborgs",
			prompt: "Transform the image into Terminator tech-noir style while maintaining the same composition. Use cold blue lighting for future scenes, warm human tones contrasted with metallic silver machine elements and electrical energy effects with blue-white intensity. Add hyperdetailed robotic components with exposed mechanical workings, battle-damaged cyborg elements revealing metal under flesh and post-apocalyptic environmental features. Apply harsh mechanical lighting emphasizing robotic elements with glowing red accents, reimagining the elements with technological horror qualities while keeping the same overall arrangement."
		),
		PromptPreset(
			label: "Manga",
			prompt: "Transform the image into black and white manga illustration style while maintaining the same composition. Use pure blacks, clean whites and varied gray tones achieved through screen tones and hatching techniques. Apply crisp ink lines with varying weights, detailed texture work through stippling and cross-hatching. Create high contrast lighting with dramatic shadows and bright highlights, keeping all elements in their original positions."
		),
		PromptPreset(
			label: "Animation",
			prompt: "Transform the image into Pixar 3D animation style while maintaining the same composition. Use carefully crafted color theory with warm family-friendly tones and cinematic color grading. Apply realistic 3D textures, advanced material shaders and subtle subsurface scattering effects. Create cinematic 3D lighting with realistic light behavior and atmospheric effects, keeping all elements in their original positions."
		),
		PromptPreset(
			label: "Golden Hour",
			prompt: "Transform the image into golden hour style while maintaining the original composition. Apply warm tones with soft lighting that creates long shadows. Enhance the image with warm golden and orange hues throughout. Create a serene, tranquil atmosphere typical of sunset lighting while keeping all elements in their current positions."
		),
		PromptPreset(
			label: "Ghibli Inspired",
			prompt: "Transform the image into Studio Ghibli style with hand-painted watercolor-like visuals while maintaining the same composition. Apply fine lines with soft shading and warm pastel colors in greens, blues and oranges with low saturation. Add delicate watercolor textures, gentle brushstrokes and subtle paper grain. Use soft diffused natural lighting reminiscent of light filtering through shoji screens, keeping all elements in their original positions."
		),
		PromptPreset(
			label: "War Zone",
			prompt: "Transform the image into Mad Max post-apocalyptic style while maintaining the same composition. Use harsh desert oranges and yellows, desaturated dusty neutrals and night scenes illuminated by fire with high contrast. Add rust-covered vehicular modifications with practical mechanical detail, makeshift clothing and armor from salvaged materials and barren wasteland environmental elements. Apply harsh desert lighting with silhouettes against vast wasteland horizons, reimagining the elements with brutal survival qualities while keeping the same overall arrangement."
		),
		PromptPreset(
			label: "Zombies",
			prompt: "Transform the image into a synthetic-3D horror video game style featuring stylized zombies while maintaining the original composition. Apply exaggerated features with high detail and texture that highlight decayed, undead elements. Use a color palette of muted earth tones with pops of eerie greens and purples. Add dramatic lighting with high contrast and deep shadows for a suspenseful, mysterious atmosphere while keeping all elements in their current positions."
		),
		PromptPreset(
			label: "K-pop",
			prompt: "Apply K-pop style with vibrant hyper-polished aesthetic, perfectly styled performers, coordinated fashion-forward outfits, candy-colored pastels alongside bold neons, immaculate styling with glossy skin, and flawless soft-focus lighting"
		),
		PromptPreset(
			label: "Mythic",
			prompt: "Transform the image into God of War game style while maintaining the same composition. Use cold Nordic blues and whites, rich wooden browns and divine gold accents with blood-red highlights. Add weathered leather and metal with intricate Norse knotwork, godly artifacts with magical properties and massive environmental scale elements. Apply dramatic cinematic lighting emphasizing character moments and epic scale, reimagining the elements with a Norse mythological action aesthetic while keeping the same overall arrangement."
		),
		PromptPreset(
			label: "Wild West",
			prompt: "Transform the image into Red Dead Redemption Western game style while maintaining the same composition. Use warm dusty earth tones with golden hour lighting, weathered browns and tans for frontier elements and natural greens for wilderness areas. Add weathered leather and denim with appropriate aging, wooden structures with detailed grain and wear patterns and natural environments with ecological detail. Apply dramatic lighting with stunning sunsets and atmospheric weather effects, reimagining the elements with an American frontier aesthetic while keeping the same overall arrangement."
		),
		PromptPreset(
			label: "Sci-fi Anime",
			prompt: "Transform the image into Rick and Morty animation style while maintaining the same composition. Combine sci-fi colors with earth tones featuring portal greens, space blues and alien color schemes in vivid saturation. Add sci-fi technology textures, interdimensional effect work and adult animation detail levels. Apply dynamic sci-fi lighting with portal effects and alien illumination, keeping all elements in their original positions."
		),
		PromptPreset(
			label: "Classic Anime",
			prompt: "Transform the image into Naruto anime style while maintaining the same composition. Use earth tones with ninja blues, forest greens and warm orange accents in moderate saturation. Combine traditional anime techniques with subtle texture work representing fabric and natural materials. Apply natural outdoor lighting mixed with mystical chakra effects, keeping all elements in their original positions."
		),
		PromptPreset(
			label: "Blocky",
			prompt: "Transform the image into a Minecraft-inspired blocky 3D style with pixelated visual design while maintaining the original composition. Apply distinct cubic shapes throughout. Use a clean, consistent color palette dominated by stone grays, browns, and whites. Create smooth, pixel-consistent textures with low-resolution detail. Add bright, even lighting for an open, constructive atmosphere while keeping all elements in their current positions."
		),
		PromptPreset(
			label: "Football",
			prompt: "Transform the image into American football style with powerful, armored athletic elements. Apply team-specific uniform colors with bold primary hues against green field background. Add football leather grain textures, helmet sheen details, grass-stained jersey effects, and player exertion elements. Use dramatic stadium lighting creating strong contrasts with harsh shadows. Maintain the subject's position while incorporating football action characteristics. Create an intense, gritty atmosphere filled with tension and explosive athleticism."
		),
		PromptPreset(
			label: "Picasso",
			prompt: "Transform the image into Picasso Cubist style while maintaining the same composition. Use flat, bold hues of blues, reds and earth tones applied in geometric patches with strong black outlines. Create flattened surfaces with angular planes that break traditional perspective rules, revealing multiple viewpoints simultaneously. Apply non-naturalistic, symbolic lighting rather than representational, reimagining the elements with fragmented, multi-perspective Cubist qualities while keeping the same overall arrangement."
		),
		PromptPreset(
			label: "Super Hero",
			prompt: "Transform the image into Marvel Cinematic Universe superhero style while maintaining the same composition. Use character-specific signature colors, location-specific color grading and vibrant energy effect colors with high saturation. Add practical superhero costumes with functional detailing, urban environments with appropriate destruction physics and magical/technological effects with distinctive visual signatures. Apply dynamic action lighting emphasizing heroic moments with dramatic highlights, reimagining the elements with colorful optimistic superhero qualities while keeping the same overall arrangement."
		),
		PromptPreset(
			label: "Neon Nostalgia",
			prompt: "Transform the image into a cyberpunk anime style with neon colors and vibrant contrasts while maintaining the original composition. Apply a color palette of electric blues, pinks, and purples against a dark, rainy backdrop. Make surfaces appear reflective and wet with shimmering reflections. Create an intense, moody atmosphere with dynamic lighting to evoke an urban, futuristic aesthetic while keeping all elements in their current positions."
		),
	]

	private static let lucyEditPresets: [PromptPreset] = [
		PromptPreset(
			label: "Anime Character",
			prompt: "Transform the person into a 2D anime character with smooth cel-shaded lines, soft pastel highlights, large expressive eyes, clean contours, even lighting, simplified textures, and a bright studio-style background for a polished anime look."
		),
		PromptPreset(
			label: "Knight Armor",
			prompt: "Change the uniform to a full medieval knight's armor with polished steel plates, engraved trim, articulated joints, matte underpadding, subtle battle scuffs, and cool directional lighting reflecting off the metal surfaces."
		),
		PromptPreset(
			label: "Spooky Skeleton",
			prompt: "Replace the person with a Halloween-style skeleton featuring clean ivory bones, deep sockets, subtle surface cracks, articulated joints, and soft overhead lighting creating dramatic shadows across the ribcage."
		),
		PromptPreset(
			label: "Leather Jacket",
			prompt: "Change the jacket to a black leather biker jacket with weathered grain texture, silver zippers, reinforced seams, slightly creased sleeves, and cool diffuse lighting suggesting an overcast outdoor feel."
		),
		PromptPreset(
			label: "Origami",
			prompt: "Replace the person with a full-body origami figure built from crisp white folded paper, sharp geometric edges, layered segments, subtle crease shadows, and clean studio lighting enhancing the sculptural form."
		),
		PromptPreset(
			label: "Business Casual",
			prompt: "Change the outfit to a light blue buttoned shirt paired with a tailored charcoal jacket, smooth cotton texture, clean stitching, structured shoulders, and balanced indoor lighting for a polished business-casual look."
		),
		PromptPreset(
			label: "Summer Dress",
			prompt: "Change the outfit to a light floral summer dress with thin spaghetti straps, soft flowing fabric, pastel bloom patterns, gentle folds, and warm natural lighting suggesting an outdoor summer setting."
		),
		PromptPreset(
			label: "Lizard Person",
			prompt: "Transform the person into a humanoid lizard figure with green scaled skin, subtle iridescence, angular cheek structure, elongated pupils, fine texture detail, and directional lighting emphasizing the reptilian contours."
		),
		PromptPreset(
			label: "Pink Shirt",
			prompt: "Change the top color to bright pink with smooth fabric texture, preserved seams, soft shading along natural folds, and consistent lighting for an even saturated look."
		),
		PromptPreset(
			label: "Plastic Doll",
			prompt: "Transform the person into a realistic fashion-doll version with smooth porcelain-like skin, glossy lips, defined lashes, polished facial symmetry, bright studio lighting, perfectly styled hair, and a fitted pink outfit with clean plastic-like highlights."
		),
		PromptPreset(
			label: "Sunglasses",
			prompt: "Add a pair of dark tinted sunglasses resting naturally on the person's face, smooth acetate frames, subtle reflections on the lenses, accurate nose placement, and soft shadows across the cheeks."
		),
		PromptPreset(
			label: "Super Hero",
			prompt: "Transform the person into a superhero wearing a fitted suit with bold color panels, textured fabric, sculpted contours, a flowing cape, subtle rim lighting, and dramatic cinematic shading."
		),
		PromptPreset(
			label: "Polar Bear",
			prompt: "Replace the person with a small polar bear featuring dense white fur, rounded ears, soft muzzle, gentle expression, and cool ambient lighting highlighting the fluffy texture."
		),
		PromptPreset(
			label: "Alien",
			prompt: "Transform the person into a realistic alien form with pale luminescent skin, smooth reflective surface tones, large glassy eyes, subtle facial ridges, elongated contours, and cinematic lighting emphasizing the otherworldly texture."
		),
		PromptPreset(
			label: "Parrot on Shoulder",
			prompt: "Add a bright green parrot perched on the person's shoulder with layered feathers, a curved beak, slight head tilt, natural talon grip, and a soft contact shadow on the clothing."
		),
		PromptPreset(
			label: "Icy Hair",
			prompt: "Change the hair color to icy platinum blonde with a cool metallic sheen, fine reflective highlights, smooth strands, and bright soft lighting emphasizing the frosted tone."
		),
		PromptPreset(
			label: "Tux",
			prompt: "Change the shirt to a formal tuxedo ensemble featuring a crisp white dress shirt, black satin lapels, structured fit, smooth fabric textures, and balanced indoor lighting for an elegant look."
		),
		PromptPreset(
			label: "Kitty",
			prompt: "Add a small cat sitting gently on the person's head, soft striped fur, relaxed posture, curved tail, clear whiskers, natural grip on the hair, and a soft contact shadow for realism."
		),
		PromptPreset(
			label: "Super Spider",
			prompt: "Transform the person into a Spider-Man–style hero wearing a red and blue textured suit, raised web patterns, fitted contours, reflective eye lenses, and dramatic city-style lighting."
		),
		PromptPreset(
			label: "Car Racer",
			prompt: "Transform the person into a professional car racer wearing a padded racing suit with bold sponsor patches, high-contrast stitching, protective collar, and bright track-side lighting."
		),
		PromptPreset(
			label: "Happy Birthday",
			prompt: "Add a mix of colorful helium balloons floating around the person, glossy surfaces, thin strings, soft reflections, varied sizes, and warm ambient party lighting."
		),
	]
}
