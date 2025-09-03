import 'package:emailjs/emailjs.dart';
import 'package:emailjs/emailjs.dart' as EmailJS;

class EmailService {
  static const String _serviceId = 'service_35oqcuc'; // From EmailJS dashboard
  static const String _templateIdApproved = 'template_n94k5hr';
  static const String _templateIdRejected = 'template_wci3bbx';
  static const String _userId = 'VY3qw_YD0zotlMFlP'; // From EmailJS dashboard

  static Future<bool> sendApprovalEmail({
    required String driverName,
    required String driverEmail,
    required String loginUrl,
  }) async {
    try {
      await EmailJS.send(
        _serviceId,
        _templateIdApproved,
        {
          'to_name': driverName,
          'to_email': driverEmail,
          'driver_name': driverName,
          'login_url': loginUrl,
          'company_name': 'VanGo',
        },
        Options(
          publicKey: _userId,
          limitRate: const LimitRate(
            id: 'approval_email',
            throttle: 10000, // 10 seconds
          ),
        ),
      );
      return true;
    } catch (e) {
      print('Error sending approval email: $e');
      return false;
    }
  }

  static Future<bool> sendRejectionEmail({
    required String driverName,
    required String driverEmail,
    required String reason,
  }) async {
    try {
      await EmailJS.send(
        _serviceId,
        _templateIdRejected,
        {
          'to_name': driverName,
          'to_email': driverEmail,
          'driver_name': driverName,
          'reason': reason,
          'company_name': 'VanGo',
          'support_email': 'support@vango.com',
        },
        Options(
          publicKey: _userId,
          limitRate: const LimitRate(
            id: 'rejection_email',
            throttle: 10000, // 10 seconds
          ),
        ),
      );
      return true;
    } catch (e) {
      print('Error sending rejection email: $e');
      return false;
    }
  }
}