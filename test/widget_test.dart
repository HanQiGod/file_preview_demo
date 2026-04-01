import 'package:flutter_test/flutter_test.dart';
import 'package:file_preview_demo/main.dart';

void main() {
  test('detectPreviewKind can classify common file types', () {
    expect(detectPreviewKind('/tmp/demo.png'), PreviewKind.image);
    expect(detectPreviewKind('/tmp/demo.pdf'), PreviewKind.pdf);
    expect(detectPreviewKind('/tmp/demo.md'), PreviewKind.markdown);
    expect(detectPreviewKind('/tmp/demo.csv'), PreviewKind.csv);
    expect(detectPreviewKind('/tmp/demo.docx'), PreviewKind.office);
    expect(detectPreviewKind('https://example.com/file.bin'), PreviewKind.unsupported);
  });
}
