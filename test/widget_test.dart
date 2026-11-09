import 'package:flutter_test/flutter_test.dart';
import 'package:car_wash_platform/main.dart';

void main() {
  testWidgets('欢迎动画结束后可进入洗车模块', (tester) async {
    await tester.pumpWidget(const CarWashApp());
    await tester.pumpAndSettle();

    expect(find.text('让爱车焕然一新'), findsNothing);
    expect(find.text('洗车'), findsOneWidget);

    await tester.tap(find.text('洗车'));
    await tester.pumpAndSettle();

    expect(find.text('预约专业洗车服务'), findsWidgets);
    expect(find.text('洗车'), findsWidgets);
  });
}