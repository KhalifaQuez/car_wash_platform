import 'booking_data.dart';

enum ActivityLogScope { all, customer, administrator }

/// 按实际操作人分类，而非操作对象或操作名称。
/// 未登录操作仍显示在全部记录，不冒充已登录用户的操作。
List<AccountActivity> filterActivityLogs(
  Iterable<AccountActivity> events,
  ActivityLogScope scope, {
  required String administratorId,
}) => List.unmodifiable(
  events.where(
    (event) => switch (scope) {
      ActivityLogScope.all => true,
      ActivityLogScope.customer =>
        event.actorId != administratorId && event.actorId != 'guest',
      ActivityLogScope.administrator => event.actorId == administratorId,
    },
  ),
);
