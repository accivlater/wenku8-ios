import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/reader_content.dart';
import 'package:wenku8_flutter/reader_rich_content.dart';

const first = 'https://pic.777743.xyz/2/2451/91509/108506.jpg';
const second = 'https://pic.777743.xyz/2/2451/91509/108507.jpg';
const third = 'https://pic.777743.xyz/2/2451/91509/108508.jpg';

/// The online body as the request returns it: a heading line, whitespace-only
/// lines, then every illustration of the chapter on one line separated by
/// spaces. Without splitting here the run fails [readerIllustrationUrl] and the
/// reader prints the addresses as body text.
const imageChapter =
    ' 第一卷 插图  \r\n'
    ' \r\n'
    '  \r\n'
    '   \r\n'
    '  \r\n'
    ' \r\n'
    '  \r\n'
    '     \r\n'
    '     \r\n'
    '     \r\n'
    '  \r\n'
    ' \r\n'
    '  \r\n'
    '  \r\n'
    '   '
    '<!--image-->$first<!--image-->       '
    '<!--image-->$second<!--image-->       '
    '<!--image-->$third<!--image-->';

void main() {
  test('an unsplit run is exactly what the single-image contract rejects', () {
    expect(
      readerIllustrationUrl(
        '<!--image-->$first<!--image-->   <!--image-->$second<!--image-->',
      ),
      isNull,
    );
    expect(readerIllustrationUrl('<!--image-->$first<!--image-->'), first);
    expect(readerIllustrationUrl(' $first '), isNull);
  });

  test(
    'an illustration run on one line becomes one paragraph per image',
    () async {
      final content = await ReaderContent.parse(imageChapter);
      expect(content.paragraphs.length, 4);
      expect(content.paragraphs.first, '第一卷 插图');
      expect(
        content.paragraphs.skip(1).every((p) => p.startsWith('<!--image-->')),
        true,
      );
      expect(content.illustrations, [first, second, third]);
    },
  );

  test('text around a run keeps its own paragraphs', () async {
    final content = await ReaderContent.parse(
      '前文<!--image-->$first<!--image-->   <!--image-->$second<!--image-->后记',
    );
    expect(content.paragraphs, [
      '前文',
      '<!--image-->$first<!--image-->',
      '<!--image-->$second<!--image-->',
      '后记',
    ]);
    expect(content.illustrations, [first, second]);
    final inline = await ReaderContent.parse(
      '正文<!--image-->$first<!--image-->结尾',
    );
    expect(inline.paragraphs, ['正文', '<!--image-->$first<!--image-->', '结尾']);
    expect(inline.illustrations, [first]);
  });

  test('a sizing suffix stays with its own image', () async {
    final content = await ReaderContent.parse(
      '<!--image-->$first<!--image--><!--epub-image:w=50%-->   '
      '<!--image-->$second<!--image-->',
    );
    expect(content.paragraphs, [
      '<!--image-->$first<!--image--><!--epub-image:w=50%-->',
      '<!--image-->$second<!--image-->',
    ]);
  });

  test('paragraph bodies that already separate images are unchanged', () async {
    final single = await ReaderContent.parse(
      '段落\n\n<!--image-->$first<!--image-->\n\n段落',
    );
    expect(single.paragraphs, ['段落', '<!--image-->$first<!--image-->', '段落']);
    expect(single.illustrations, [first]);
    final padded = await ReaderContent.parse(
      '  <!--image-->$first<!--image-->  ',
    );
    expect(padded.paragraphs, ['  <!--image-->$first<!--image-->  ']);
    expect(padded.illustrations, [first]);
    final two = await ReaderContent.parse(
      '<!--image-->$first<!--image-->\n\n<!--image-->$second<!--image-->',
    );
    expect(two.paragraphs.length, 2);
    expect(two.illustrations, [first, second]);
  });

  test('an incomplete marker pair keeps its raw text', () async {
    for (final source in [
      '正文<!--image-->不是网址<!--image-->结尾',
      '正文<!--image-->结尾',
      '[插图]',
    ]) {
      final content = await ReaderContent.parse(source);
      expect(content.paragraphs, [source], reason: source);
      expect(content.illustrations, isEmpty, reason: source);
    }
  });

  test('a rich local body keeps its own paragraph coordinates', () async {
    final run =
        '<!--image-->$first<!--image-->   <!--image-->$second<!--image-->';
    final body = ReaderRichBody(
      [run],
      formats: const {0: ReaderRichParagraph(alignment: 'center')},
    ).encode();
    expect(body.contains('<!--reader-rich-v1:'), true);
    final content = await ReaderContent.parse(body);
    expect(content.paragraphs, [run]);
    expect(content.formats.keys, [0]);
    expect(content.illustrations, isEmpty);
  });
}
