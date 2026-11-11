/// Persisted interest frequencies. Monthly retains the fixed 30-day policy.
enum InterestType {
  none('None', '', null),
  daily('Daily', 'day', Duration(days: 1)),
  weekly('Weekly', 'week', Duration(days: 7)),
  monthly('Monthly', 'mo', Duration(days: 30));

  const InterestType(this.label, this.unitLabel, this.period);

  final String label;
  final String unitLabel;
  final Duration? period;

  static bool isValid(String value) => values.any((type) => type.name == value);

  static InterestType fromString(String value) => values.firstWhere(
    (type) => type.name == value,
    orElse: () => throw ArgumentError.value(value, 'interestType'),
  );

  String get accrualDescription => this == none
      ? 'No interest.'
      : 'Rate applies to remaining principal every completed '
            '${period!.inDays == 1 ? 'day' : '${period!.inDays} days'}, '
            'starting when utang is recorded. No interest on interest. '
            'A 0% rate means no interest.';
}
