class ReservationDocumentScanContext {
  const ReservationDocumentScanContext({
    required this.reservationId,
    required this.guestId,
    required this.pitchId,
    required this.pitchName,
    required this.checkInDate,
    required this.checkOutDate,
  });

  final String reservationId;
  final String guestId;
  final String pitchId;
  final String pitchName;
  final DateTime checkInDate;
  final DateTime checkOutDate;
}
