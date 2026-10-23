import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../services/links.dart';
import '../services/session.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// First-open consent (version v1). Cannot be dismissed without agreeing.
Future<void> showConsentDialog(BuildContext context) => showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(canPop: false, child: _ConsentDialog()),
    );

class _ConsentDialog extends StatefulWidget {
  const _ConsentDialog();
  @override
  State<_ConsentDialog> createState() => _ConsentDialogState();
}

class _ConsentDialogState extends State<_ConsentDialog> {
  bool _busy = false;

  TextSpan _link(String text, String url) => TextSpan(
        text: text,
        style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
        recognizer: TapGestureRecognizer()..onTap = () => Links.open(url),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(children: [BrandMark(size: 32), SizedBox(width: 12), Text('Welcome to Bytebox')]),
      content: Text.rich(
        TextSpan(
          style: const TextStyle(color: AppColors.textMuted, height: 1.5),
          children: [
            const TextSpan(text: 'Before you start, please read and accept our '),
            _link('Privacy Policy', Links.privacy),
            const TextSpan(text: ', '),
            _link('Terms of Use', Links.terms),
            const TextSpan(text: ', '),
            _link('Refund Policy', Links.refund),
            const TextSpan(text: ' and '),
            _link('Community Guidelines', Links.community),
            const TextSpan(text: '.\n\nYou must be 18 or older to use Bytebox.'),
          ],
        ),
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: GradientButton(
            label: 'Agree & continue',
            busy: _busy,
            onPressed: () async {
              setState(() => _busy = true);
              try {
                await session.acceptConsent();
                if (context.mounted) Navigator.pop(context);
              } catch (e) {
                if (context.mounted) showSnack(context, friendlyError(e), error: true);
                setState(() => _busy = false);
              }
            },
          ),
        ),
      ],
    );
  }
}
