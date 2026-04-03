# Product Needs Ecosystem Survey — 2026-03-29

Last updated: March 29, 2026
Status: Active research notes

## Topic

This document records what is currently available in the Flutter and standards ecosystem to satisfy the needs defined in [product-definition.md](../product-definition.md).

The goal is not to lock implementation immediately. The goal is to identify where the ecosystem already supports the product well, where the current direction is validated, and where the project will still need custom product work.

## Findings

### 1. Document intake is well supported, but no single package covers every flow cleanly

For native file picking, the ecosystem is strong.

- `file_picker` is current, cross-platform, uses OS-native pickers, supports multiple files, extension filtering, directories, save dialogs, and cloud-backed sources. It also exposes `XFile` results.
- `file_selector` is the official Flutter-publisher option. It covers opening files, saving files, and selecting directories across Android, iOS, Linux, macOS, web, and Windows. Its docs explicitly call out the required macOS file entitlements.
- `desktop_drop` is current and works across macOS, Windows, Linux, web, and preview Android for drag-and-drop.
- `file_open` is a narrow macOS plugin focused specifically on receiving file-open events from the operating system.

Mobile share-in is available, but the ecosystem is weaker and less established.

- `share_intent_package` offers Android and iOS share receive/send flows with automatic setup scripts, hot and cold start handling, multiple files, and document/file MIME support.
- `share_intent_package` does not list macOS support, so it is not a full cross-platform answer for the product by itself.
- `share_intent_package` is also from an unverified uploader with relatively low ecosystem weight compared with packages like `file_picker`, so it should be treated as useful but not especially reassuring ecosystem evidence on its own.

### 2. Rich document display is available, but different formats want different strategies

For HTML-like rich rendering, the ecosystem is strong.

- `flutter_html` is current, cross-platform, and designed for rendering HTML and CSS into Flutter widgets rather than a WebView.
- `flutter_html` supports `Html.fromDom()`, which matters because it lets us sanitize and transform imported markup before rendering.
- `flutter_html` has extension packages for audio, video, iframe, SVG, and tables. That lines up well with the product requirement that the reading surface not be locked into plain text.

For PDF, the ecosystem is strong.

- `pdfrx` is current, multi-platform, and supports Android, iOS, Linux, macOS, web, and Windows.
- `pdfrx` provides viewer widgets, text selection, document outline/bookmarks, and text search.
- `pdfrx` also supports a Darwin-specific CoreGraphics path to reduce app size on Apple platforms, although that option is documented as experimental.

For EPUB, the ecosystem is usable but more fragmented.

- `epubx` is a cross-platform parser that exposes chapter structure, HTML content, images, CSS, fonts, and navigation data. It is a strong parser candidate for a normalized import pipeline.
- `epub_view` is a pure Flutter EPUB viewer with table of contents support and EPUB CFI location persistence. It is more useful as a reader reference or fallback than as the core product architecture.
- `epub_decoder` explicitly advertises EPUB parsing with Media Overlay support, which may matter later if the product grows into synchronized text/audio EPUB handling.
- The EPUB packages visible today are capable, but they appear older and less central to the Flutter ecosystem than the PDF and HTML packages above, which increases the value of keeping EPUB in our own normalized import layer.

For DOCX and RTF, the ecosystem is materially weaker.

- `docx_file_viewer` is ambitious and claims high-fidelity DOCX rendering with search, zoom, selection, tables, images, footnotes, and theming across Flutter platforms.
- The DOCX viewer ecosystem is young compared with PDF and HTML, and there is not yet a clear mature default with the same level of adoption and ecosystem weight as `pdfrx` or `flutter_html`.
- RTF support appears especially thin. The visible package ecosystem is much stronger for creating RTF than for rendering or parsing it robustly.

### 3. Local-first Kokoro is viable in Flutter, but the app still needs its own voice-management layer

The local-first TTS direction is supported by the current ecosystem.

- `kokoro_tts_flutter` is a Flutter package built around Kokoro and ONNX Runtime. It supports Android, iOS, Linux, macOS, and Windows.
- `kokoro_tts_flutter` expects the app to provide model assets and voice assets.
- `kokoro_tts_flutter` uses `malsami` for phonemization.
- `malsami` is a Dart G2P engine for Flutter, but the current package documentation says it only supports English and requires dictionary assets.
- `kokoro_tts_flutter` is still a relatively young package from an unverified uploader with low adoption signals, so it validates feasibility more than maturity.

The ONNX runtime layer is available and current.

- `flutter_onnxruntime` was updated on March 28, 2026 and supports Android, iOS, Linux, macOS, web, and Windows.
- `flutter_onnxruntime` documents platform constraints that matter to the product: iOS requires version `16.0` or newer and macOS requires version `14.0` or newer.

There is one important ecosystem tension here:

- `kokoro_tts_flutter` describes itself as supporting multi-language synthesis.
- `malsami`, which it uses for phonemization, currently documents English-only support.

My inference from those two sources is that English is the safest supported language target for the product today, and broader language expectations should be treated as a research item rather than a solved assumption.

The product requirement that voices be bundled and managed by the app is not solved by these packages alone.

- The packages provide inference and basic speech generation.
- They do not replace the need for a product-level voice library, bundled starter voices, downloadable voices, local caching, progress reporting, or cache management.

### 4. Audio playback and background control are already well covered

- `just_audio` is mature, cross-platform, and supports file, asset, URL, and byte-stream playback.
- `just_audio` supports clip playback, speed changes, playlists, lazy preparation, and gapless playback.
- `audio_service` is explicitly positioned as suitable for text-to-speech readers and provides background audio, media notification, lock screen controls, headset controls, and a standard audio handler model.
- `audio_service` also documents `fast forward` and `rewind`, which aligns cleanly with the product’s 30-second jump controls.

This means the product does not need to invent its own playback stack from scratch. The custom work should stay focused on chunk generation, queueing, progress mapping, and product-specific state behavior.

### 5. Accessibility expectations are well documented and should be treated as product requirements

Flutter’s official accessibility documentation aligns closely with the product direction.

- Flutter’s accessibility checklist says the UI should remain legible and usable at very large text scale factors.
- Flutter’s accessibility testing docs recommend testing labeled tap targets, tap target size, and text contrast with the Accessibility Guideline API.
- The same docs recommend VoiceOver and TalkBack inspection flows for iOS and Android.

This is especially relevant for `Read Aloud` because the product is fundamentally a reading tool and should assume above-average accessibility expectations.

### 6. Publishing standards reinforce the future direction for chapters, landmarks, and synchronized reading

The standards direction still matches the earlier product thinking.

- EPUB 3.3 defines `toc`, `page-list`, and `landmarks` navigation structures, including landmarks like `toc`, `bodymatter`, and list-of-illustrations style navigation.
- EPUB 3.3 also defines Media Overlays for synchronizing text and audio.
- SSML 1.1 remains the primary standard for controlling synthesized speech structure and prosody, including paragraphs, sentences, breaks, prosody control, marks, and phonemes.

This does not force those features into `v1`, but it does validate the decision to keep the internal model rich enough to support chapter navigation, highlighting, and future prosody control later.

## Implications

### What the research validates

- The current local-first Flutter direction is viable.
- The normalized document architecture remains the right long-term shape.
- The choice to keep PDF first-class and HTML/rich markup central is well supported.
- The choice to avoid a plain-text-only reader surface is strongly supported by the available ecosystem.

### What the research suggests we should keep doing

- Keep PDF as a first-class document type using `pdfrx`.
- Treat EPUB as parser-first and normalization-first rather than relying on a viewer package as the app’s internal model.
- Keep Kokoro local and bundled, but own voice management at the product layer.
- Keep generated audio reuse and queue-based playback as product responsibilities above the package layer.

### Where the ecosystem is weaker than the product

- Mobile share-in is available, but full cross-platform share/open behavior still needs product-owned integration work.
- DOCX and especially RTF do not have a clearly mature, trusted rendering path at the same level as PDF and HTML.
- Voice packages do not provide the full product experience for bundled voices, downloads, progress, cache lifetime, and library management.

### Recommended product-facing interpretation

The product definition does not need major revision yet.

The research mostly reinforces the existing product direction, with three meaningful adjustments:

- PDF and HTML are the strongest rendering foundations today.
- EPUB is strong enough to support a real import pipeline, but likely should not define the whole reading architecture.
- DOCX and RTF should be treated as more lossy import formats until the ecosystem proves otherwise.

## References

- File Picker: https://pub.dev/packages/file_picker
- File Selector: https://pub.dev/packages/file_selector
- desktop_drop: https://pub.dev/packages/desktop_drop
- file_open: https://pub.dev/documentation/file_open/latest/
- share_intent_package: https://pub.dev/packages/share_intent_package
- flutter_html: https://pub.dev/packages/flutter_html
- flutter_html_audio: https://pub.dev/packages/flutter_html_audio
- flutter_html_video: https://pub.dev/packages/flutter_html_video
- flutter_html_table: https://pub.dev/packages/flutter_html_table
- pdfrx: https://pub.dev/packages/pdfrx
- epubx: https://pub.dev/packages/epubx
- epub_view: https://pub.dev/packages/epub_view
- epub_decoder: https://pub.dev/packages/epub_decoder
- docx_file_viewer: https://pub.dev/packages/docx_file_viewer
- kokoro_tts_flutter: https://pub.dev/packages/kokoro_tts_flutter
- flutter_onnxruntime: https://pub.dev/packages/flutter_onnxruntime
- malsami: https://pub.dev/packages/malsami
- just_audio: https://pub.dev/packages/just_audio
- audio_service: https://pub.dev/packages/audio_service
- Flutter Accessibility: https://docs.flutter.dev/ui/accessibility
- Flutter Accessibility Testing: https://docs.flutter.dev/ui/accessibility/accessibility-testing
- EPUB 3.3: https://www.w3.org/TR/2021/WD-epub-33-20210929/
- SSML 1.1: https://www.w3.org/TR/speech-synthesis11/
