// ─────────────────────────────────────────────────────────────────────────────
// base_model.dart — Abstract base class for all data models
// Purpose : Enforces a consistent identity and serialization contract on every
//           model in the system so any model can be stored, compared, or logged
//           using the same interface.
// OOP Pillars demonstrated:
//   • Abstraction  — abstract class enforces a serialization contract via toMap()
//   • Encapsulation— private _id exposed only via getter; no public setter
//   • Inheritance  — Product, Order, CustomerDebt, AppUser all extend this
//   • Polymorphism — toMap() is overridden differently by each subclass
// ─────────────────────────────────────────────────────────────────────────────

abstract class BaseModel {
  // Encapsulated: private backing field — subclasses cannot change the ID after creation
  final String _id;

  const BaseModel({required String id}) : _id = id;

  /// Unique identifier — read-only via getter (no public setter prevents mutation)
  String get id => _id;

  /// Every model must implement its own serialization to a column map (Abstraction)
  // Used by repositories to write model data to SQLite and Firestore
  Map<String, dynamic> toMap();

  /// Value equality based on the identity field — two models are equal if their IDs match
  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is BaseModel && other._id == _id);

  // Hash is consistent with == so models work correctly in Sets and Map keys
  @override
  int get hashCode => _id.hashCode;

  // Useful for debugging — prints model type and its ID in log output
  @override
  String toString() => '$runtimeType(id: $_id)';
}
