## 0.0.3

* Wrap `ChattyEmbedScreen` in `SafeArea` when `topInset` is omitted to guarantee status bar / notch clearance.
* Pass explicit `topInset=0` to embedded web view when handled by native `SafeArea` to prevent double top padding.
* Add responsive width constraints (`ConstrainedBox` with screen width and `maxLines: 2` with `TextOverflow.ellipsis`) to conversation starter chips in `ChattyChatScreen`.

## 0.0.2

* Fix mobile status bar overlap and vertical responsiveness in `ChattyEmbedScreen`.
* Automatically deliver `MediaQuery` safe area insets (top and bottom) to the embedded web widget via `chatty-safe-area`.
* Add optional `topInset` and `bottomInset` parameters to `ChattyEmbedScreen` for custom status bar and navigation bar insets.
* Pass `platform=flutter` and `safeArea=true` in embed URL query parameters.

## 0.0.1

* Initial release of official Chatty Flutter SDK with chat widget, floating launcher, theming, and markdown/LaTeX rendering.
