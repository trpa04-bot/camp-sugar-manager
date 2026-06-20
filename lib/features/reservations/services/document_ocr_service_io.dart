import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

Future<String?> recognizeDocumentText(XFile file) async {
  final recognizer = TextRecognizer();
  try {
    final inputImage = InputImage.fromFilePath(file.path);
    final recognizedText = await recognizer.processImage(inputImage);
    final text = recognizedText.text.trim();
    return text.isEmpty ? null : text;
  } finally {
    recognizer.close();
  }
}
