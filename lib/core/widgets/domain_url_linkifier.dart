import 'package:flutter_linkify/flutter_linkify.dart';

class DomainUrlLinkifier extends Linkifier {
  const DomainUrlLinkifier();

  @override
  List<LinkifyElement> parse(
    List<LinkifyElement> elements,
    LinkifyOptions options,
  ) {
    final list = <LinkifyElement>[];
    final regex = RegExp(
      r'((?:https?:\/\/|www\.)[^\s]+|(?:[a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}(?:\/[^\s]*)?)',
      caseSensitive: false,
    );

    for (final element in elements) {
      if (element is TextElement) {
        final text = element.text;
        int start = 0;
        for (final match in regex.allMatches(text)) {
          if (match.start > start) {
            list.add(TextElement(text.substring(start, match.start)));
          }
          final urlText = match.group(0)!;
          String cleanUrl = urlText;
          String trailingPunct = '';
          while (cleanUrl.endsWith('.') ||
              cleanUrl.endsWith(',') ||
              cleanUrl.endsWith('!')) {
            trailingPunct = cleanUrl[cleanUrl.length - 1] + trailingPunct;
            cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
          }
          list.add(UrlElement(cleanUrl, cleanUrl));
          if (trailingPunct.isNotEmpty) {
            list.add(TextElement(trailingPunct));
          }
          start = match.end;
        }
        if (start < text.length) {
          list.add(TextElement(text.substring(start)));
        }
      } else {
        list.add(element);
      }
    }
    return list;
  }
}
