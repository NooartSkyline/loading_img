enum MediaKind { image, video }

extension MediaKindLabel on MediaKind {
  String get label => switch (this) {
        MediaKind.image => 'รูป',
        MediaKind.video => 'วิดีโอ',
      };
}
