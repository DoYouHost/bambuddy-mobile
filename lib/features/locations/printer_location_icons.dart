import 'package:flutter/material.dart';

/// Maps a location's icon name to a Material glyph.
///
/// The server stores the Lucide names the web's `IconPicker` offers
/// ([printerLocationIcons]); each is drawn with the closest Material glyph so a
/// location styled on the web reads the same here. Unknown or `null` shows the
/// default box, as the web does.
IconData printerLocationIcon(String? name) => switch (name) {
  'globe' => Icons.language,
  'link' => Icons.link,
  'external-link' => Icons.open_in_new,
  'book' => Icons.menu_book_outlined,
  'file-text' => Icons.description_outlined,
  'home' => Icons.home_outlined,
  'star' => Icons.star_outline,
  'heart' => Icons.favorite_border,
  'bookmark' => Icons.bookmark_border,
  'shopping-cart' => Icons.shopping_cart_outlined,
  'music' => Icons.music_note_outlined,
  'video' => Icons.videocam_outlined,
  'image' => Icons.image_outlined,
  'camera' => Icons.photo_camera_outlined,
  'map' => Icons.map_outlined,
  'compass' => Icons.explore_outlined,
  'coffee' => Icons.coffee_outlined,
  'gift' => Icons.card_giftcard,
  'wrench' => Icons.build_outlined,
  'zap' => Icons.bolt_outlined,
  'cloud' => Icons.cloud_outlined,
  'database' => Icons.storage_outlined,
  'folder' => Icons.folder_outlined,
  'mail' => Icons.mail_outline,
  'phone' => Icons.phone_outlined,
  'user' => Icons.person_outline,
  'users' => Icons.group_outlined,
  'server' => Icons.dns_outlined,
  'terminal' => Icons.terminal,
  'code' => Icons.code,
  _ => Icons.inventory_2_outlined,
};
