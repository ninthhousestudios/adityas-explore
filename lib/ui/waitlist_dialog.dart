import 'package:flutter/material.dart';

import '../api/waitlist_service.dart';

class WaitlistDialog extends StatefulWidget {
  final Color color;
  final bool isDark;
  final VoidCallback onSuccess;

  const WaitlistDialog({
    super.key,
    required this.color,
    required this.isDark,
    required this.onSuccess,
  });

  @override
  State<WaitlistDialog> createState() => _WaitlistDialogState();
}

class _WaitlistDialogState extends State<WaitlistDialog> {
  final _emailController = TextEditingController();
  final _service = WaitlistService();
  String? _error;
  bool _submitting = false;
  bool _submitted = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  String? _validateEmail(String email) {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return 'Email is required.';
    if (trimmed.length > 254) return 'Email is too long.';
    final atIndex = trimmed.indexOf('@');
    if (atIndex < 1) return 'Please enter a valid email.';
    final domain = trimmed.substring(atIndex + 1);
    if (!domain.contains('.')) return 'Please enter a valid email.';
    return null;
  }

  Future<void> _submit() async {
    final validationError = _validateEmail(_emailController.text);
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }

    setState(() {
      _error = null;
      _submitting = true;
    });

    final result = await _service.signup(_emailController.text);

    if (!mounted) return;

    if (result != null) {
      setState(() {
        _error = result;
        _submitting = false;
      });
      return;
    }

    setState(() {
      _submitting = false;
      _submitted = true;
    });

    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSuccess();
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    final cardBg = widget.isDark
        ? const Color(0xF0151015)
        : const Color(0xF0F5F1EA);
    final accentColor = widget.isDark
        ? const Color(0xFFD4A853)
        : const Color(0xFF8B6F37);

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Material(
          color: Colors.transparent,
          child: _submitted
              ? _buildSuccess(color, accentColor)
              : _buildForm(color, accentColor),
        ),
      ),
    );
  }

  Widget _buildForm(Color color, Color accentColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Spacer(),
            Text(
              'Get notified',
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
        const SizedBox(height: 16),
        Text(
          "More reports and products coming soon. Enter your email to be notified when they’re available.",
          style: TextStyle(
            color: color.withValues(alpha: 0.85),
            fontSize: 14,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
          style: TextStyle(color: color),
          decoration: InputDecoration(
            labelText: 'Email address',
            labelStyle: TextStyle(color: color.withValues(alpha: 0.5)),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: color.withValues(alpha: 0.2)),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: accentColor),
            ),
          ),
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: const TextStyle(color: Colors.redAccent, fontSize: 13),
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          height: 44,
          child: FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: widget.isDark ? Colors.black : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: _submitting
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: widget.isDark ? Colors.black : Colors.white,
                    ),
                  )
                : const Text(
                    'Join the waitlist',
                    style: TextStyle(fontSize: 15),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccess(Color color, Color accentColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle_outline, color: accentColor, size: 48),
        const SizedBox(height: 16),
        Text(
          "You’re on the list!",
          style: TextStyle(
            color: color,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "We’ll let you know when in-depth reports are available.",
          style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 14),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
