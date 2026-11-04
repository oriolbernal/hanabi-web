import 'dart:ui';

import '../game/card.dart';
import '../game/game.dart';
import 'hint_mode.dart';
import 'settings.dart';

enum Language {
  ca('Català'),
  es('Español'),
  en('English');

  const Language(this.label);
  final String label;

  Strings get strings => switch (this) {
    Language.ca => const _Catalan(),
    Language.es => const _Spanish(),
    Language.en => const _English(),
  };

  /// The device language when it is one we have, else English.
  static Language get system =>
      switch (PlatformDispatcher.instance.locale.languageCode) {
        'ca' => Language.ca,
        'es' => Language.es,
        _ => Language.en,
      };
}

/// Texts in the language chosen on the home screen.
Strings get tr => Settings.language.value.strings;

abstract class Strings {
  const Strings();

  // Home.
  String get subtitle;
  String get hintsHeader;
  String get play;
  String get howToPlay;
  String homeStats(Stats s);
  String get devMode;
  String get devModeDetail;
  String modeLabel(HintMode m);
  String modeDescription(HintMode m);

  /// Dev mode: copies the log of the person's moves to the clipboard.
  String get copyLog;
  String logCopied(int moves);

  // Game.
  String colorName(CardColor c);

  /// Plural adjective, as in "these cards are red".
  String colorsName(CardColor c);
  String hintsSubtitle(String mode);
  String get hideAdvice;
  String get showAdvice;
  String get newGame;
  String get fireworks;
  String get discards;
  String get yourHand;
  String get discard;
  String get hint;
  String get tapCard;
  String get ai;
  String misfire(GameCard c);
  String discarded(GameCard c);
  String get allKnown;
  String numberHint(int n);
  String colorHint(CardColor c);
  String get chooseJokerPile;
  String get perfectShow;
  String get newRecord;
  String get showOver;
  String yourScore(int score);
  String endStats(Stats s);
  String get menu;
  String get playAgain;
  String get hintsStat;
  String get livesStat;
  String get deckStat;
  String get scoreStat;
  String get maxStat;
  String get wild;
  String get noDiscards;

  // Cooperative game. A null name means the person ("you").
  String get gameHeader;
  String get solo;
  String get coop;
  String get coopSubtitle;
  String get playersHeader;
  String coopDescription(int players);
  String get you;
  String get yourTurn;
  String botThinking(String name);
  String get tapCardCoop;
  String get noHintTokens;
  String cardName(GameCard c) => '${c.number} ${colorName(c.color)}';
  String playedBy(String? name, GameCard c, {required bool fits});
  String discardedBy(String? name, GameCard c);
  String hintedBy(String? giver, String? receiver, Hint hint);
  String teamScore(int score);

  // Online games, on several phones.
  String get offline;
  String get online;
  String get onlineDescription;
  String get yourName;
  String get createRoom;
  String get joinRoom;
  String get room;
  String get seatBot;
  String get seatFriend;
  String get invite;
  String get waitingAnswer;
  String get inviteHelp;
  String get scanAnswer;
  String get scanCode;
  String get pasteCode;
  String get copyCode;
  String get codeCopied;
  String get startGame;
  String get startHelp;
  String get joinHelp;
  String get answerHelp;
  String get connecting;
  String get waitingHost;
  String get hostLeft;
  String guestLeft(String name);
  String get notACode;
  String get connectionFailed;
  String get pointCamera;
  String get cancel;
  String get ok;
  String get keepAwake;
  String get hostDealsAgain;
  String get stay;

  // Advisor.
  String advicePlay(int card, String chance);
  String adviceDiscard(int card, String points);
  String get adviceHint;

  // Tutorial: title and text of each step.
  List<(String, String)> get tutorial;
  String get gotIt;
  String get next;

  /// A decimal with the local separator.
  String decimal(double x, [int digits = 1]) => x.toStringAsFixed(digits);
}

class _English extends Strings {
  const _English();

  @override
  String get copyLog => 'Copy move log';
  @override
  String logCopied(int moves) => 'Copied: $moves games';
  @override
  String get subtitle => 'solitaire';
  @override
  String get hintsHeader => 'HINTS';
  @override
  String get play => 'Play';
  @override
  String get howToPlay => 'How to play';
  @override
  String homeStats(Stats s) =>
      'Best ${s.best} · average ${decimal(s.average)} · last 10 '
      '${decimal(s.recent())} · ${s.played} ${s.played == 1 ? 'game' : 'games'}';
  @override
  String get devMode => 'Dev mode';
  @override
  String get devModeDetail => 'AI advisor and odds in game';
  @override
  String modeLabel(HintMode m) => switch (m) {
    HintMode.classic => 'Classic',
    HintMode.ai => 'AI',
  };
  @override
  String modeDescription(HintMode m) => switch (m) {
    HintMode.classic => 'The original rule: reveals what most cards share.',
    HintMode.ai =>
      'A neural network that learned from the search over thousands of games.',
  };

  @override
  String colorName(CardColor c) => switch (c) {
    CardColor.red => 'red',
    CardColor.green => 'green',
    CardColor.blue => 'blue',
    CardColor.yellow => 'yellow',
    CardColor.white => 'white',
    CardColor.joker => 'joker',
  };
  @override
  String colorsName(CardColor c) => colorName(c);
  @override
  String hintsSubtitle(String mode) => '$mode hints';
  @override
  String get hideAdvice => 'Hide advice';
  @override
  String get showAdvice => 'Show advice';
  @override
  String get newGame => 'New game';
  @override
  String get fireworks => 'FIREWORKS';
  @override
  String get discards => 'DISCARDS';
  @override
  String get yourHand => 'YOUR HAND';
  @override
  String get discard => 'Discard';
  @override
  String get hint => 'Hint';
  @override
  String get tapCard => 'Tap a card to select it';
  @override
  String get ai => 'AI';
  @override
  String misfire(GameCard c) =>
      'Misfire! That card was a ${c.number} ${colorName(c.color)}.';
  @override
  String discarded(GameCard c) =>
      'Discarded a ${c.number} ${colorName(c.color)}.';
  @override
  String get allKnown =>
      'You already know all your cards. Play or discard them.';
  @override
  String numberHint(int n) => 'Hint: these are your ${n}s.';
  @override
  String colorHint(CardColor c) => c == CardColor.joker
      ? 'Hint: these are your jokers.'
      : 'Hint: these are your ${colorName(c)} cards.';
  @override
  String get chooseJokerPile => "It's a joker! Choose where to play it";
  @override
  String get perfectShow => 'Perfect show! 🎆';
  @override
  String get newRecord => 'New record! 🎉';
  @override
  String get showOver => 'The show is over';
  @override
  String yourScore(int score) => 'Your score is $score / 25';
  @override
  String endStats(Stats s) =>
      'Best ${s.best} · average ${decimal(s.average)} over ${s.played} '
      '${s.played == 1 ? 'game' : 'games'}';
  @override
  String get menu => 'Menu';
  @override
  String get playAgain => 'Play again';
  @override
  String get hintsStat => 'hints';
  @override
  String get livesStat => 'lives';
  @override
  String get deckStat => 'deck';
  @override
  String get scoreStat => 'score';
  @override
  String get maxStat => 'max';
  @override
  String get wild => 'wild';
  @override
  String get noDiscards => 'Nothing discarded yet';

  @override
  String get gameHeader => 'GAME';
  @override
  String get solo => 'Solitaire';
  @override
  String get coop => 'Co-op';
  @override
  String get coopSubtitle => 'together';
  @override
  String get playersHeader => 'PLAYERS';
  @override
  String coopDescription(int players) {
    final bots = players - 1;
    return 'You and $bots ${bots == 1 ? 'bot' : 'bots'}. You see their cards, '
        'not yours: you give them hints and they give you hints.';
  }

  @override
  String get you => 'You';
  @override
  String get yourTurn => 'Your turn';
  @override
  String botThinking(String name) => '$name is thinking…';
  @override
  String get tapCardCoop =>
      "Tap one of your cards to play or discard it, or a partner's card "
      'to give them a hint';
  @override
  String get noHintTokens => 'No hint tokens left: discard to win one back';
  @override
  String playedBy(String? name, GameCard c, {required bool fits}) => fits
      ? '${name ?? 'You'} played a ${cardName(c)}.'
      : 'Misfire! ${name ?? 'You'} played a ${cardName(c)}.';
  @override
  String discardedBy(String? name, GameCard c) =>
      '${name ?? 'You'} discarded a ${cardName(c)}.';
  @override
  String hintedBy(String? giver, String? receiver, Hint hint) {
    final what = switch (hint) {
      NumberHint(:final number) => '${number}s',
      ColorHint(color: CardColor.joker) => 'jokers',
      ColorHint(:final color) => colorName(color),
    };
    return '${giver ?? 'You'} ${giver == null ? 'tell' : 'tells'} '
        '${receiver ?? 'you'} which cards are $what.';
  }

  @override
  String teamScore(int score) => 'The team scored $score / 25';

  @override
  String get offline => 'Offline';
  @override
  String get online => 'Online';
  @override
  String get onlineDescription =>
      'Play with friends, each on their own phone. You connect by scanning '
      'QR codes, with no server in between.';
  @override
  String get yourName => 'Your name';
  @override
  String get createRoom => 'Create a room';
  @override
  String get joinRoom => 'Join a room';
  @override
  String get room => 'Room';
  @override
  String get seatBot => 'Bot';
  @override
  String get seatFriend => 'Friend';
  @override
  String get invite => 'Invite';
  @override
  String get waitingAnswer => 'Waiting for their code';
  @override
  String get inviteHelp =>
      'Your friend taps "Join a room" and scans this code. Then scan the '
      'code their phone shows.';
  @override
  String get scanAnswer => "Scan your friend's code";
  @override
  String get scanCode => "Scan the host's code";
  @override
  String get pasteCode => 'Paste a code';
  @override
  String get copyCode => 'Copy code';
  @override
  String get codeCopied => 'Code copied: send it if you are not together';
  @override
  String get startGame => 'Start';
  @override
  String get startHelp => 'Bots play the seats with nobody connected.';
  @override
  String get joinHelp => "Scan the code on the host's phone.";
  @override
  String get answerHelp => 'Now the host scans this code.';
  @override
  String get connecting => 'Connecting…';
  @override
  String get waitingHost => 'Waiting for the host to start the game…';
  @override
  String get hostLeft => 'The host left the room.';
  @override
  String guestLeft(String name) => '$name left; a bot takes their seat.';
  @override
  String get notACode => 'That is not a Hanabi code.';
  @override
  String get connectionFailed => 'Could not connect. Try again.';
  @override
  String get pointCamera => 'Point the camera at the QR code';
  @override
  String get cancel => 'Cancel';
  @override
  String get ok => 'OK';
  @override
  String get keepAwake =>
      'Keep the screen on: a locked phone may drop out of the game.';
  @override
  String get hostDealsAgain => 'The host can start another game.';
  @override
  String get stay => 'Stay';

  @override
  String advicePlay(int card, String chance) =>
      'Play card $card · $chance it fits';
  @override
  String adviceDiscard(int card, String points) =>
      'Discard card $card · costs $points pts';
  @override
  String get adviceHint => 'Ask for a hint';

  @override
  List<(String, String)> get tutorial => [
    (
      'The goal',
      'Each card has a NUMBER and a COLOR. Build one firework per color by '
          'stacking its cards in order, from 1 to 5. A perfect show scores 25.',
    ),
    (
      'Your hand',
      'You hold $handSize cards, but you cannot see them. '
          'Tap a card to select it, then play or discard it.',
    ),
    (
      'Hints',
      'Ask for a hint to reveal all your cards sharing a number or a color. '
          'You have $maxHints hint tokens; discarding a card gives one back.',
    ),
    (
      'What hints rule out',
      'A hint also tells you about the cards it does not touch. After "these '
          'are your 1s", the others show the numbers they can still be; after '
          '"these are green", the dots show the colors still possible.',
    ),
    (
      'Misfires',
      'Playing a card that does not fit costs a life. '
          'Lose $allowedErrors lives and the show is over. '
          'The game also ends when the deck and your hand run out.',
    ),
    (
      'Jokers',
      'There are five rainbow jokers, numbered 1 to 5. A joker can go on any '
          'firework. A joker 1 takes the first free spot, marked "wild", and '
          'steps aside if a real 1 needs it. For higher jokers you choose the '
          'firework. Keep them for where they are needed: each joker can '
          'replace one lost card.',
    ),
    (
      'Max score',
      'The flag in the top bar shows the best score still reachable. It drops '
          'when every copy of a card you needed is gone, so discard carefully: '
          'losing one 5 costs nothing while the joker 5 can replace it, a '
          'second one costs a point.',
    ),
  ];
  @override
  String get gotIt => 'Got it!';
  @override
  String get next => 'Next';
}

class _Catalan extends Strings {
  const _Catalan();

  @override
  String decimal(double x, [int digits = 1]) =>
      x.toStringAsFixed(digits).replaceAll('.', ',');

  @override
  String get copyLog => 'Copia el registre de jugades';
  @override
  String logCopied(int moves) => 'Copiat: $moves partides';
  @override
  String get subtitle => 'solitari';
  @override
  String get hintsHeader => 'PISTES';
  @override
  String get play => 'Jugar';
  @override
  String get howToPlay => 'Com es juga';
  @override
  String homeStats(Stats s) =>
      'Millor ${s.best} · mitjana ${decimal(s.average)} · últimes 10 '
      '${decimal(s.recent())} · ${s.played} '
      '${s.played == 1 ? 'partida' : 'partides'}';
  @override
  String get devMode => 'Mode dev';
  @override
  String get devModeDetail => 'Assistent IA i probabilitats a la partida';
  @override
  String modeLabel(HintMode m) => switch (m) {
    HintMode.classic => 'Clàssic',
    HintMode.ai => 'IA',
  };
  @override
  String modeDescription(HintMode m) => switch (m) {
    HintMode.classic =>
      'La regla original: revela el que tenen en comú més cartes.',
    HintMode.ai =>
      'Una xarxa neuronal que ha après de la cerca en milers de partides.',
  };

  @override
  String colorName(CardColor c) => switch (c) {
    CardColor.red => 'vermell',
    CardColor.green => 'verd',
    CardColor.blue => 'blau',
    CardColor.yellow => 'groc',
    CardColor.white => 'blanc',
    CardColor.joker => 'comodí',
  };
  @override
  String colorsName(CardColor c) => switch (c) {
    CardColor.red => 'vermelles',
    CardColor.green => 'verdes',
    CardColor.blue => 'blaves',
    CardColor.yellow => 'grogues',
    CardColor.white => 'blanques',
    CardColor.joker => 'comodins',
  };
  @override
  String hintsSubtitle(String mode) => 'Pistes: $mode';
  @override
  String get hideAdvice => 'Amaga el consell';
  @override
  String get showAdvice => 'Mostra el consell';
  @override
  String get newGame => 'Partida nova';
  @override
  String get fireworks => 'FOCS';
  @override
  String get discards => 'DESCARTADES';
  @override
  String get yourHand => 'LA TEVA MÀ';
  @override
  String get discard => 'Descartar';
  @override
  String get hint => 'Pista';
  @override
  String get tapCard => 'Toca una carta per seleccionar-la';
  @override
  String get ai => 'IA';
  @override
  String misfire(GameCard c) =>
      'Error! Aquesta carta era un ${c.number} ${colorName(c.color)}.';
  @override
  String discarded(GameCard c) =>
      'Has descartat un ${c.number} ${colorName(c.color)}.';
  @override
  String get allKnown =>
      'Ja coneixes totes les teves cartes. Juga-les o descarta-les.';
  @override
  String numberHint(int n) => 'Pista: aquestes cartes són $n.';
  @override
  String colorHint(CardColor c) =>
      'Pista: aquestes cartes són ${colorsName(c)}.';
  @override
  String get chooseJokerPile => 'És un comodí! Tria on jugar-lo';
  @override
  String get perfectShow => 'Espectacle perfecte! 🎆';
  @override
  String get newRecord => 'Nou rècord! 🎉';
  @override
  String get showOver => "S'ha acabat l'espectacle";
  @override
  String yourScore(int score) => 'Has fet $score punts de 25';
  @override
  String endStats(Stats s) =>
      'Millor ${s.best} · mitjana ${decimal(s.average)} en ${s.played} '
      '${s.played == 1 ? 'partida' : 'partides'}';
  @override
  String get menu => 'Menú';
  @override
  String get playAgain => 'Torna a jugar';
  @override
  String get hintsStat => 'pistes';
  @override
  String get livesStat => 'vides';
  @override
  String get deckStat => 'munt';
  @override
  String get scoreStat => 'punts';
  @override
  String get maxStat => 'màx';
  @override
  String get wild => 'lliure';
  @override
  String get noDiscards => 'Encara no has descartat res';

  @override
  String get gameHeader => 'JOC';
  @override
  String get solo => 'Solitari';
  @override
  String get coop => 'Cooperatiu';
  @override
  String get coopSubtitle => 'en equip';
  @override
  String get playersHeader => 'JUGADORS';
  @override
  String coopDescription(int players) {
    final bots = players - 1;
    return 'Tu i $bots ${bots == 1 ? 'bot' : 'bots'}. Veus les seves cartes '
        "però no les teves: tu els dones pistes i ells te'n donen a tu.";
  }

  @override
  String get you => 'Tu';
  @override
  String get yourTurn => 'Et toca';
  @override
  String botThinking(String name) => '$name pensa…';
  @override
  String get tapCardCoop =>
      'Toca una carta teva per jugar-la o descartar-la, o una carta '
      "d'un company per donar-li una pista";
  @override
  String get noHintTokens =>
      "No queden pistes: descarta una carta per recuperar-ne una";
  @override
  String playedBy(String? name, GameCard c, {required bool fits}) => fits
      ? (name == null
            ? 'Has jugat un ${cardName(c)}.'
            : '$name ha jugat un ${cardName(c)}.')
      : (name == null
            ? 'Error! Has jugat un ${cardName(c)}.'
            : 'Error! $name ha jugat un ${cardName(c)}.');
  @override
  String discardedBy(String? name, GameCard c) => name == null
      ? 'Has descartat un ${cardName(c)}.'
      : '$name ha descartat un ${cardName(c)}.';
  @override
  String hintedBy(String? giver, String? receiver, Hint hint) {
    final what = switch (hint) {
      NumberHint(:final number) => '$number',
      ColorHint(:final color) => colorsName(color),
    };
    if (giver == null) return 'Has dit a $receiver quines cartes són $what.';
    if (receiver == null) return '$giver et diu quines cartes són $what.';
    return '$giver diu a $receiver quines cartes són $what.';
  }

  @override
  String teamScore(int score) => "L'equip ha fet $score punts de 25";

  @override
  String get offline => 'Fora de línia';
  @override
  String get online => 'En línia';
  @override
  String get onlineDescription =>
      'Juga amb amics, cadascú amb el seu mòbil. Us connecteu escanejant '
      'codis QR, sense cap servidor pel mig.';
  @override
  String get yourName => 'El teu nom';
  @override
  String get createRoom => 'Crear una sala';
  @override
  String get joinRoom => 'Unir-me a una sala';
  @override
  String get room => 'Sala';
  @override
  String get seatBot => 'Bot';
  @override
  String get seatFriend => 'Amic';
  @override
  String get invite => 'Convidar';
  @override
  String get waitingAnswer => 'Esperant el seu codi';
  @override
  String get inviteHelp =>
      "El teu amic toca «Unir-me a una sala» i escaneja aquest codi. Després "
      'escaneja el codi que li surti al mòbil.';
  @override
  String get scanAnswer => 'Escanejar el codi del teu amic';
  @override
  String get scanCode => "Escanejar el codi de l'amfitrió";
  @override
  String get pasteCode => 'Enganxar un codi';
  @override
  String get copyCode => 'Copiar el codi';
  @override
  String get codeCopied => "Codi copiat: envia'l si no sou junts";
  @override
  String get startGame => 'Començar';
  @override
  String get startHelp => 'Les cadires sense ningú connectat les juguen bots.';
  @override
  String get joinHelp => "Escaneja el codi del mòbil de l'amfitrió.";
  @override
  String get answerHelp => "Ara l'amfitrió escaneja aquest codi.";
  @override
  String get connecting => 'Connectant…';
  @override
  String get waitingHost => "Esperant que l'amfitrió comenci la partida…";
  @override
  String get hostLeft => "L'amfitrió ha tancat la sala.";
  @override
  String guestLeft(String name) =>
      "$name ha marxat; ara juga un bot al seu lloc.";
  @override
  String get notACode => 'Aquest no és un codi de Hanabi.';
  @override
  String get connectionFailed => "No s'ha pogut connectar. Torna-ho a provar.";
  @override
  String get pointCamera => 'Apunta la càmera al codi QR';
  @override
  String get cancel => 'Cancel·lar';
  @override
  String get ok => "D'acord";
  @override
  String get keepAwake =>
      'Mantén la pantalla encesa: si el mòbil es bloqueja, pots sortir de la '
      'partida.';
  @override
  String get hostDealsAgain => "L'amfitrió pot començar una altra partida.";
  @override
  String get stay => 'Quedar-me';

  @override
  String advicePlay(int card, String chance) =>
      'Juga la carta $card · $chance que encaixi';
  @override
  String adviceDiscard(int card, String points) =>
      'Descarta la carta $card · costa $points punts';
  @override
  String get adviceHint => 'Demana una pista';

  @override
  List<(String, String)> get tutorial => [
    (
      "L'objectiu",
      'Cada carta té un NÚMERO i un COLOR. Fes un castell de focs per a cada '
          "color apilant-ne les cartes en ordre, de l'1 al 5. Un espectacle "
          'perfecte fa 25 punts.',
    ),
    (
      'La teva mà',
      'Tens $handSize cartes, però no les veus. '
          'Toca una carta per seleccionar-la i després juga-la o descarta-la.',
    ),
    (
      'Pistes',
      'Demana una pista per descobrir totes les cartes que comparteixen un '
          'número o un color. Tens $maxHints pistes; descartar una carta en '
          'recupera una.',
    ),
    (
      'El que descarten les pistes',
      'Una pista també et diu coses de les cartes que no toca. Després de '
          '"aquestes cartes són 1", les altres mostren els números que encara '
          'poden ser; després de "aquestes són verdes", els punts mostren els '
          'colors encara possibles.',
    ),
    (
      'Errors',
      'Jugar una carta que no encaixa et costa una vida. '
          'Si en perds $allowedErrors, s\'acaba l\'espectacle. '
          'La partida també acaba quan es buiden el munt i la mà.',
    ),
    (
      'Comodins',
      "Hi ha cinc comodins de l'arc de Sant Martí, de l'1 al 5. Un comodí pot "
          "anar a qualsevol foc. Un comodí 1 ocupa el primer lloc lliure, "
          'marcat amb "lliure", i s\'aparta si un 1 de veritat el necessita. '
          'Per als comodins més alts tries tu el foc. Guarda\'ls per on facin '
          'falta: cada comodí pot substituir una carta perduda.',
    ),
    (
      'Puntuació màxima',
      'La bandera de la barra de dalt mostra la millor puntuació que encara '
          'pots assolir. Baixa quan han desaparegut totes les còpies d\'una '
          'carta que necessitaves; descarta amb compte: perdre un 5 no costa '
          'res mentre el comodí 5 el pugui substituir, però el segon costa un '
          'punt.',
    ),
  ];
  @override
  String get gotIt => 'Entesos!';
  @override
  String get next => 'Següent';
}

class _Spanish extends Strings {
  const _Spanish();

  @override
  String decimal(double x, [int digits = 1]) =>
      x.toStringAsFixed(digits).replaceAll('.', ',');

  @override
  String get copyLog => 'Copiar el registro de jugadas';
  @override
  String logCopied(int moves) => 'Copiado: $moves partidas';
  @override
  String get subtitle => 'solitario';
  @override
  String get hintsHeader => 'PISTAS';
  @override
  String get play => 'Jugar';
  @override
  String get howToPlay => 'Cómo se juega';
  @override
  String homeStats(Stats s) =>
      'Mejor ${s.best} · media ${decimal(s.average)} · últimas 10 '
      '${decimal(s.recent())} · ${s.played} '
      '${s.played == 1 ? 'partida' : 'partidas'}';
  @override
  String get devMode => 'Modo dev';
  @override
  String get devModeDetail => 'Asistente IA y probabilidades en la partida';
  @override
  String modeLabel(HintMode m) => switch (m) {
    HintMode.classic => 'Clásico',
    HintMode.ai => 'IA',
  };
  @override
  String modeDescription(HintMode m) => switch (m) {
    HintMode.classic =>
      'La regla original: revela lo que comparten más cartas.',
    HintMode.ai =>
      'Una red neuronal que ha aprendido de la búsqueda en miles de partidas.',
  };

  @override
  String colorName(CardColor c) => switch (c) {
    CardColor.red => 'rojo',
    CardColor.green => 'verde',
    CardColor.blue => 'azul',
    CardColor.yellow => 'amarillo',
    CardColor.white => 'blanco',
    CardColor.joker => 'comodín',
  };
  @override
  String colorsName(CardColor c) => switch (c) {
    CardColor.red => 'rojas',
    CardColor.green => 'verdes',
    CardColor.blue => 'azules',
    CardColor.yellow => 'amarillas',
    CardColor.white => 'blancas',
    CardColor.joker => 'comodines',
  };
  @override
  String hintsSubtitle(String mode) => 'Pistas: $mode';
  @override
  String get hideAdvice => 'Ocultar consejo';
  @override
  String get showAdvice => 'Mostrar consejo';
  @override
  String get newGame => 'Nueva partida';
  @override
  String get fireworks => 'FUEGOS';
  @override
  String get discards => 'DESCARTES';
  @override
  String get yourHand => 'TU MANO';
  @override
  String get discard => 'Descartar';
  @override
  String get hint => 'Pista';
  @override
  String get tapCard => 'Toca una carta para seleccionarla';
  @override
  String get ai => 'IA';
  @override
  String misfire(GameCard c) =>
      '¡Fallo! Esa carta era un ${c.number} ${colorName(c.color)}.';
  @override
  String discarded(GameCard c) =>
      'Has descartado un ${c.number} ${colorName(c.color)}.';
  @override
  String get allKnown => 'Ya conoces todas tus cartas. Juégalas o descártalas.';
  @override
  String numberHint(int n) => 'Pista: estas cartas son $n.';
  @override
  String colorHint(CardColor c) => 'Pista: estas cartas son ${colorsName(c)}.';
  @override
  String get chooseJokerPile => '¡Es un comodín! Elige dónde jugarlo';
  @override
  String get perfectShow => '¡Espectáculo perfecto! 🎆';
  @override
  String get newRecord => '¡Nuevo récord! 🎉';
  @override
  String get showOver => 'Se acabó el espectáculo';
  @override
  String yourScore(int score) => 'Has hecho $score puntos de 25';
  @override
  String endStats(Stats s) =>
      'Mejor ${s.best} · media ${decimal(s.average)} en ${s.played} '
      '${s.played == 1 ? 'partida' : 'partidas'}';
  @override
  String get menu => 'Menú';
  @override
  String get playAgain => 'Jugar otra vez';
  @override
  String get hintsStat => 'pistas';
  @override
  String get livesStat => 'vidas';
  @override
  String get deckStat => 'mazo';
  @override
  String get scoreStat => 'puntos';
  @override
  String get maxStat => 'máx';
  @override
  String get wild => 'libre';
  @override
  String get noDiscards => 'Aún no has descartado nada';

  @override
  String get gameHeader => 'JUEGO';
  @override
  String get solo => 'Solitario';
  @override
  String get coop => 'Cooperativo';
  @override
  String get coopSubtitle => 'en equipo';
  @override
  String get playersHeader => 'JUGADORES';
  @override
  String coopDescription(int players) {
    final bots = players - 1;
    return 'Tú y $bots ${bots == 1 ? 'bot' : 'bots'}. Ves sus cartas pero no '
        'las tuyas: tú les das pistas y ellos te las dan a ti.';
  }

  @override
  String get you => 'Tú';
  @override
  String get yourTurn => 'Te toca';
  @override
  String botThinking(String name) => '$name piensa…';
  @override
  String get tapCardCoop =>
      'Toca una carta tuya para jugarla o descartarla, o una carta de un '
      'compañero para darle una pista';
  @override
  String get noHintTokens =>
      'No quedan pistas: descarta una carta para recuperar una';
  @override
  String playedBy(String? name, GameCard c, {required bool fits}) => fits
      ? (name == null
            ? 'Has jugado un ${cardName(c)}.'
            : '$name ha jugado un ${cardName(c)}.')
      : (name == null
            ? '¡Fallo! Has jugado un ${cardName(c)}.'
            : '¡Fallo! $name ha jugado un ${cardName(c)}.');
  @override
  String discardedBy(String? name, GameCard c) => name == null
      ? 'Has descartado un ${cardName(c)}.'
      : '$name ha descartado un ${cardName(c)}.';
  @override
  String hintedBy(String? giver, String? receiver, Hint hint) {
    final what = switch (hint) {
      NumberHint(:final number) => '$number',
      ColorHint(:final color) => colorsName(color),
    };
    if (giver == null) return 'Le has dicho a $receiver qué cartas son $what.';
    if (receiver == null) return '$giver te dice qué cartas son $what.';
    return '$giver le dice a $receiver qué cartas son $what.';
  }

  @override
  String teamScore(int score) => 'El equipo ha hecho $score puntos de 25';

  @override
  String get offline => 'Sin conexión';
  @override
  String get online => 'En línea';
  @override
  String get onlineDescription =>
      'Juega con amigos, cada uno con su móvil. Os conectáis escaneando '
      'códigos QR, sin ningún servidor de por medio.';
  @override
  String get yourName => 'Tu nombre';
  @override
  String get createRoom => 'Crear una sala';
  @override
  String get joinRoom => 'Unirme a una sala';
  @override
  String get room => 'Sala';
  @override
  String get seatBot => 'Bot';
  @override
  String get seatFriend => 'Amigo';
  @override
  String get invite => 'Invitar';
  @override
  String get waitingAnswer => 'Esperando su código';
  @override
  String get inviteHelp =>
      'Tu amigo toca «Unirme a una sala» y escanea este código. Después '
      'escanea el código que le salga en el móvil.';
  @override
  String get scanAnswer => 'Escanear el código de tu amigo';
  @override
  String get scanCode => 'Escanear el código del anfitrión';
  @override
  String get pasteCode => 'Pegar un código';
  @override
  String get copyCode => 'Copiar el código';
  @override
  String get codeCopied => 'Código copiado: envíalo si no estáis juntos';
  @override
  String get startGame => 'Empezar';
  @override
  String get startHelp => 'Las sillas sin nadie conectado las juegan bots.';
  @override
  String get joinHelp => 'Escanea el código del móvil del anfitrión.';
  @override
  String get answerHelp => 'Ahora el anfitrión escanea este código.';
  @override
  String get connecting => 'Conectando…';
  @override
  String get waitingHost => 'Esperando a que el anfitrión empiece la partida…';
  @override
  String get hostLeft => 'El anfitrión ha cerrado la sala.';
  @override
  String guestLeft(String name) =>
      '$name se ha ido; ahora juega un bot en su lugar.';
  @override
  String get notACode => 'Esto no es un código de Hanabi.';
  @override
  String get connectionFailed => 'No se ha podido conectar. Vuelve a probar.';
  @override
  String get pointCamera => 'Apunta la cámara al código QR';
  @override
  String get cancel => 'Cancelar';
  @override
  String get ok => 'Vale';
  @override
  String get keepAwake =>
      'Mantén la pantalla encendida: si el móvil se bloquea, puedes salir de '
      'la partida.';
  @override
  String get hostDealsAgain => 'El anfitrión puede empezar otra partida.';
  @override
  String get stay => 'Quedarme';

  @override
  String advicePlay(int card, String chance) =>
      'Juega la carta $card · $chance de que encaje';
  @override
  String adviceDiscard(int card, String points) =>
      'Descarta la carta $card · cuesta $points puntos';
  @override
  String get adviceHint => 'Pide una pista';

  @override
  List<(String, String)> get tutorial => [
    (
      'El objetivo',
      'Cada carta tiene un NÚMERO y un COLOR. Monta un castillo de fuegos por '
          'cada color apilando sus cartas en orden, del 1 al 5. Un espectáculo '
          'perfecto suma 25 puntos.',
    ),
    (
      'Tu mano',
      'Tienes $handSize cartas, pero no las ves. '
          'Toca una carta para seleccionarla y luego juégala o descártala.',
    ),
    (
      'Pistas',
      'Pide una pista para descubrir todas las cartas que comparten un número '
          'o un color. Tienes $maxHints pistas; descartar una carta te devuelve '
          'una.',
    ),
    (
      'Lo que descartan las pistas',
      'Una pista también te dice cosas de las cartas que no toca. Tras "estas '
          'cartas son 1", las demás muestran los números que aún pueden ser; '
          'tras "estas son verdes", los puntos muestran los colores aún '
          'posibles.',
    ),
    (
      'Fallos',
      'Jugar una carta que no encaja te cuesta una vida. '
          'Si pierdes $allowedErrors, se acaba el espectáculo. '
          'La partida también termina cuando se vacían el mazo y la mano.',
    ),
    (
      'Comodines',
      'Hay cinco comodines arcoíris, del 1 al 5. Un comodín puede ir en '
          'cualquier fuego. Un comodín 1 ocupa el primer hueco libre, marcado '
          'con "libre", y se aparta si un 1 de verdad lo necesita. Para los '
          'comodines más altos eliges tú el fuego. Guárdalos para donde hagan '
          'falta: cada comodín puede sustituir una carta perdida.',
    ),
    (
      'Puntuación máxima',
      'La bandera de la barra superior muestra la mejor puntuación que aún '
          'puedes alcanzar. Baja cuando han desaparecido todas las copias de '
          'una carta que necesitabas; descarta con cuidado: perder un 5 no '
          'cuesta nada mientras el comodín 5 pueda sustituirlo, pero el '
          'segundo cuesta un punto.',
    ),
  ];
  @override
  String get gotIt => '¡Entendido!';
  @override
  String get next => 'Siguiente';
}
