final uri = Uri.tryParse(song.id);

if (uri == null ||
    uri.scheme != 'https' ||
    uri.host.isEmpty) {
  throw Exception('URL HTTPS e pavlefshme');
}

mediaItem.add(item(song));
await player.setUrl(song.id);
await player.play();
