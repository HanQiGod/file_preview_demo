import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:universal_file_viewer/universal_file_viewer.dart';

Widget buildUniversalStrategyPreview({
  required String source,
  required bool isRemote,
}) {
  return isRemote
      ? UniversalFileViewer.remote(fileUrl: source)
      : UniversalFileViewer(file: File(source));
}
