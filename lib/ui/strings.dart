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
  String get thinking;

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
  String get thinking => 'Thinking of the best hint…';
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
    HintMode.smart => 'Smart',
    HintMode.ai => 'AI',
    HintMode.search => 'Search',
  };
  @override
  String modeDescription(HintMode m) => switch (m) {
    HintMode.classic => 'The original rule: reveals what most cards share.',
    HintMode.smart => 'Tries every hint and picks the one that helps most.',
    HintMode.ai => 'A neural network trained on thousands of simulated games.',
    HintMode.search =>
      'Plays out every hint many times and gives the best one.',
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
  String get thinking => 'Pensant la millor pista…';
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
    HintMode.smart => 'Llest',
    HintMode.ai => 'IA',
    HintMode.search => 'Cerca',
  };
  @override
  String modeDescription(HintMode m) => switch (m) {
    HintMode.classic =>
      'La regla original: revela el que tenen en comú més cartes.',
    HintMode.smart => 'Prova totes les pistes i tria la que més ajuda.',
    HintMode.ai =>
      'Una xarxa neuronal entrenada amb milers de partides simulades.',
    HintMode.search => 'Juga cada pista moltes vegades i et dona la millor.',
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
  String get thinking => 'Pensando la mejor pista…';
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
    HintMode.smart => 'Listo',
    HintMode.ai => 'IA',
    HintMode.search => 'Busca',
  };
  @override
  String modeDescription(HintMode m) => switch (m) {
    HintMode.classic =>
      'La regla original: revela lo que comparten más cartas.',
    HintMode.smart => 'Prueba todas las pistas y elige la que más ayuda.',
    HintMode.ai =>
      'Una red neuronal entrenada con miles de partidas simuladas.',
    HintMode.search => 'Juega cada pista muchas veces y te da la mejor.',
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
