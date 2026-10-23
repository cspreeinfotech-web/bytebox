import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show UserAttributes;

import '../services/session.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Shows "Please log in" with a reason; returns true once the user is logged in.
Future<bool> requireLogin(BuildContext context, {String title = 'Please log in', String? message}) async {
  if (session.isLoggedIn) return true;
  final go = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message ?? 'Log in or create a free account to continue.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not now')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Log in')),
      ],
    ),
  );
  if (go != true || !context.mounted) return false;
  final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const LoginScreen()));
  return ok == true && session.isLoggedIn;
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.startWithCreate = false});
  final bool startWithCreate;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late bool _create = widget.startWithCreate;
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      if (_create) {
        await session.createAccount(_email.text, _password.text);
      } else {
        await session.logIn(_email.text, _password.text);
      }
      if (!mounted) return;
      if (session.isLoggedIn) {
        Navigator.pop(context, true);
      } else {
        showSnack(context, 'Check your email to confirm your account, then log in.');
      }
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      showSnack(context, 'Enter your email first, then tap Forgot password.');
      return;
    }
    try {
      await session.forgotPassword(email);
      if (mounted) showSnack(context, 'We sent a password reset link to $email.');
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _google() async {
    setState(() => _busy = true);
    final enabled = await session.googleEnabled();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!enabled) {
      showSnack(context, 'Google sign-in is coming soon. Please log in with email.');
      return;
    }
    try {
      await session.signInWithGoogle();
      if (mounted) Navigator.pop(context, false); // session updates via deep link
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            const Center(child: BrandMark(size: 72)),
            const SizedBox(height: 16),
            Text(_create ? 'Create account' : 'Log in',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              _create ? 'Keep your cloud files and plans safe across devices.' : 'Welcome back to Bytebox.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 28),
            Form(
              key: _form,
              child: Column(children: [
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                  validator: (v) => (v == null || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim()))
                      ? 'Enter a valid email'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  autofillHints: [_create ? AutofillHints.newPassword : AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Show password' : 'Hide password',
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) => (v == null || v.length < 6) ? 'At least 6 characters' : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
              ]),
            ),
            if (!_create)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: _busy ? null : _forgot, child: const Text('Forgot password?')),
              )
            else
              const SizedBox(height: 16),
            GradientButton(label: _create ? 'Create account' : 'Log in', busy: _busy, onPressed: _submit),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _busy ? null : _google,
              icon: const Icon(Icons.g_mobiledata, size: 28),
              label: const Text('Continue with Google'),
            ),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(_create ? 'Already have an account?' : 'New to Bytebox?',
                  style: const TextStyle(color: AppColors.textMuted)),
              TextButton(
                onPressed: _busy ? null : () => setState(() => _create = !_create),
                child: Text(_create ? 'Log in' : 'Create account'),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Shown after a password-recovery deep link.
Future<void> showSetNewPassword(BuildContext context) async {
  final ctrl = TextEditingController();
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      title: const Text('Set a new password'),
      content: TextField(controller: ctrl, obscureText: true, decoration: const InputDecoration(labelText: 'New password')),
      actions: [
        FilledButton(
          onPressed: () async {
            if (ctrl.text.length < 6) return;
            try {
              await db.auth.updateUser(UserAttributes(password: ctrl.text));
              if (c.mounted) Navigator.pop(c);
            } catch (e) {
              if (c.mounted) showSnack(c, friendlyError(e), error: true);
            }
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
