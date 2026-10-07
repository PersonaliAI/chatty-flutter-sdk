/// Official Flutter SDK for Chatty AI chatbots — chat widget, floating
/// launcher, theming (including per-section color_scheme overrides), and
/// real CommonMark/GFM + LaTeX markdown rendering. Mirrors the web widget
/// (chatty/packages/chatty-react) and chatty-android-sdk feature-for-feature.
library;

export 'src/chatty_api.dart'
    show
        chattyDefaultBaseUrl,
        ChattyTheme,
        ChattyColorScheme,
        ChattySectionColors,
        ChattyClient,
        ChattyChatResponse,
        ChattyVoiceToken,
        ChattyPollMessage,
        ChattyPollResponse,
        ChattyRateLimitException,
        ChattyDomainNotAllowedException,
        ChattyRequestException;
export 'src/chatty_controller.dart' show ChattyController, ChattyMessage, ChattyRole;
export 'src/chatty_session.dart' show ChattySession;
export 'src/chatty_chat_screen.dart' show ChattyChatScreen;
// Primary integration path — loads the actual web widget page in a WebView,
// guaranteeing exact parity with it. See ChattyChatScreen above for the
// native-components alternative (more native feel, manually kept in parity).
export 'src/chatty_embed_screen.dart' show ChattyEmbedScreen, ChattyVoiceScreen, chattyDefaultEmbedBaseUrl, chattyBridgeShimJs;
export 'src/chatty_launcher.dart' show ChattyLauncher, ChattyPosition;
export 'src/chatty_markdown.dart' show ChattyMarkdown, chattyExtractMath, ChattyMathSpan;
export 'src/chatty_design_tokens.dart' show ChattyDesignTokens, chattyDesignTokens, chattyNormalizeWidgetStyle;

