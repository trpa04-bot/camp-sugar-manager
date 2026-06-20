import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

enum PitchStatus { available, reserved, occupied, cleaning, unavailable }

PitchStatus pitchStatusFromString(String value) {
  return PitchStatus.values.firstWhere(
    (status) => status.name == value,
    orElse: () => PitchStatus.available,
  );
}

extension PitchStatusX on PitchStatus {
  String get label {
    switch (this) {
      case PitchStatus.available:
        return 'available';
      case PitchStatus.reserved:
        return 'reserved';
      case PitchStatus.occupied:
        return 'occupied';
      case PitchStatus.cleaning:
        return 'cleaning';
      case PitchStatus.unavailable:
        return 'unavailable';
    }
  }

  String get displayLabel {
    switch (this) {
      case PitchStatus.available:
        return 'Slobodna';
      case PitchStatus.reserved:
        return 'Rezervirana';
      case PitchStatus.occupied:
        return 'Zauzeta';
      case PitchStatus.cleaning:
        return 'Ciscenje';
      case PitchStatus.unavailable:
        return 'Nedostupna';
    }
  }

  Color get color {
    switch (this) {
      case PitchStatus.available:
        return const Color(0xFF1F8A70);
      case PitchStatus.reserved:
        return const Color(0xFFB7791F);
      case PitchStatus.occupied:
        return const Color(0xFFD64545);
      case PitchStatus.cleaning:
        return const Color(0xFF5B6B7F);
      case PitchStatus.unavailable:
        return const Color(0xFF374151);
    }
  }
}

class Pitch {
  const Pitch({
    required this.id,
    required this.name,
    required this.number,
    required this.zone,
    required this.status,
    required this.maxGuests,
    required this.currentGuests,
    required this.currentGuestCount,
    this.currentReservationId,
    this.currentPrimaryGuestName,
    this.occupiedFrom,
    this.occupiedUntil,
    required this.hasElectricity,
    required this.hasWater,
    required this.notes,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final int number;
  final String zone;
  final PitchStatus status;
  final int maxGuests;
  final int currentGuests;
  final int currentGuestCount;
  final String? currentReservationId;
  final String? currentPrimaryGuestName;
  final DateTime? occupiedFrom;
  final DateTime? occupiedUntil;
  final bool hasElectricity;
  final bool hasWater;
  final String notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Pitch.empty() {
    return const Pitch(
      id: '',
      name: '',
      number: 1,
      zone: '',
      status: PitchStatus.available,
      maxGuests: 4,
      currentGuests: 0,
      currentGuestCount: 0,
      hasElectricity: true,
      hasWater: true,
      notes: '',
    );
  }

  factory Pitch.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return Pitch(
      id: (data['id'] as String?) ?? doc.id,
      name: (data['name'] as String?) ?? '',
      number: _readInt(data['number']) ?? 0,
      zone: (data['zone'] as String?) ?? '',
      status: pitchStatusFromString((data['status'] as String?) ?? 'available'),
      maxGuests: _readInt(data['maxGuests']) ?? 1,
      currentGuests: _readInt(data['currentGuests']) ?? 0,
      currentGuestCount:
          _readInt(data['currentGuestCount']) ??
          _readInt(data['currentGuests']) ??
          0,
      currentReservationId: (data['currentReservationId'] as String?)?.trim(),
      currentPrimaryGuestName: (data['currentPrimaryGuestName'] as String?)
          ?.trim(),
      occupiedFrom: _readDate(data['occupiedFrom']),
      occupiedUntil: _readDate(data['occupiedUntil']),
      hasElectricity: (data['hasElectricity'] as bool?) ?? false,
      hasWater: (data['hasWater'] as bool?) ?? false,
      notes: (data['notes'] as String?) ?? '',
      createdAt: _readDate(data['createdAt']),
      updatedAt: _readDate(data['updatedAt']),
    );
  }

  static int? _readInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
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

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'number': number,
      'zone': zone,
      'status': status.name,
      'maxGuests': maxGuests,
      'currentGuests': currentGuests,
      'currentGuestCount': currentGuestCount,
      'currentReservationId': currentReservationId,
      'currentPrimaryGuestName': currentPrimaryGuestName,
      'occupiedFrom': occupiedFrom,
      'occupiedUntil': occupiedUntil,
      'hasElectricity': hasElectricity,
      'hasWater': hasWater,
      'notes': notes,
      if (createdAt != null) 'createdAt': createdAt,
      if (updatedAt != null) 'updatedAt': updatedAt,
    };
  }

  Pitch copyWith({
    String? id,
    String? name,
    int? number,
    String? zone,
    PitchStatus? status,
    int? maxGuests,
    int? currentGuests,
    int? currentGuestCount,
    String? currentReservationId,
    String? currentPrimaryGuestName,
    DateTime? occupiedFrom,
    DateTime? occupiedUntil,
    bool? hasElectricity,
    bool? hasWater,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Pitch(
      id: id ?? this.id,
      name: name ?? this.name,
      number: number ?? this.number,
      zone: zone ?? this.zone,
      status: status ?? this.status,
      maxGuests: maxGuests ?? this.maxGuests,
      currentGuests: currentGuests ?? this.currentGuests,
      currentGuestCount: currentGuestCount ?? this.currentGuestCount,
      currentReservationId: currentReservationId ?? this.currentReservationId,
      currentPrimaryGuestName:
          currentPrimaryGuestName ?? this.currentPrimaryGuestName,
      occupiedFrom: occupiedFrom ?? this.occupiedFrom,
      occupiedUntil: occupiedUntil ?? this.occupiedUntil,
      hasElectricity: hasElectricity ?? this.hasElectricity,
      hasWater: hasWater ?? this.hasWater,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
