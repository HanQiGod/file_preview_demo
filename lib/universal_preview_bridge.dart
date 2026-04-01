import 'package:flutter/widgets.dart';

import 'universal_preview_stub.dart'
    if (dart.library.io) 'universal_preview_io.dart'
    as universal_preview;

Widget buildUniversalStrategyPreview({
  required String source,
  required bool isRemote,
}) {
  return universal_preview.buildUniversalStrategyPreview(
    source: source,
    isRemote: isRemote,
  );
}
