// ─────────────────────────────────────────────────────────────────────────────
// base_model.dart — Abstract base class for all data models
// OOP Pillars demonstrated:
//   • Abstraction  — abstract class enforces a serialization contract via toMap()
//   • Encapsulation— private _id exposed only via getter; no public setter
//   • Inheritance  — Product, Order, CustomerDebt, AppUser all extend this
//   • Polymorphism — toMap() is overridden differently by each subclass
// ─────────────────────────────────────────────────────────────────────────────

abstract class BaseModel {
  // Encapsulated: private backing field exposed via getter only (Encapsulation)
  final String _id;

  const BaseModel({required String id}) : _id = id;

  /// Unique identifier — read-only via getter (Encapsulation: no public setter)
  String get id => _id;

  /// Every model must implement its own serialization (Abstraction + Polymorphism)
  Map<String, dynamic> toMap();

  /// Value equality based on identity field (Polymorphism: overrides Object)
  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is BaseModel && other._id == _id);

  @override
  int get hashCode => _id.hashCode;

  @override
  String toString() => '$runtimeType(id: $_id)';
}
