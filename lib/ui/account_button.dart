import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../navigate.dart' if (dart.library.js_interop) '../navigate_web.dart';

class AccountButton extends StatefulWidget {
  const AccountButton({super.key});

  @override
  State<AccountButton> createState() => _AccountButtonState();
}

class _AccountButtonState extends State<AccountButton> {
  User? _user;
  late final StreamSubscription<AuthState> _authSub;

  @override
  void initState() {
    super.initState();
    _user = Supabase.instance.client.auth.currentUser;
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      setState(() => _user = data.session?.user);
    });
  }

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_user != null) {
      return PopupMenuButton<String>(
        icon: const Icon(Icons.person),
        tooltip: 'Account',
        position: PopupMenuPosition.under,
        onSelected: (value) {
          if (value == 'account') navigateToUrl('/account/');
          if (value == 'sign_out') _signOut();
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            enabled: false,
            child: Text(
              _user!.email ?? 'Signed in',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'account',
            child: Row(
              children: [
                Icon(Icons.manage_accounts, size: 20),
                SizedBox(width: 12),
                Text('Account'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'sign_out',
            child: Row(
              children: [
                Icon(Icons.logout, size: 20),
                SizedBox(width: 12),
                Text('Sign out'),
              ],
            ),
          ),
        ],
      );
    }

    return IconButton(
      icon: const Icon(Icons.person_outline),
      tooltip: 'Sign in',
      onPressed: () => _showSignInDialog(context),
    );
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
  }

  void _showSignInDialog(BuildContext context) {
    showDialog(context: context, builder: (context) => const _SignInDialog());
  }
}

class _SignInDialog extends StatefulWidget {
  const _SignInDialog();

  @override
  State<_SignInDialog> createState() => _SignInDialogState();
}

class _SignInDialogState extends State<_SignInDialog> {
  final _emailCtl = TextEditingController();
  final _passwordCtl = TextEditingController();
  bool _isSignUp = false;
  bool _loading = false;
  String? _message;
  bool _isError = true;
  late final StreamSubscription<AuthState> _authSub;

  @override
  void initState() {
    super.initState();
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedIn && mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _authSub.cancel();
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
        // Dialog closes via onAuthStateChange listener
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
      redirectTo: '${Uri.base.origin}/account/callback',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? Colors.white : Colors.black;
    final cardBg = isDark ? const Color(0xF0151015) : const Color(0xF0F5F1EA);
    final accent = isDark ? const Color(0xFFD4A853) : const Color(0xFF8B6F37);

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
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _message!,
                    style: TextStyle(
                      color: _isError ? Colors.redAccent : Colors.green,
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
                    foregroundColor: isDark ? Colors.black : Colors.white,
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
