import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const ExamPrepApp());

// ---------------------------------------------------------------- models

class Question {
  final String text;
  final List<String> options;
  final int answer;
  final String explanation;
  Question({
    required this.text,
    required this.options,
    required this.answer,
    required this.explanation,
  });
  factory Question.fromJson(Map<String, dynamic> j) => Question(
        text: j['q'] as String,
        options: List<String>.from(j['options'] as List),
        answer: j['answer'] as int,
        explanation: (j['explanation'] ?? '') as String,
      );
}

class Flashcard {
  final String front;
  final String back;
  Flashcard({required this.front, required this.back});
  factory Flashcard.fromJson(Map<String, dynamic> j) =>
      Flashcard(front: j['front'] as String, back: j['back'] as String);
}

class Subject {
  final String name;
  final String icon;
  final List<Question> questions;
  final List<Flashcard> flashcards;
  Subject({
    required this.name,
    required this.icon,
    required this.questions,
    required this.flashcards,
  });
  factory Subject.fromJson(Map<String, dynamic> j) => Subject(
        name: j['name'] as String,
        icon: (j['icon'] ?? '') as String,
        questions: (j['questions'] as List)
            .map((e) => Question.fromJson(e as Map<String, dynamic>))
            .toList(),
        flashcards: ((j['flashcards'] ?? []) as List)
            .map((e) => Flashcard.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
  IconData get iconData {
    switch (icon) {
      case 'public':
        return Icons.public;
      case 'calculate':
        return Icons.calculate;
      default:
        return Icons.menu_book;
    }
  }
}

Future<List<Subject>> loadSubjects() async {
  final raw = await rootBundle.loadString('assets/questions.json');
  final data = jsonDecode(raw) as Map<String, dynamic>;
  return (data['subjects'] as List)
      .map((e) => Subject.fromJson(e as Map<String, dynamic>))
      .toList();
}

// ---------------------------------------------------------------- storage

class QuizResult {
  final String subject;
  final int score;
  final int total;
  QuizResult(this.subject, this.score, this.total);
}

class Progress {
  final int streak;
  final List<QuizResult> history;
  Progress(this.streak, this.history);
}

class Store {
  static String _day(DateTime d) => '${d.year}-${d.month}-${d.day}';

  static Future<void> saveResult(String subject, int score, int total) async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList('history') ?? <String>[];
    list.add(jsonEncode({'s': subject, 'score': score, 'total': total}));
    await p.setStringList('history', list);

    final now = DateTime.now();
    final today = _day(now);
    final last = p.getString('lastDay');
    if (last != today) {
      final yesterday = _day(now.subtract(const Duration(days: 1)));
      final old = p.getInt('streak') ?? 0;
      await p.setInt('streak', last == yesterday ? old + 1 : 1);
      await p.setString('lastDay', today);
    }
  }

  static Future<Progress> load() async {
    final p = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final last = p.getString('lastDay');
    var streak = p.getInt('streak') ?? 0;
    if (last != _day(now) &&
        last != _day(now.subtract(const Duration(days: 1)))) {
      streak = 0;
    }
    final history = <QuizResult>[];
    for (final s in p.getStringList('history') ?? <String>[]) {
      final m = jsonDecode(s) as Map<String, dynamic>;
      history.add(QuizResult(
          m['s'] as String, (m['score'] as num).toInt(), (m['total'] as num).toInt()));
    }
    return Progress(streak, history);
  }
}

// ---------------------------------------------------------------- app

class ExamPrepApp extends StatelessWidget {
  const ExamPrepApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Exam Prep',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int tab = 0;
  late final Future<List<Subject>> subjects = loadSubjects();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Exam Prep')),
      body: FutureBuilder<List<Subject>>(
        future: subjects,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Could not load questions: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final s = snap.data!;
          if (tab == 0) return PracticeTab(subjects: s);
          if (tab == 1) return FlashcardsTab(subjects: s);
          return ProgressTab(subjects: s);
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.quiz), label: 'Practice'),
          NavigationDestination(icon: Icon(Icons.style), label: 'Flashcards'),
          NavigationDestination(icon: Icon(Icons.insights), label: 'Progress'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- practice

class PracticeTab extends StatelessWidget {
  final List<Subject> subjects;
  const PracticeTab({super.key, required this.subjects});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Choose a subject',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        for (final s in subjects)
          Card(
            child: ListTile(
              leading: Icon(s.iconData, size: 32),
              title: Text(s.name),
              subtitle: Text('${s.questions.length} questions - 30 sec each'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => QuizScreen(subject: s))),
            ),
          ),
      ],
    );
  }
}

class QuizScreen extends StatefulWidget {
  final Subject subject;
  const QuizScreen({super.key, required this.subject});
  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  static const int secondsPerQuestion = 30;
  late List<Question> qs;
  int idx = 0;
  int score = 0;
  int left = secondsPerQuestion;
  int? selected;
  bool answered = false;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    qs = List<Question>.of(widget.subject.questions)..shuffle();
    startTimer();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  void startTimer() {
    timer?.cancel();
    left = secondsPerQuestion;
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (left <= 1) {
        t.cancel();
        setState(() {
          left = 0;
          answered = true;
        });
      } else {
        setState(() => left--);
      }
    });
  }

  void choose(int i) {
    if (answered) return;
    timer?.cancel();
    setState(() {
      selected = i;
      answered = true;
      if (i == qs[idx].answer) score++;
    });
  }

  Future<void> next() async {
    if (idx + 1 >= qs.length) {
      await Store.saveResult(widget.subject.name, score, qs.length);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ResultScreen(
              subject: widget.subject, score: score, total: qs.length),
        ),
      );
      return;
    }
    setState(() {
      idx++;
      selected = null;
      answered = false;
    });
    startTimer();
  }

  @override
  Widget build(BuildContext context) {
    final q = qs[idx];
    return Scaffold(
      appBar: AppBar(title: Text(widget.subject.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          LinearProgressIndicator(value: (idx + 1) / qs.length),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Question ${idx + 1} of ${qs.length}'),
              Chip(
                avatar: const Icon(Icons.timer, size: 18),
                label: Text('${left}s'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(q.text,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          for (int i = 0; i < q.options.length; i++) optionTile(q, i),
          if (answered) ...[
            const SizedBox(height: 8),
            if (selected == null)
              const Text("Time's up!",
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            if (q.explanation.isNotEmpty) Text(q.explanation),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: next,
              child: Text(idx + 1 >= qs.length ? 'Finish' : 'Next'),
            ),
          ],
        ],
      ),
    );
  }

  Widget optionTile(Question q, int i) {
    Color? color;
    if (answered) {
      if (i == q.answer) {
        color = Colors.green.shade100;
      } else if (i == selected) {
        color = Colors.red.shade100;
      }
    }
    return Card(
      color: color,
      child: ListTile(
        title: Text(q.options[i]),
        onTap: () => choose(i),
      ),
    );
  }
}

class ResultScreen extends StatelessWidget {
  final Subject subject;
  final int score;
  final int total;
  const ResultScreen(
      {super.key,
      required this.subject,
      required this.score,
      required this.total});

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0 : (score * 100 / total).round();
    return Scaffold(
      appBar: AppBar(title: const Text('Result')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$score / $total',
                  style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold)),
              Text('$pct% in ${subject.name}', style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 8),
              Text(pct >= 80
                  ? 'Excellent work!'
                  : pct >= 60
                      ? 'Good, keep practising.'
                      : 'Needs more revision - try the flashcards.'),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => QuizScreen(subject: subject)),
                ),
                child: const Text('Try again'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Back to subjects'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- flashcards

class FlashcardsTab extends StatelessWidget {
  final List<Subject> subjects;
  const FlashcardsTab({super.key, required this.subjects});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Quick revision',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        for (final s in subjects)
          Card(
            child: ListTile(
              leading: Icon(s.iconData, size: 32),
              title: Text(s.name),
              subtitle: Text('${s.flashcards.length} cards'),
              trailing: const Icon(Icons.chevron_right),
              onTap: s.flashcards.isEmpty
                  ? null
                  : () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => FlashcardScreen(subject: s))),
            ),
          ),
      ],
    );
  }
}

class FlashcardScreen extends StatefulWidget {
  final Subject subject;
  const FlashcardScreen({super.key, required this.subject});
  @override
  State<FlashcardScreen> createState() => _FlashcardScreenState();
}

class _FlashcardScreenState extends State<FlashcardScreen> {
  int page = 0;

  @override
  Widget build(BuildContext context) {
    final cards = widget.subject.flashcards;
    return Scaffold(
      appBar: AppBar(title: Text(widget.subject.name)),
      body: Column(
        children: [
          const SizedBox(height: 16),
          Text('Card ${page + 1} of ${cards.length} - tap to flip, swipe for next'),
          Expanded(
            child: PageView.builder(
              itemCount: cards.length,
              onPageChanged: (i) => setState(() => page = i),
              itemBuilder: (_, i) => FlashCardView(card: cards[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class FlashCardView extends StatefulWidget {
  final Flashcard card;
  const FlashCardView({super.key, required this.card});
  @override
  State<FlashCardView> createState() => _FlashCardViewState();
}

class _FlashCardViewState extends State<FlashCardView> {
  bool showBack = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => showBack = !showBack),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          color: showBack
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surface,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                showBack ? widget.card.back : widget.card.front,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- progress

class ProgressTab extends StatefulWidget {
  final List<Subject> subjects;
  const ProgressTab({super.key, required this.subjects});
  @override
  State<ProgressTab> createState() => _ProgressTabState();
}

class _ProgressTabState extends State<ProgressTab> {
  late final Future<Progress> future = Store.load();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Progress>(
      future: future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final p = snap.data!;
        final totalScore = p.history.fold<int>(0, (a, h) => a + h.score);
        final totalQs = p.history.fold<int>(0, (a, h) => a + h.total);
        final overall = totalQs == 0 ? 0 : (totalScore * 100 / totalQs).round();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                statCard('Streak', '${p.streak} day(s)', Icons.local_fire_department),
                statCard('Quizzes', '${p.history.length}', Icons.check_circle),
                statCard('Accuracy', '$overall%', Icons.percent),
              ],
            ),
            const SizedBox(height: 16),
            const Text('By subject',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            for (final s in widget.subjects) subjectRow(s, p),
          ],
        );
      },
    );
  }

  Widget statCard(String label, String value, IconData icon) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Icon(icon),
              const SizedBox(height: 4),
              Text(value,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }

  Widget subjectRow(Subject s, Progress p) {
    final r = p.history.where((h) => h.subject == s.name);
    final sc = r.fold<int>(0, (a, h) => a + h.score);
    final tot = r.fold<int>(0, (a, h) => a + h.total);
    final acc = tot == 0 ? 0.0 : sc / tot;
    final weak = tot > 0 && acc < 0.6;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: acc),
            const SizedBox(height: 6),
            Text(tot == 0
                ? 'Not attempted yet'
                : '${(acc * 100).round()}% correct${weak ? ' - weak area, revise this' : ''}'),
          ],
        ),
      ),
    );
  }
}
