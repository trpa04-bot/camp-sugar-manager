import 'package:camp_sugar_manager/features/reservations/widgets/reservation_document_scan_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('statusAfterMerge moves to review when result exists', () {
    final status = statusAfterMerge(hasResult: true);

    expect(status, DocumentScanProcessStatus.review);
  });

  test('statusAfterMerge stays in merge state without result', () {
    final status = statusAfterMerge(hasResult: false);

    expect(status, DocumentScanProcessStatus.mergingResults);
  });
}
