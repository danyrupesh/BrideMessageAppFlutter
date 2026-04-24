class TamilSong {
  final int id;
  final String? songId;
  final int? numericId;
  final String name;
  final String? tamilName;
  final int? artistId;
  final String? pptUrl;
  final bool hasPpt;
  final bool hasLyrics;
  final String? lyricsPreview;
  final String? fullLyrics;
  final int downloadCount;
  final int viewCount;
  final bool isFeatured;
  final bool isActive;
  final String? artistName;

  TamilSong({
    required this.id,
    this.songId,
    this.numericId,
    required this.name,
    this.tamilName,
    this.artistId,
    this.pptUrl,
    required this.hasPpt,
    required this.hasLyrics,
    this.lyricsPreview,
    this.fullLyrics,
    this.downloadCount = 0,
    this.viewCount = 0,
    required this.isFeatured,
    required this.isActive,
    this.artistName,
  });

  factory TamilSong.fromRow(Map<String, dynamic> row) {
    return TamilSong(
      id: row['id'] as int,
      songId: row['song_id'] as String?,
      numericId: row['numeric_id'] as int?,
      name: row['name'] as String? ?? '',
      tamilName: row['tamil_name'] as String?,
      artistId: row['artist_id'] as int?,
      pptUrl: row['ppt_url'] as String?,
      hasPpt: (row['has_ppt'] as int? ?? 0) == 1,
      hasLyrics: (row['has_lyrics'] as int? ?? 0) == 1,
      lyricsPreview: row['lyrics_preview'] as String?,
      fullLyrics: row['full_lyrics'] as String?,
      downloadCount: row['download_count'] as int? ?? 0,
      viewCount: row['view_count'] as int? ?? 0,
      isFeatured: (row['is_featured'] as int? ?? 0) == 1,
      isActive: (row['is_active'] as int? ?? 0) == 1,
      artistName: row['artist_name'] as String?,
    );
  }

  String get displayName => tamilName ?? name;
}

class TamilArtist {
  final int id;
  final String name;
  final String? slug;
  final String? description;

  TamilArtist({
    required this.id,
    required this.name,
    this.slug,
    this.description,
  });

  factory TamilArtist.fromRow(Map<String, dynamic> row) {
    return TamilArtist(
      id: row['id'] as int,
      name: row['name'] as String? ?? '',
      slug: row['slug'] as String?,
      description: row['description'] as String?,
    );
  }
}

class TamilTag {
  final int id;
  final String name;
  final String? slug;
  final String? category;
  final String? color;

  TamilTag({
    required this.id,
    required this.name,
    this.slug,
    this.category,
    this.color,
  });

  factory TamilTag.fromRow(Map<String, dynamic> row) {
    return TamilTag(
      id: row['id'] as int,
      name: row['name'] as String? ?? '',
      slug: row['slug'] as String?,
      category: row['category'] as String?,
      color: row['color'] as String?,
    );
  }
}

enum TamilSongSort {
  nameAz,
  songNo,
  mostViewed,
  mostDownloaded,
  latest,
}
