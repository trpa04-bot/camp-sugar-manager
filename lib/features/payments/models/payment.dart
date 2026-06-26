import 'package:cloud_firestore/cloud_firestore.dart';

enum PaymentMethod { paypal, revolut, cash, bankTransfer }

extension PaymentMethodX on PaymentMethod {
  String get displayLabel {
    switch (this) {
      case PaymentMethod.paypal:
        return 'PayPal';
      case PaymentMethod.revolut:
        return 'Revolut';
      case PaymentMethod.cash:
        return 'Gotovina';
      case PaymentMethod.bankTransfer:
        return 'Na račun';
    }
  }

  String get icon {
    switch (this) {
      case PaymentMethod.paypal:
        return '💳';
      case PaymentMethod.revolut:
        return '🔵';
      case PaymentMethod.cash:
        return '💵';
      case PaymentMethod.bankTransfer:
        return '🏦';
    }
  }
}

PaymentMethod paymentMethodFromString(String value) {
  return PaymentMethod.values.firstWhere(
    (method) => method.name == value,
    orElse: () => PaymentMethod.cash,
  );
}

class Payment {
  const Payment({
    required this.id,
    required this.reservationId,
    required this.guestName,
    required this.amount,
    required this.method,
    required this.notes,
    required this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String reservationId;
  final String guestName;
  final double amount;
  final PaymentMethod method;
  final String notes;
  final DateTime createdAt;
  final DateTime? updatedAt;

  factory Payment.empty() {
    return Payment(
      id: '',
      reservationId: '',
      guestName: '',
      amount: 0,
      method: PaymentMethod.cash,
      notes: '',
      createdAt: DateTime.now(),
    );
  }

  factory Payment.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return Payment(
      id: (data['id'] as String?) ?? doc.id,
      reservationId: (data['reservationId'] as String?) ?? '',
      guestName: (data['guestName'] as String?) ?? '',
      amount: _readDouble(data['amount']) ?? 0,
      method: paymentMethodFromString((data['method'] as String?) ?? 'cash'),
      notes: (data['notes'] as String?) ?? '',
      createdAt: _readDate(data['createdAt']) ?? DateTime.now(),
      updatedAt: _readDate(data['updatedAt']),
    );
  }

  static DateTime? _readDate(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return null;
  }

  static double? _readDouble(dynamic value) {
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    return null;
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'reservationId': reservationId,
      'guestName': guestName,
      'amount': amount,
      'method': method.name,
      'notes': notes,
      'createdAt': Timestamp.fromDate(createdAt),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
    };
  }

  Payment copyWith({
    String? id,
    String? reservationId,
    String? guestName,
    double? amount,
    PaymentMethod? method,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Payment(
      id: id ?? this.id,
      reservationId: reservationId ?? this.reservationId,
      guestName: guestName ?? this.guestName,
      amount: amount ?? this.amount,
      method: method ?? this.method,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
