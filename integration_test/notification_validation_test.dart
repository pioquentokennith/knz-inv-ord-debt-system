import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';
import '../test/services/notification_service_test.dart' as policy;
import '../test/screens/notification_navigation_test.dart' as navigation;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('Notification policy', policy.main);
  group('Notification navigation', navigation.main);
}
