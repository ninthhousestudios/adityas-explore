import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../state/auth.dart';
import 'tokens.dart';

/// Opens the email/OAuth sign-in dialog. The single entry point for sign-in
/// across the app: the account button's signed-out state and the Solar Prism
/// chat gate (logged-out → sign in, adityas/ai/85) both call this, so there is
/// one dialog and one auth flow, not two.
void showSignInDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (context) => const SignInDialog(),
  );
}

/// Email + Google/Apple sign-in / sign-up card. Closes itself once
/// [authProvider] flips to a signed-in user.
class SignInDialog extends ConsumerStatefulWidget {
  const SignInDialog({super.key});

  @override
  ConsumerState<SignInDialog> createState() => _SignInDialogState();
}

class _SignInDialogState extends ConsumerState<SignInDialog> {
  final _emailCtl = TextEditingController();
  final _passwordCtl = TextEditingController();
  bool _isSignUp = false;
  bool _loading = false;
  String? _message;
  bool _isError = true;

  @override
  void dispose() {
    _emailCtl.dispose();
    _passwordCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtl.text.trim();
    final password = _passwordCtl.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _message = 'Email and password are required.';
        _isError = true;
      });
      return;
    }

    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      final client = Supabase.instance.client;
      if (_isSignUp) {
        await client.auth.signUp(email: email, password: password);
        if (!mounted) return;
        setState(() {
          _message = 'Check your email to confirm your account.';
          _isError = false;
          _loading = false;
        });
      } else {
        await client.auth.signInWithPassword(email: email, password: password);
        // Dialog closes via the authProvider listener in build (user -> non-null)
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _message = e.message;
        _isError = true;
        _loading = false;
      });
    }
  }

  Future<void> _oauthSignIn(OAuthProvider provider) async {
    await Supabase.instance.client.auth.signInWithOAuth(
      provider,
      redirectTo: Uri.base.toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Close the dialog once sign-in lands (user transitions null -> non-null).
    ref.listen<User?>(authProvider, (previous, user) {
      if (user != null) Navigator.of(context).pop();
    });

    final t = context.tokens;
    final color = t.ink;
    final cardBg = t.cardBg;
    final accent = t.gold;
    final message = _message;

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 380),
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Material(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Spacer(),
                  Text(
                    _isSignUp ? 'Sign Up' : 'Sign In',
                    style: TextStyle(
                      color: color,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.close, color: color, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _emailCtl,
                keyboardType: TextInputType.emailAddress,
                style: TextStyle(color: color),
                decoration: InputDecoration(
                  labelText: 'Email',
                  labelStyle: TextStyle(color: color.withValues(alpha: 0.6)),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: color.withValues(alpha: 0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: accent),
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordCtl,
                obscureText: true,
                style: TextStyle(color: color),
                decoration: InputDecoration(
                  labelText: 'Password',
                  labelStyle: TextStyle(color: color.withValues(alpha: 0.6)),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: color.withValues(alpha: 0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: accent),
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 16),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    message,
                    style: TextStyle(
                      color: _isError ? t.error : t.success,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _loading ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: t.onGold,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_isSignUp ? 'Sign Up' : 'Sign In'),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _isSignUp
                        ? 'Already have an account?'
                        : "Don't have an account?",
                    style: TextStyle(
                      color: color.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _isSignUp = !_isSignUp;
                      _message = null;
                    }),
                    child: Text(
                      _isSignUp ? 'Sign in' : 'Sign up',
                      style: TextStyle(color: accent, fontSize: 13),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Divider(color: color.withValues(alpha: 0.2)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'or',
                        style: TextStyle(
                          color: color.withValues(alpha: 0.5),
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Divider(color: color.withValues(alpha: 0.2)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _oauthSignIn(OAuthProvider.google),
                  icon: const Icon(Icons.g_mobiledata, size: 24),
                  label: const Text('Continue with Google'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: color,
                    side: BorderSide(color: color.withValues(alpha: 0.3)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _oauthSignIn(OAuthProvider.apple),
                  icon: const Icon(Icons.apple, size: 22),
                  label: const Text('Continue with Apple'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: color,
                    side: BorderSide(color: color.withValues(alpha: 0.3)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
