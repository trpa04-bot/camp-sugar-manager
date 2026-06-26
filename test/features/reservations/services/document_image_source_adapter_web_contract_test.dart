import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File(
    'lib/features/reservations/services/document_image_source_adapter_web.dart',
  ).readAsStringSync();
  final adapterEntry = File(
    'lib/features/reservations/services/document_image_source_adapter.dart',
  ).readAsStringSync();

  test('gallery picker uses image accept and no capture', () {
    expect(source.contains("pickFromGallery()"), isTrue);
    expect(source.contains("_pickUsingInput(accept: 'image/*')"), isTrue);
  });

  test('file picker uses image and pdf accept and no capture', () {
    expect(source.contains("pickFromFile()"), isTrue);
    expect(
      source.contains("_pickUsingInput(accept: 'image/*,application/pdf')"),
      isTrue,
    );
  });

  test('mobile camera path keeps capture attribute', () {
    expect(
      source.contains(
        "_pickUsingInput(accept: 'image/*', capture: 'environment')",
      ),
      isTrue,
    );
  });

  test('input is type=file and appended to DOM before click', () {
    expect(source.contains("input.setAttribute('type', 'file');"), isTrue);
    expect(source.contains('html.document.body?.append(input);'), isTrue);
    expect(source.contains('input.click();'), isTrue);
  });

  test('same file reselection reset exists', () {
    expect(source.contains("input.value = '';"), isTrue);
  });

  test('listeners are removed and input cleaned up', () {
    expect(source.contains('await changeSub.cancel();'), isTrue);
    expect(source.contains('await blurSub.cancel();'), isTrue);
    expect(source.contains('input.remove();'), isTrue);
  });

  test('conditional import routes to web adapter implementation', () {
    expect(
      adapterEntry.contains(
        "if (dart.library.html) 'document_image_source_adapter_web.dart'",
      ),
      isTrue,
    );
  });
}
