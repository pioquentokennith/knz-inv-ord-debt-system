class DomainException implements Exception {
  const DomainException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

class DataReadException extends DomainException {
  const DataReadException(String message) : super('data_read_failed', message);
}

class StockShortageException extends DomainException {
  const StockShortageException({
    required this.productId,
    required this.productName,
    required this.requiredQuantity,
    required this.availableQuantity,
  }) : super(
         'stock_shortage',
         'Insufficient stock for $productName: need $requiredQuantity, '
             'have $availableQuantity.',
       );

  final String productId;
  final String productName;
  final int requiredQuantity;
  final int availableQuantity;
}

class InvalidOrderTransitionException extends DomainException {
  const InvalidOrderTransitionException(String message)
    : super('invalid_order_transition', message);
}

class OpenDebtException extends DomainException {
  const OpenDebtException(String message) : super('open_debt', message);
}

class SyncOperationException extends DomainException {
  const SyncOperationException(String message)
    : super('sync_operation_failed', message);
}
