# MyAttendance branding

The original uploaded calendar artwork, AppIcon variants and InvoiceLogo asset are preserved in `MyAttendance-OriginalUploadedAssets.zip`.

The new transparent logo is saved at:

`MyAttendance/Assets.xcassets/BrandMark.imageset/BrandMark.png`

It is used by the launch screen, the brief in-app splash, and salary statement PDFs. The generated PNG has an alpha channel and is 1254 × 1254 pixels. The same generated mark now also controls the iPhone home-screen icon (light and dark backgrounds), and replaces the image behind the existing `InvoiceLogo` asset name. App icon files are scaled and composited into opaque 1024 × 1024 PNGs as iOS requires; the logo artwork itself is unchanged. iOS can derive its tinted icon from the same mark.

## Generation

The built-in image-generation tool was used, with the supplied `InvoiceLogo.png` as the reference. No external API credentials were used.

Final prompt:

> Create one production-ready logo mark for the MyAttendance iOS app, using the supplied blue calendar with checkmark artwork as the reference. Preserve its recognizable calendar-and-check identity but refine it into a clean premium minimal brand mark: blue calendar outline or solid rounded calendar body, a single clear white or teal checkmark, restrained cyan/blue shading with very subtle dimensional polish, excellent small-size legibility. Remove the duplicate checkmark badge, busy cell details, neon glow, metallic reflections and black background. Center the mark with generous transparent padding, balanced square composition. No letters, no words, no mockup, no surrounding app-icon square, no shadows outside the mark. Genuinely transparent background, crisp alpha edges. Intended for a white professional salary invoice header and a native iPhone launch splash. Supply one square high-resolution logo.

## Splash screen

`MyAttendance/App/LaunchScreen.storyboard` displays the brand as soon as iOS launches the app. `LaunchSplashView.swift` instantiates that exact same storyboard rather than rebuilding its layout in SwiftUI. The Dashboard mounts underneath, settles for 0.35 seconds, and only the splash opacity fades over 0.24 seconds. Removing the splash does not animate the tab or navigation layout. It has no artificial progress indicator and does not reappear each time you change tabs or return from the background. Light and dark background colors are included. Reduce Motion disables the animated fade.

## Accent colors

Settings → Appearance → Accent color now opens a list of actual colored swatches. Every swatch uses its own color rather than inheriting the selected app tint. The selected option has a checkmark, saves immediately through the existing settings, and changes the app tint.
