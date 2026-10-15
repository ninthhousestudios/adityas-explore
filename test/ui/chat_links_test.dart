import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import 'package:explore/ui/chat_links.dart';
import 'package:explore/ui/message_markdown.dart';

void main() {
  group('linkChatNames', () {
    test('links being types, singular and plural', () {
      expect(
        linkChatNames('An Aditya leads the Rishis and Nagas.'),
        'An [Aditya](being-type:aditya) leads the '
        '[Rishis](being-type:rishi) and [Nagas](being-type:naga).',
      );
    });

    test('links planets', () {
      expect(
        linkChatNames('Sun, Moon and Ketu; Rahu\'s pull.'),
        '[Sun](planet:sun), [Moon](planet:moon) and [Ketu](planet:ketu); '
        "[Rahu](planet:rahu)'s pull.",
      );
    });

    test('lowercase type and planet words stay plain', () {
      const text = 'the sun, a rishi, two nagas, mercury.';
      expect(linkChatNames(text), text);
    });

    test('links a plain mention', () {
      expect(
        linkChatNames('Meet Takshaka today.'),
        'Meet [Takshaka](being:mitra-naga) today.',
      );
    });

    test('links every mention, Aditya and companion alike', () {
      expect(
        linkChatNames('Varuna and Huhu; Huhu again.'),
        '[Varuna](being:varuna-aditya) and [Huhu](being:varuna-gandharva); '
        '[Huhu](being:varuna-gandharva) again.',
      );
    });

    test('links through punctuation and possessives', () {
      expect(
        linkChatNames("Takshaka's gift, (Menaka)."),
        "[Takshaka](being:mitra-naga)'s gift, ([Menaka](being:mitra-apsara)).",
      );
    });

    test('ignores lowercase and in-word occurrences', () {
      const text = 'haha, vata dosha, Vatas, Indrani, Mitras.';
      expect(linkChatNames(text), text);
    });

    test('longest name wins over a shorter name inside it', () {
      // "Vishvamitra" contains "Mitra"; it must link as one name.
      expect(
        linkChatNames('Vishvamitra.'),
        '[Vishvamitra](being:vishnu-rishi).',
      );
    });

    test('links inside bold and headings', () {
      expect(
        linkChatNames('# Indra\n**Rambha**'),
        '# [Indra](being:indra-aditya)\n**[Rambha](being:vishnu-apsara)**',
      );
    });

    test('leaves existing links, inline code and fences alone', () {
      const text =
          'See [Indra here](https://x.test/Indra) and `Indra` and '
          '<https://x.test/Bhaga> and https://x.test/Mitra\n'
          '```\nIndra\n```\n';
      expect(linkChatNames(text), text);
    });

    test('still links text around a protected region', () {
      expect(
        linkChatNames('`code` Bhaga `more`'),
        '`code` [Bhaga](being:bhaga-aditya) `more`',
      );
    });

    test('an unterminated fence protects to the end', () {
      const text = 'Bhaga\n```\nIndra';
      expect(linkChatNames(text), '[Bhaga](being:bhaga-aditya)\n```\nIndra');
    });

    group('Vishvavasu co-mention', () {
      test('only Indra mentioned → sign 5', () {
        expect(
          linkChatNames('Vishvavasu serves Indra.'),
          '[Vishvavasu](being:indra-gandharva) serves '
          '[Indra](being:indra-aditya).',
        );
      });

      test('only Parjanya mentioned → sign 12', () {
        expect(
          linkChatNames('Parjanya brings Vishvavasu.'),
          contains('[Vishvavasu](being:parjanya-gandharva)'),
        );
      });

      test('both mentioned → ambiguous marker', () {
        expect(
          linkChatNames('Vishvavasu, Indra, Parjanya.'),
          contains('[Vishvavasu](being:vishvavasu)'),
        );
      });

      test('neither mentioned → ambiguous marker', () {
        expect(
          linkChatNames('Vishvavasu sings.'),
          '[Vishvavasu](being:vishvavasu) sings.',
        );
      });
    });
  });

  group('parseChatLink', () {
    test('decodes each scheme', () {
      expect(
        (parseChatLink('being:mitra-naga') as BeingLink?)?.slug,
        'mitra-naga',
      );
      expect(
        (parseChatLink('being-type:rishi') as BeingTypeLink?)?.type,
        'rishi',
      );
      expect((parseChatLink('planet:venus') as PlanetLink?)?.body, 'venus');
    });

    test('rejects unknown types, bodies and other URLs', () {
      expect(parseChatLink('being-type:deva'), isNull);
      expect(parseChatLink('planet:pluto'), isNull);
      expect(parseChatLink('https://84beings.com'), isNull);
    });
  });

  group('resolveBeingLink', () {
    test('concrete slug resolves directly', () {
      final b = resolveBeingLink('mitra-naga', (_) => false);
      expect((b?.sign, b?.type), (3, 'naga'));
    });

    test('unknown slug is null', () {
      expect(resolveBeingLink('nobody-naga', (_) => true), isNull);
    });

    (int?, String?) vishvavasu(Set<int> placedSigns) {
      final b = resolveBeingLink(
        vishvavasuMarker,
        (b) => placedSigns.contains(b.sign),
      );
      return (b?.sign, b?.type);
    }

    test('chart places only sign 5 → Indra', () {
      expect(vishvavasu({5}), (5, 'gandharva'));
    });

    test('chart places only sign 12 → Parjanya', () {
      expect(vishvavasu({12}), (12, 'gandharva'));
    });

    test('chart places both → Indra fallback', () {
      expect(vishvavasu({5, 12}), (5, 'gandharva'));
    });

    test('chart places neither → Indra fallback', () {
      expect(vishvavasu({}), (5, 'gandharva'));
    });
  });

  group('MessageMarkdown being links', () {
    Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));
    const style = TextStyle(fontSize: 14, color: Colors.white);

    testWidgets('tapping a linked name reports its slug', (tester) async {
      final tapped = <ChatLink>[];
      await tester.pumpWidget(
        host(
          MessageMarkdown(
            'Ask Takshaka.',
            style: style,
            linkColor: Colors.amber,
            onChatLinkTap: tapped.add,
          ),
        ),
      );
      expect(find.byType(GptMarkdown), findsOneWidget);
      await tester.tap(
        find.textContaining('Takshaka', findRichText: true).last,
      );
      expect((tapped.single as BeingLink).slug, 'mitra-naga');
    });
  });
}
