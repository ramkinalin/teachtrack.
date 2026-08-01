import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/app_contact.dart';
import '../theme/app_spacing.dart';

/// Publisher name and tappable contact links, pinned at the foot of the home
/// screen.
///
/// Slim and always visible rather than appended to the day list, so it is there
/// on a free day and during an exam week too — the day list is empty on both.
class ContactFooter extends StatelessWidget {
  const ContactFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return Material(
      color: scheme.surfaceContainerHighest,
      child: SafeArea(
        // Only the bottom edge: the sides and top belong to the screen above.
        top: false,
        left: false,
        right: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      AppContact.publisherName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelLarge
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    if (AppContact.tagline.isNotEmpty)
                      Text(
                        AppContact.tagline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              if (AppContact.hasEmail)
                IconButton(
                  tooltip: 'Email us',
                  icon: const Icon(Icons.mail_outline_rounded),
                  color: scheme.primary,
                  onPressed: () => _open(
                    context,
                    AppContact.emailUri,
                    'No email app found on this phone',
                  ),
                ),
              if (AppContact.hasWhatsapp)
                IconButton(
                  tooltip: 'Message us on WhatsApp',
                  icon: const Icon(Icons.chat_outlined),
                  color: scheme.primary,
                  onPressed: () => _open(
                    context,
                    AppContact.whatsappUri,
                    'Could not open WhatsApp',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Hands the link to Android, and says so plainly when nothing can handle it.
  ///
  /// `externalApplication` is deliberate: a mail or WhatsApp link should leave the
  /// app rather than open in an in-app web view, which for `mailto:` would do
  /// nothing useful at all.
  static Future<void> _open(
    BuildContext context,
    Uri uri,
    String failureMessage,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    bool launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      launched = false;
    }

    if (!launched) {
      messenger.showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }
}
