import 'package:flutter/material.dart';
import '../services/lock_api_service.dart';

/// Hidden API Configuration Panel for Godrej Lock
/// Access via double-tap on "Godrej Advantis IoT9" text
class ApiConfigPanel extends StatefulWidget {
  const ApiConfigPanel({super.key});

  @override
  State<ApiConfigPanel> createState() => _ApiConfigPanelState();
}

class _ApiConfigPanelState extends State<ApiConfigPanel> {
  final LockApiService _lockApi = LockApiService();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();

  bool _isLoading = false;
  bool _otpSent = false;
  String _statusMessage = '';
  bool _isSuccess = false;

  @override
  void initState() {
    super.initState();
    _loadSavedState();
  }

  Future<void> _loadSavedState() async {
    await _lockApi.initialize();
    setState(() {
      _phoneController.text = _lockApi.phoneNumber;
      if (_lockApi.isConfigured) {
        _statusMessage = '✅ Configured - Lock ID: ${_lockApi.lockId}';
        _isSuccess = true;
      }
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _setStatus(String message, bool success) {
    setState(() {
      _statusMessage = message;
      _isSuccess = success;
    });
  }

  Future<void> _requestOTP() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty || phone.length < 10) {
      _setStatus('Please enter a valid phone number', false);
      return;
    }

    setState(() => _isLoading = true);

    final (success, message) = await _lockApi.requestOTP(phone);

    setState(() {
      _isLoading = false;
      _otpSent = success;
    });
    _setStatus(message, success);
  }

  Future<void> _verifyOTP() async {
    final otp = _otpController.text.trim();
    if (otp.isEmpty || otp.length < 4) {
      _setStatus('Please enter a valid OTP', false);
      return;
    }

    setState(() => _isLoading = true);

    final (success, message) = await _lockApi.verifyOTP(otp);

    if (success) {
      // Fetch lock list after successful OTP verification
      _setStatus('Fetching lock list...', true);
      final (lockSuccess, lockMessage) = await _lockApi.fetchLockList();

      if (lockSuccess) {
        await _lockApi.saveConfiguration(
          _phoneController.text.trim(),
          _lockApi.lockId,
        );
        _setStatus(
          '✅ Configuration complete!\nLock ID: ${_lockApi.lockId}',
          true,
        );
      } else {
        _setStatus(lockMessage, false);
      }
    } else {
      _setStatus(message, false);
    }

    setState(() => _isLoading = false);
  }

  Future<void> _testUnlock() async {
    setState(() => _isLoading = true);
    _setStatus('Testing unlock...', true);

    final (success, message) = await _lockApi.unlockDoor();

    setState(() => _isLoading = false);
    _setStatus(success ? '🔓 $message' : '❌ $message', success);
  }

  Future<void> _refreshToken() async {
    setState(() => _isLoading = true);
    _setStatus('Refreshing token...', true);

    final success = await _lockApi.refreshAccessToken();

    setState(() => _isLoading = false);
    _setStatus(
      success
          ? '✅ Token refreshed'
          : '❌ Token refresh failed - re-authenticate',
      success,
    );
  }

  Future<void> _clearConfiguration() async {
    await _lockApi.clearAllTokens();
    setState(() {
      _otpSent = false;
      _otpController.clear();
    });
    _setStatus('Configuration cleared', true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Row(
          children: [
            Icon(Icons.settings, color: Colors.orange, size: 24),
            SizedBox(width: 8),
            Text(
              'Lock API Configuration',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _isSuccess
                    ? Colors.green.withOpacity(0.2)
                    : Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isSuccess ? Colors.green : Colors.orange,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _lockApi.isConfigured
                        ? Icons.check_circle
                        : Icons.info_outline,
                    color: _isSuccess ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _statusMessage.isEmpty
                          ? 'Configure lock API to enable remote unlock'
                          : _statusMessage,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Phone number input
            const Text(
              'Phone Number',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Enter 10-digit phone number',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                prefixIcon: const Icon(Icons.phone, color: Colors.blue),
                prefixText: '+91 ',
                prefixStyle: const TextStyle(color: Colors.white),
                filled: true,
                fillColor: Colors.white.withOpacity(0.1),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Request OTP button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _requestOTP,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.sms),
                label: Text(_otpSent ? 'Resend OTP' : 'Request OTP'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            // OTP Section (shown after OTP sent)
            if (_otpSent) ...[
              const SizedBox(height: 24),
              const Text(
                'Enter OTP',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white, letterSpacing: 8),
                textAlign: TextAlign.center,
                maxLength: 6,
                decoration: InputDecoration(
                  hintText: '• • • • • •',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                  counterText: '',
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.1),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _verifyOTP,
                  icon: const Icon(Icons.verified),
                  label: const Text('Verify & Configure'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],

            // Actions when configured
            if (_lockApi.isConfigured) ...[
              const SizedBox(height: 32),
              const Divider(color: Colors.white24),
              const SizedBox(height: 16),

              const Text(
                'Actions',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 12),

              // Test Unlock
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _testUnlock,
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Test Unlock Door'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Refresh Token
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _refreshToken,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Refresh Token'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blue,
                        side: const BorderSide(color: Colors.blue),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _clearConfiguration,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Clear Config'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 32),

            // Info text
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.blue.withOpacity(0.7),
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'After configuration, the door will automatically unlock when face is recognized.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
