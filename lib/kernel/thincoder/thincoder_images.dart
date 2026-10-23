part of 'thincoder_kernel.dart';

// The pictures face of the kernel: the editor contexts a turn carries, the
// pictures it sends — written where the agent runs, or as native image blocks
// — and the names and limits they go under. The class keeps the fields.

/// The turn's [contexts], one per file (its canonical absolute path):
/// the same file said twice is said once.
List<EditorContext> _contextsOf(List<EditorContext> contexts) {
  final seen = <String>{};
  return [
    for (final context in contexts)
      if (seen.add(context.dedupeKey)) context,
  ];
}

/// The pictures of [turn] as the message to send: each saved where the
/// agent runs (`<cwd>/.thincoder/tmp/paste-<runId>-<i>.<ext>`, the
/// terminal's own naming) and named in the text; what is too big, or
/// cannot be written, dropped and counted (F6).
({String text, List<ImageAttachment> images, int dropped}) _attachImagesOf(
  ThincoderKernel owner,
  KernelTurn turn,
) {
  final parts = [
    if (turn.text.trim().isNotEmpty) turn.text,
  ];
  var dropped = 0;
  final images = <ImageAttachment>[];
  final paths = <String>[];
  if (turn.images.isNotEmpty) {
    final runId = ThincoderKernel._runId();
    final dir = p.join(owner._cwd, '.thincoder', 'tmp');
    var budget = ThincoderKernel.turnMaxBytes;
    for (final (index, image) in turn.images.indexed) {
      final ext = ThincoderKernel._imageExtension(image.mediaType);
      final bytes = image.bytes.length;
      final over = ext == null || bytes == 0 || bytes > ThincoderKernel.imageMaxBytes;
      if (over || bytes > budget) {
        dropped++;
        continue;
      }
      try {
        Directory(dir).createSync(recursive: true);
        final file = File(p.join(dir, 'paste-$runId-$index.$ext'));
        file.writeAsBytesSync(image.bytes);
        paths.add(file.path);
        budget -= bytes;
        images.add(image);
      } on FileSystemException catch (error) {
        dropped++;
        appEvent('thincoder', 'an image was not written: ${error.message}');
      }
    }
  }
  if (paths.isNotEmpty) {
    parts.add('[Attached images: ${paths.join(' | ')}]');
  }
  return (text: parts.join('\n\n'), images: images, dropped: dropped);
}

/// [turn]'s pictures as native image blocks (F19), under the same limits.
({String text, List<ImageAttachment> images, int dropped}) _nativePromptOf(
  ThincoderKernel owner,
  KernelTurn turn,
) {
  var dropped = 0;
  final images = <ImageAttachment>[];
  var budget = ThincoderKernel.turnMaxBytes;
  for (final image in turn.images) {
    final ext = ThincoderKernel._imageExtension(image.mediaType);
    final bytes = image.bytes.length;
    if (ext == null || bytes == 0 || bytes > ThincoderKernel.imageMaxBytes || bytes > budget) {
      dropped++;
      continue;
    }
    budget -= bytes;
    images.add(image);
  }
  return (text: turn.text, images: images, dropped: dropped);
}

/// The extension of a picture of [mediaType], as the terminal names it;
/// null for one it does not take.
String? _imageExtensionOf(String mediaType) => switch (mediaType) {
  'image/png' => 'png',
  'image/jpeg' => 'jpg',
  'image/gif' => 'gif',
  'image/webp' => 'webp',
  _ => null,
};

/// What a run of saved pictures is named under: when, and a little
/// chance (`Date.now().toString(36) + 4 random`).
String _runIdOf() => [
  DateTime.now().millisecondsSinceEpoch.toRadixString(36),
  for (var i = 0; i < 4; i++) ThincoderKernel._letters[ThincoderKernel._random.nextInt(ThincoderKernel._letters.length)],
].join();
