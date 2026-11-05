import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hanabi/game/coop.dart';
import 'package:hanabi/game/game.dart';
import 'package:hanabi/net/link.dart';
import 'package:hanabi/net/online.dart';
import 'package:hanabi/net/signal_code.dart';

/// An offer as Chrome writes it for a data channel, after gathering.
const chromeOffer =
    'v=0\r\n'
    'o=- 4611731400430051336 2 IN IP4 127.0.0.1\r\n'
    's=-\r\n'
    't=0 0\r\n'
    'a=group:BUNDLE 0\r\n'
    'a=extmap-allow-mixed\r\n'
    'a=msid-semantic: WMS\r\n'
    'm=application 52123 UDP/DTLS/SCTP webrtc-datachannel\r\n'
    'c=IN IP4 81.40.1.2\r\n'
    'a=candidate:2999745851 1 udp 2122260223 '
    '1c2d3e4f-aaaa-bbbb-cccc-0123456789ab.local 50000 typ host '
    'generation 0 network-id 1\r\n'
    'a=candidate:1 1 tcp 1518280447 '
    '1c2d3e4f-aaaa-bbbb-cccc-0123456789ab.local 9 typ host tcptype active '
    'generation 0 network-id 1\r\n'
    'a=candidate:842163049 1 udp 1686052607 81.40.1.2 52123 typ srflx '
    'raddr 0.0.0.0 rport 0 generation 0 network-id 1\r\n'
    'a=ice-ufrag:Ab+1\r\n'
    'a=ice-pwd:k7Pq0Lr9/sT2uV4wX6yZ8aBcDe\r\n'
    'a=ice-options:trickle\r\n'
    'a=fingerprint:sha-256 '
    '0A:1B:2C:3D:4E:5F:60:71:82:93:A4:B5:C6:D7:E8:F9:'
    '0A:1B:2C:3D:4E:5F:60:71:82:93:A4:B5:C6:D7:E8:F9\r\n'
    'a=setup:actpass\r\n'
    'a=mid:0\r\n'
    'a=sctp-port:5000\r\n'
    'a=max-message-size:262144\r\n';

void main() {
  group('signal code', () {
    test('keeps what a data channel needs, in a few characters', () {
      final code = SignalCode.fromSdp(chromeOffer, offer: true)!;
      expect(code.text.length, lessThan(220));
      final back = SignalCode.parse(code.text)!;
      expect(back.offer, isTrue);
      final sdp = back.sdp;
      expect(sdp, contains('a=ice-ufrag:Ab+1\r\n'));
      expect(sdp, contains('a=ice-pwd:k7Pq0Lr9/sT2uV4wX6yZ8aBcDe\r\n'));
      expect(
        sdp,
        contains(
          'a=fingerprint:sha-256 0A:1B:2C:3D:4E:5F:60:71:82:93:A4:B5:C6:'
          'D7:E8:F9:0A:1B:2C:3D:4E:5F:60:71:82:93:A4:B5:C6:D7:E8:F9\r\n',
        ),
      );
      expect(sdp, contains('a=setup:actpass\r\n'));
      expect(sdp, contains('a=mid:0\r\n'));
      // The two UDP candidates, not the TCP one.
      expect(
        sdp,
        contains(
          'udp 2122260223 1c2d3e4f-aaaa-bbbb-cccc-0123456789ab.local 50000 '
          'typ host',
        ),
      );
      expect(sdp, contains('udp 1686052607 81.40.1.2 52123 typ srflx'));
      expect(sdp, isNot(contains('tcp')));
    });

    test('tells offers from answers and rejects anything else', () {
      final offer = SignalCode.fromSdp(chromeOffer, offer: true)!.text;
      final answer = SignalCode.fromSdp(chromeOffer, offer: false)!.text;
      expect(SignalCode.parse(offer)!.offer, isTrue);
      expect(SignalCode.parse(answer)!.offer, isFalse);
      expect(SignalCode.parse('https://example.com'), isNull);
      expect(SignalCode.parse('H1o,a,b,c,d,e,f'), isNull);
    });
  });

  test('moves and decks read back as written', () {
    for (final text in ['p3', 'p0B', 'd4', 'h2:5', 'h1:R', 'h3:*']) {
      expect(CoopMove.parse(text).text, text);
    }
    for (final bad in ['', 'p', 'x1', 'h2', 'h2:9', 'p1Z', 'd12']) {
      expect(() => CoopMove.parse(bad), throwsFormatException);
    }
    final deck = buildDeck(Random(3));
    expect(deckText(parseDeck(deckText(deck))), deckText(deck));
  });

  test('legal moves', () {
    final game = CoopGame(players: 3, random: Random(1));
    expect(game.isLegal(CoopDiscard(0)), isTrue);
    expect(game.isLegal(CoopDiscard(5)), isFalse);
    expect(game.isLegal(CoopHint(0, NumberHint(1))), isFalse);
    final card = game.hands[1].first;
    expect(game.isLegal(CoopHint(1, NumberHint(card.number))), isTrue);
    final absent = [1, 2, 3, 4, 5].firstWhere(
      (n) => game.hands[2].every((c) => c.number != n),
      orElse: () => 0,
    );
    if (absent > 0) {
      expect(game.isLegal(CoopHint(2, NumberHint(absent))), isFalse);
    }
  });

  test('a guest joins, the host starts and both play the same game', () async {
    final host = HostSession('Oriol')..players = 3;
    final (hostEnd, guestEnd) = LocalLink.pair();
    host.seat(1, hostEnd);
    final guest = GuestSession(guestEnd, 'Anna');
    await pumpEventQueue();
    expect(guest.seat, 1);
    expect(host.table.names, ['Oriol', 'Anna', 'Ren']);
    expect(host.table.bots, {2});
    expect(guest.table!.names, ['Oriol', 'Anna', 'Ren']);

    final deck = buildDeck(Random(7));
    final seating = host.start(deck);
    final hostGame = CoopGame(players: seating.players, deck: List.of(deck));
    await pumpEventQueue();
    final start = guest.game!;
    final guestGame = CoopGame(
      players: start.table.players,
      deck: List.of(start.deck),
    );

    // The host moves, then the guest; the host checks and relays it.
    final first = CoopDiscard(0);
    hostGame.apply(first);
    host.sendMove(0, first);
    final received = <GuestMove>[];
    host.moves.listen(received.add);
    await pumpEventQueue();
    guestGame.apply(guest.moves.single);
    final second = CoopHint(0, NumberHint(hostGame.hands[0].first.number));
    guest.sendMove(1, second);
    await pumpEventQueue();
    expect(received.single.seat, 1);
    expect(hostGame.isLegal(received.single.move), isTrue);
    hostGame.apply(received.single.move);
    host.sendMove(1, received.single.move);
    await pumpEventQueue();
    guestGame.apply(guest.moves.last);
    for (var p = 0; p < 3; p++) {
      expect(guestGame.hands[p].join(), hostGame.hands[p].join());
    }
    expect(guestGame.hints, hostGame.hints);

    // The guest leaves: a bot takes the seat.
    final left = <int>[];
    host.left.listen(left.add);
    guest.close();
    await pumpEventQueue();
    expect(left, [1]);
    expect(host.table.bots, {1, 2});
  });

  test('the host tells who plays first', () async {
    final host = HostSession('Oriol')..players = 3;
    final (hostEnd, guestEnd) = LocalLink.pair();
    host.seat(1, hostEnd);
    final guest = GuestSession(guestEnd, 'Anna');
    await pumpEventQueue();
    host.start(buildDeck(Random(2)), first: 2);
    await pumpEventQueue();
    expect(guest.game!.first, 2);
    final game = CoopGame(
      players: 3,
      deck: List.of(guest.game!.deck),
      first: guest.game!.first,
    );
    expect(game.current, 2);
    expect(game.hands.every((h) => h.length == 5), isTrue);
  });

  test('garbled messages change nothing', () async {
    final host = HostSession('Oriol');
    final (hostEnd, guestEnd) = LocalLink.pair();
    host.seat(1, hostEnd);
    final moves = <GuestMove>[];
    host.moves.listen(moves.add);
    guestEnd
      ..send('not json')
      ..send('{"t":"move","n":0,"m":"rm -rf"}')
      ..send('{"t":"hello"}');
    await pumpEventQueue();
    expect(moves, isEmpty);
    expect(host.table.names[1], '?');
  });
}
