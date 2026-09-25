# Earnote – macOS Design & UI Architecture Guidelines

> Verbindliches Briefing für alle Arbeiten an der Oberfläche (Stand 16.09.2026).
> Gilt für jeden, der an Earnote baut – Menschen wie KI-Agenten.

## ROLE
You are the lead product architect and macOS UI architect for this application.
Your job is NOT to generate visually impressive demo screens.
Your job is to build a mature, native macOS application that feels like it was designed specifically for macOS by an experienced Apple-platform product team.

The application must never feel like:
- a web dashboard wrapped in a Mac window
- an iPad app running on macOS
- a generic AI SaaS interface
- a Dribbble concept
- a collection of SwiftUI cards
- a custom design system fighting against macOS

Native macOS behavior, hierarchy, density and interaction patterns take precedence over decorative styling.

## 1. MACOS FIRST
Before designing any feature, ask:
1. What kind of macOS surface is this?
2. Is it a main window, document window, utility window, inspector, settings window, sheet, popover, panel or menu bar extra?
3. What is the primary selection model?
4. Which actions belong in the toolbar?
5. Which actions belong in menus / commands?
6. Which actions deserve keyboard shortcuts?
7. Does the feature need multiple windows?
8. Is this information better represented in a sidebar, detail pane or inspector?

Do not start by thinking in terms of web pages or mobile screens. Think in terms of macOS scenes, windows and desktop workflows.

## 2. USE NATIVE STRUCTURE BEFORE CUSTOM UI
Prefer native SwiftUI/macOS structures whenever they solve the problem:
NavigationSplitView · List with sidebar style · Inspector · Toolbar · Commands · Menu · ContextMenu · Settings scene · WindowGroup · Window · DocumentGroup · MenuBarExtra · searchable · Table · OutlineGroup · Form · native sheets · native popovers

Do not recreate these components manually unless there is a concrete product requirement that the native component cannot satisfy.
- Never build a custom sidebar merely to make the app look unique.
- Never build a custom title bar merely for aesthetics.
- Never build a fake toolbar inside the content area.
- Never create web-style navigation if standard macOS window/sidebar navigation fits the task.

## 3. DO NOT DESIGN A WEB APP INSIDE A WINDOW
Avoid typical web/SaaS patterns unless the product genuinely requires them. Do NOT default to:
dashboard card grids · hero sections · giant page titles · nested cards · floating navigation pills · excessive rounded rectangles · custom tab bars · bottom navigation · mobile-style navigation stacks · large touch targets everywhere · huge spacing between controls · decorative statistics cards · oversized call-to-action buttons · custom scroll containers without reason

A macOS application should generally feel denser and more structural than a modern marketing website.

## 4. CARDS ARE THE EXCEPTION
Do not use rounded rectangles as the default grouping mechanism. A visual card is justified only when it represents a genuinely independent object or meaningful bounded surface.

Prefer: alignment · spacing · section headers · separators · lists · tables · inspectors · disclosure groups · native grouped controls — before introducing a card.

Never create Card → inside another Card → containing multiple mini Cards.

Avoid repeated combinations such as
`.background(...)` + `.clipShape(RoundedRectangle(...))` + `.overlay(RoundedRectangle(...).stroke(...))` + `.shadow(...)`
unless the component truly requires visual elevation.

## 5. PRESERVE MACOS INFORMATION DENSITY
Design for mouse, trackpad and keyboard users sitting at a desktop. Do not use iOS-sized spacing everywhere. Prefer compact and medium control sizes unless an action genuinely deserves prominence. Related controls should be visually close. Do not create empty space merely to make the application appear premium.

Hierarchy should primarily come from: 1. structure 2. typography 3. alignment 4. spacing 5. semantic foreground/background differences. Decoration comes last.

## 6. SIDEBARS MUST LOOK LIKE MACOS SIDEBARS
Use native source-list behavior and system selection. Sidebar rows should normally contain: zero or one leading icon · one primary label · optionally one short secondary label.

Avoid: rounded cards around every sidebar item · multiple inline status badges · several icons per row · three-line metadata layouts · custom selection backgrounds · buttons appearing permanently inside every row · excessive row height.

Move detailed metadata and actions into the detail view or inspector. The sidebar is for navigation and selection, not for presenting the whole data model.

## 7. USE THE DETAIL + INSPECTOR MODEL
For editing-oriented applications, strongly consider: Sidebar → Content/Detail → Inspector.
Use the detail area for the primary task. Use an inspector for properties, metadata, configuration and secondary controls associated with the current selection. Do not put every possible option directly into the primary interface. Do not create modal dialogs for properties that naturally belong in an inspector. The inspector should remain contextually tied to the current selection.

## 8. TOOLBARS ARE FUNCTIONAL, NOT DECORATIVE
Toolbar items must represent important window-level actions. Do not fill the toolbar with decorative icons. Group related actions. Avoid placing every possible feature in the toolbar. Primary actions should be discoverable through appropriate combinations of toolbar, menu commands, context menus and keyboard shortcuts. Do not make the content area imitate a toolbar when the actual window toolbar can perform the job.

## 9. MENUS AND KEYBOARD SHORTCUTS ARE PART OF THE PRODUCT
Important actions should not only exist as clickable UI. For every important action consider: application menu command · keyboard shortcut · contextual menu · toolbar item · command routing through focused content.
Standard actions should use standard shortcuts whenever applicable. Do not hide important functionality behind pointer-only gestures. Design keyboard navigation and focus intentionally.

## 10. TYPOGRAPHY SHOULD FEEL SYSTEMATIC
Prefer system typography unless there is a strong brand requirement. Avoid giant headings. Do not treat every view like a landing page. Use a restrained hierarchy: window / section title · primary content · secondary content · metadata · labels.
Use `.secondary` intentionally. Do not make half of the application low-contrast gray. Readable content must remain readable.

## 11. COLORS MUST BE SEMANTIC AND ADAPTIVE
Prefer semantic system colors and styles: primary · secondary · tertiary where appropriate · semantic system backgrounds · system materials · tint/accent for meaningful interaction.
Avoid hardcoded white backgrounds, nearly-black custom backgrounds, arbitrary gray values everywhere, generic purple/blue AI gradients.
The application must work correctly in Light Mode and Dark Mode without maintaining two unrelated visual systems.
Color should primarily communicate: selection · state · hierarchy · warning · success · destructive action · interactive emphasis. Do not use color merely because an area looks visually empty.

## 12. USE SYSTEM MATERIALS
Do not manually recreate macOS translucency. Prefer native materials and current macOS system effects. Do not place opaque custom backgrounds behind system sidebars, toolbars or sheets without a product reason. Do not stack blur + opacity + gradient + border + shadow to imitate system glass. Let macOS provide macOS chrome. Custom glass is reserved for application-specific surfaces that cannot be expressed using standard components.

## 13. DO NOT OVERUSE LIQUID GLASS
Liquid Glass is not a decoration layer. Use system-provided glass automatically supplied by standard macOS structure before adding custom glass surfaces. Do not turn every button, card or label into glass. Do not tint glass merely for visual variety. Glass should follow platform semantics and hierarchy. If standard controls already render appropriately, leave them alone.

## 14. BUTTONS SHOULD LOOK LIKE MACOS CONTROLS
Do not create giant rounded CTA buttons unless the workflow genuinely has a singular high-emphasis action. Establish a clear distinction between primary, regular, destructive and inline actions. Prefer standard Button, Menu, Toggle, Picker, TextField and other native controls. Do not create custom controls solely because standard controls look "too boring." Boring but familiar is often correct desktop UX.

## 15. ICONS MUST HAVE MEANING
Prefer SF Symbols where appropriate. Icons should improve recognition. Do not put an icon next to every label. Do not use sparkles, magic wands, stars or colorful symbols merely to make features appear intelligent or modern. Avoid mixing unrelated icon styles. Toolbar icons should remain especially restrained.

## 16. WINDOWS ARE FIRST-CLASS OBJECTS
Do not treat the whole app as one permanent ContentView. Explicitly model meaningful scenes (main window, settings, inspector, utility window, preview window, document window, menu bar extra).
Decide whether state belongs to the entire application, one scene/window, one feature or one view before implementing the view. Window-specific ephemeral state should not accidentally become global application state.

## 17. SETTINGS BELONG IN SETTINGS
Application preferences use a dedicated Settings scene. Do not make Settings another destination in the main sidebar unless the product has a very specific reason. Preferences should feel like macOS preferences, not like a SaaS account settings webpage. Use native forms, sections and controls.

## 18. STATE ARCHITECTURE
Use the narrowest appropriate state ownership. Before creating a view model, determine whether the state is actually: local view state · binding state · scene/window state · persistent preference state · shared domain state · application service state.
Do not create an ObservableObject/ViewModel for every view by reflex. Keep selection state explicit and stable. For Observation-based architecture, keep observable models owned at deliberate boundaries and pass them explicitly where practical. Avoid hidden global state.

## 19. KEEP ROOT LAYOUT STABLE
Do not replace the entire root view whenever selection changes. Prefer a stable structural shell: NavigationSplitView → Sidebar → Detail → optional Inspector, and change the content inside the appropriate region. Selection changes should not make the application jump between unrelated layouts.

## 20. ARCHITECTURE BEFORE VIEW CODE
Before implementing a non-trivial feature, provide a short architecture proposal:
- **Scene** – which scene/window owns the feature?
- **Primary task** – what is the user trying to accomplish?
- **Layout** – sidebar/detail/inspector, editor, table, utility window, etc.
- **Selection** – what is selected and who owns that state?
- **Commands** – which actions belong in menus and keyboard shortcuts?
- **Toolbar** – which actions deserve toolbar placement?
- **State ownership** – which state is local, scene-scoped, persistent or shared?
- **Native components** – which standard SwiftUI/macOS components solve the problem?
- **Custom components** – what genuinely needs custom rendering?

Only after answering these questions should implementation begin.

## 21. FILE STRUCTURE
Do not build non-trivial applications in one Swift file. Prefer:
```
App/        AppNameApp.swift
Views/      ContentView.swift, SidebarView.swift, DetailView.swift, InspectorView.swift
Features/   FeatureName/FeatureView.swift, FeatureComponents.swift
Models/  Stores/  Services/  Support/
```
The entry point stays small. ContentView describes high-level composition. Business logic, persistence, networking and process management must not live inside view bodies.

## 22. KEEP SWIFTUI VIEWS SMALL
Avoid giant `body` implementations. Extract semantically meaningful components, not arbitrary chunks of syntax. Prefer dedicated View types over dozens of large computed `some View` properties. Subviews receive explicit values, bindings and actions. Do not casually pass a gigantic global app model into every descendant. A view's responsibility should be obvious from its name and inputs.

## 23. KEEP APPKIT ESCAPE HATCHES NARROW
SwiftUI first. Use AppKit only when macOS functionality genuinely requires it (NSWindow control, responder chain, advanced text system, specialized panels, AppKit-only APIs). Isolate it behind a small adapter or representable. Do not let NSView / NSWindow references spread through the SwiftUI hierarchy. Do not use AppKit to reproduce something SwiftUI already handles correctly.

## 24. DESIGN FOR REAL DATA
Every feature must account for: no selection · empty datasets · one item · hundreds or thousands of items · long names · narrow windows · wide windows · loading · errors · offline/unavailable services · disabled states · permission failures · destructive confirmation · keyboard focus · selection changes. Do not optimize for perfect screenshot data.

## 25. WINDOW RESIZING IS PART OF THE DESIGN
Evaluate every major screen at minimum, normal and wide window size. Do not assume a fixed canvas. Do not center everything because it looks good at one width. Specify reasonable minimum sizes. Use layout priorities and flexible structures intentionally.

## 26. ACCESSIBILITY AND PLATFORM BEHAVIOR
Respect keyboard navigation, focus states, VoiceOver labels, reduced motion, increased contrast, Light/Dark Mode, system accent color, localization, Dynamic Type where applicable, menu discoverability. Do not sacrifice native behavior for visual customization.

## 27. ANIMATION
Animation communicates insertion/removal, state transition, spatial relationship, expansion/collapse. Do not animate merely because SwiftUI makes it easy. Avoid spring animations on ordinary desktop interactions. Mac apps should feel responsive rather than theatrical.

## 28. DESIGN REVIEW — ANTI-VIBECODING PASS
After implementing every major screen, review for AI-generated UI smells:
- Did I create unnecessary cards? Too many rounded rectangles?
- Is spacing unnecessarily large?
- Did I recreate a native macOS component?
- Does this resemble a website?
- Custom backgrounds where the system should provide them? Unnecessary glass? Unnecessary icons?
- Is the toolbar overcrowded?
- Are important actions missing keyboard/menu equivalents?
- Does the sidebar look like a source list or like web cards?
- Is information density appropriate for desktop use?
- Could typography/alignment replace decorative containers?
- Is there one obvious hierarchy?
- Correct in Light and Dark Mode? Coherent when the window is narrow?
- Would this interaction feel normal in Finder, Mail, Xcode, Notes or another mature Mac app?

If any element exists primarily to make the screenshot look more impressive, challenge whether it should exist.

## 29. DEFAULT DESIGN PHILOSOPHY
When uncertain, choose:
native over custom · structural over decorative · dense over artificially spacious · semantic over ornamental · standard controls over bespoke controls · alignment over containers · typography over cards · system materials over fake glass · desktop patterns over mobile patterns · selection over push navigation · menus and shortcuts over hidden gestures · predictability over novelty · clarity over visual spectacle

The desired result: **"This application belongs on macOS."** — not "This website happens to be running inside a Mac window."

---

## 30. IPHONE (ab 24.09.2026)
The same philosophy applies to the iPhone app: **"This application belongs on iOS."** Native structure first, no custom design system. Plan and features: [IPHONE.md](IPHONE.md).

**Structure**
- Root is a `TabView` (Aufnahmen · Lernen · Suche with `role: .search`). Each tab owns one `NavigationStack`; the root never swaps layouts.
- The running recording lives in `tabViewBottomAccessory` (like Now Playing in Music), not in a floating custom button.
- Lists are `List` with system styles, grouped by day with `Section`. Swipe actions and context menus for row actions, never custom row buttons.
- Details push onto the stack. Secondary tasks (settings, record screen, choosing an area) are sheets with detents. Settings are an in-app sheet with `Form`, opened from the toolbar.
- Empty, loading and error states use `ContentUnavailableView` and `ProgressView`.

**Visuals**
- System typography with Dynamic Type everywhere; test at the largest accessibility size.
- Semantic colors only; the brand red is the tint, nothing else. Light and Dark Mode.
- Liquid Glass: iOS 26 applies it to tab bar, toolbars and sheets. Beyond that, glass is allowed for **a few floating controls that sit above content** – the record/stop controls, the player bar, the flashcard – via `.glassEffect`, `GlassEffectContainer` and `.buttonStyle(.glass/.glassProminent)`. Never on list rows, never glass on glass, never as a decorative background.
- One signature moment per screen is allowed (24.09.2026, owner's request "native, but a little special"): a softly moving brand-tinted `MeshGradient` on the welcome page and behind a running recording, animated SF Symbols (`symbolEffect`) and numeric transitions. Everything else stays plain system UI. Respect Reduce Motion: gradients stand still, symbols do not animate.
- SF Symbols with meaning; no decorative icons.

**Behavior**
- One-handed use: primary actions reachable at the bottom (accessory, toolbar bottom bar).
- Recording must be startable without looking: Live Activity buttons, Control Center control, App Intents (Siri, Shortcuts, Action button).
- Haptics only to confirm start, stop and pause of a recording.
- Respect Reduce Motion, VoiceOver (every control labeled, the record state spoken), Bold Text, Increased Contrast.

**Review:** Section 28 applies unchanged, plus: Would this feel normal in Voice Memos, Notes, Music or Mail on iPhone?

## 31. IPAD (Entwurf ab 24.09.2026)
The iPad is not a big iPhone and not a small Mac: **"This application belongs on iPadOS."** Plan: [IPAD.md](IPAD.md). Section 30 applies unless stated otherwise here.

**Structure**
- One app for iPhone and iPad. The root stays one `TabView`, now with `.tabViewStyle(.sidebarAdaptable)`: tabs on iPhone and in compact width, a sidebar on iPad. Sidebar entries mirror the Mac sidebar (All, Open Tasks, Uncategorized, Problems, areas). Never a second, iPad-only root.
- In regular width the recordings tab is a `NavigationSplitView` (list | note). Compact width (Slide Over, narrow Stage Manager windows) falls back to the stack automatically – never branch on device type, only on size class.
- The transcript sits next to the note when there is room (toggle „Transkript daneben“, like ⌘3 on the Mac) – as a second column inside the detail, **not** `inspector`: inside a `NavigationSplitView` detail the inspector swallowed the note’s navigation bar (iPadOS 26). In compact width it stays the segmented picker from section 30.
- Every window size and orientation works. Test at full screen, half, a third, and a small Stage Manager window.

**Input**
- Menu bar and keyboard (iPadOS 26): `commands` with the same shortcuts as the Mac (⌘N record, Space pause/resume, ⌘F search, ⌘, settings, ⌘⌫ delete). Every command in the menu bar, not only as a shortcut.
- Pointer: hover effects come from the system controls; no custom hover states.
- Drag and drop: audio files into the window import; a note drags out as Markdown text.

**Windows**
- `WindowGroup(for: UUID.self)` opens a note in its own window (e.g. next to lecture slides). A window restores its content via `@SceneStorage`.
- The running recording is global (`PhoneRecorder`); every window shows it in its bottom accessory.

**Visuals**
- Same rules as section 30: system typography, semantic colors, Liquid Glass only where the system puts it plus the few floating controls. Content columns get a readable width (`.frame(maxWidth:)` around 700 pt for the note text) instead of stretching across the screen.

**Review:** Section 28 applies unchanged, plus: Would this feel normal in Notes, Files, Mail or Voice Memos on iPad – with a keyboard attached and without one?
