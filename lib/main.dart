import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _native = MethodChannel('impression_day/native');
const _black = Color(0xFF101114);
const _panel = Color(0xFF1B1D22);
const _white = Color(0xFFF9FAFC);
const _blue = Color(0xFF3478F6);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ImpressionDayApp());
}

class ImpressionDayApp extends StatelessWidget {
  const ImpressionDayApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '하루의 인상',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: _blue),
      scaffoldBackgroundColor: _white,
      fontFamily: '.AppleSystemUIFont',
    ),
    home: const HomePage(),
  );
}

class DayEvent {
  DayEvent({
    required this.id,
    required this.title,
    required this.date,
    this.endDate,
  });
  final String id;
  String title;
  DateTime date;
  DateTime? endDate;

  factory DayEvent.fromJson(Map<String, dynamic> json) => DayEvent(
    id: json['id'] as String,
    title: json['title'] as String,
    date: DateTime.parse(json['date'] as String),
    endDate: json['endDate'] == null
        ? null
        : DateTime.parse(json['endDate'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'date': date.toIso8601String(),
    'endDate': endDate?.toIso8601String(),
  };

  int _daysBetween(DateTime a, DateTime b) => DateTime.utc(
    b.year,
    b.month,
    b.day,
  ).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

  int get days => _daysBetween(DateTime.now(), date);

  String statusOn(DateTime today) {
    final untilStart = _daysBetween(today, date);
    if (untilStart > 0) return 'D-$untilStart';
    if (endDate == null) return untilStart == 0 ? 'D-DAY' : 'D+${-untilStart}';
    final untilEnd = _daysBetween(today, endDate!);
    if (untilEnd < 0) return 'D+${-untilEnd}';
    if (untilStart == 0) return 'D-DAY';
    return '진행 ${-untilStart + 1}일차';
  }

  String get dDay => statusOn(DateTime.now());
}

class Quote {
  const Quote(
    this.artist,
    this.searchName,
    this.creatorName,
    this.text,
    this.source,
  );
  final String artist;
  final String searchName;
  final String creatorName;
  final String text;
  final String source;
}

const _quotes = [
  Quote(
    '클로드 모네',
    'Claude Monet',
    'Monet',
    '함께 작업하다 보면 배울 것이 많고, 자연은 더욱 아름다워 보인다.',
    'https://www.nga.gov/sites/default/files/migrate_images/content/dam/ngaweb/research/publications/pdfs/impressionists-at-argenteuil.pdf',
  ),
  Quote(
    '카미유 피사로',
    'Camille Pissarro',
    'Pissarro',
    '그림과 예술은 나를 매혹한다. 그것은 내 삶이다.',
    'https://cdn.kunstmuseumbasel.ch/website/kmb-saalblatt-pissarro-e_1f4043d7.pdf',
  ),
  Quote(
    '에두아르 마네',
    'Edouard Manet',
    'Manet',
    '자신이 사는 시대에 속해, 눈앞에 보이는 것을 그려야 한다.',
    'https://resources.metmuseum.org/resources/metpublications/pdf/Impressionists_in_the_Metropolitan_The_Metropolitan_Museum_of_Art_Bulletin_v_27_no_1_Summer_1968.pdf',
  ),
  Quote(
    '오귀스트 르누아르',
    'Pierre-Auguste Renoir',
    'Renoir',
    '그 속을 산책하고 싶어지는 그림이 좋다.',
    'https://www.musee-orsay.fr/en/whats-on/exhibitions/presentation/renoir-renoir',
  ),
  Quote(
    '폴 세잔',
    'Paul Cezanne',
    'Cézanne',
    '자연을 원기둥, 구, 원뿔로 바라보라.',
    'https://gallerycollections.courtauld.ac.uk/object-ms-1932-sc-1-1',
  ),
];

class Artwork {
  const Artwork({
    required this.id,
    required this.title,
    required this.artist,
    required this.imageUrl,
    required this.pageUrl,
    required this.credit,
  });
  final int id;
  final String title;
  final String artist;
  final String imageUrl;
  final String pageUrl;
  final String credit;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final _title = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  DateTime? _selectedEndDate;
  final List<DayEvent> _events = [];
  Artwork? _art;
  Uint8List? _image;
  String? _artError;
  String? _dataDir;
  String? _lastShownDay;
  bool _launchAtLogin = false;
  bool _notificationsAllowed = false;
  Timer? _clock;
  int _dayIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _native.setMethodCallHandler((call) async {
      if (call.method == 'becameActive') await _showOnceToday();
    });
    _start();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      final index = _ordinal(now);
      if (index != _dayIndex) {
        setState(() => _dayIndex = index);
        _loadArt();
      }
      if (now.hour == 8 && now.minute < 2) _showOnceToday();
      setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    _title.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _showOnceToday();
  }

  int _ordinal(DateTime d) => DateTime.utc(
    d.year,
    d.month,
    d.day,
  ).difference(DateTime.utc(1970)).inDays;
  String _stamp(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _dateLabel(DateTime d) => '${d.year}.${d.month}.${d.day}';
  String _rangeLabel(DayEvent event) {
    final end = event.endDate;
    if (end == null) return _dateLabel(event.date);
    final endLabel = end.year == event.date.year
        ? '${end.month}.${end.day}'
        : _dateLabel(end);
    return '${_dateLabel(event.date)} – $endLabel';
  }

  Future<void> _start() async {
    _dayIndex = _ordinal(DateTime.now());
    try {
      _dataDir = await _native.invokeMethod<String>('dataDirectory');
      if (_dataDir != null) {
        final file = File('$_dataDir/state.json');
        if (await file.exists()) {
          final data =
              jsonDecode(await file.readAsString()) as Map<String, dynamic>;
          _events.addAll(
            (data['events'] as List<dynamic>? ?? []).map(
              (e) => DayEvent.fromJson(e as Map<String, dynamic>),
            ),
          );
          _lastShownDay = data['lastShownDay'] as String?;
        }
      }
      _launchAtLogin =
          await _native.invokeMethod<bool>('getLaunchAtLogin') ?? false;
      _notificationsAllowed =
          await _native.invokeMethod<bool>('notificationAllowed') ?? false;
      if (mounted) setState(() {});
      await _showOnceToday();
    } catch (e) {
      _message('설정을 불러오지 못했습니다: $e');
    }
    await _loadArt();
  }

  Future<void> _persist() async {
    if (_dataDir == null) return;
    final file = File('$_dataDir/state.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'events': _events.map((e) => e.toJson()).toList(),
        'lastShownDay': _lastShownDay,
      }),
      flush: true,
    );
  }

  Future<void> _showOnceToday() async {
    final today = _stamp(DateTime.now());
    if (_lastShownDay == today) return;
    _lastShownDay = today;
    await _persist();
    await _native.invokeMethod('showWindow');
  }

  Future<void> _loadArt() async {
    final quote = _quotes[_dayIndex % _quotes.length];
    final artist = quote.searchName;
    final query = Uri.https(
      'openaccess-api.clevelandart.org',
      '/api/artworks/',
      {
        'q': artist,
        'cc0': '',
        'has_image': '1',
        'type': 'Painting',
        'limit': '30',
      },
    );
    try {
      final search =
          jsonDecode(utf8.decode(await _get(query))) as Map<String, dynamic>;
      final choices = (search['data'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where(
            (item) =>
                item['share_license_status'] == 'CC0' &&
                (item['images'] as Map<String, dynamic>?)?['web']?['url']
                    is String &&
                (item['creators'] as List<dynamic>? ?? []).any(
                  (creator) =>
                      ((creator as Map<String, dynamic>)['description']
                                  as String? ??
                              '')
                          .toLowerCase()
                          .contains(quote.creatorName.toLowerCase()),
                ),
          )
          .toList();
      if (choices.isEmpty) throw const FormatException('공개 도메인 작품을 찾지 못했습니다.');
      final item = choices[_dayIndex % choices.length];
      final creators = (item['creators'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final art = Artwork(
        id: item['id'] as int,
        title: item['title'] as String,
        artist: creators.first['description'] as String,
        imageUrl:
            ((item['images'] as Map<String, dynamic>)['web']
                    as Map<String, dynamic>)['url']
                as String,
        pageUrl: item['url'] as String,
        credit: 'Cleveland Museum of Art',
      );
      final bytes = await _get(Uri.parse(art.imageUrl));
      if (!mounted) return;
      setState(() {
        _art = art;
        _image = bytes;
        _artError = null;
      });
      if (_dataDir != null) {
        await File('$_dataDir/art.jpg').writeAsBytes(bytes, flush: true);
        await File('$_dataDir/art.json').writeAsString(
          jsonEncode({
            'id': art.id,
            'title': art.title,
            'artist': art.artist,
            'imageUrl': art.imageUrl,
            'pageUrl': art.pageUrl,
            'credit': art.credit,
            'day': _stamp(DateTime.now()),
          }),
        );
      }
    } catch (e) {
      if (_dataDir != null) {
        try {
          final file = File('$_dataDir/art.json');
          if (await file.exists()) {
            final info =
                jsonDecode(await file.readAsString()) as Map<String, dynamic>;
            final bytes = await File('$_dataDir/art.jpg').readAsBytes();
            if (mounted) {
              setState(() {
                _art = Artwork(
                  id: info['id'] as int,
                  title: info['title'] as String,
                  artist: info['artist'] as String,
                  imageUrl: info['imageUrl'] as String,
                  pageUrl: info['pageUrl'] as String,
                  credit: info['credit'] as String,
                );
                _image = bytes;
                _artError = null;
              });
            }
            return;
          }
        } catch (_) {}
      }
      if (mounted) {
        setState(() => _artError = '그림을 불러오지 못했습니다. 인터넷 연결을 확인해 주세요.');
      }
    }
  }

  Future<Uint8List> _get(Uri uri) async {
    final client = HttpClient();
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 12));
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 20))) {
        bytes.addAll(chunk);
      }
      return Uint8List.fromList(bytes);
    } finally {
      client.close();
    }
  }

  Future<void> _saveArt() async {
    if (_art == null || _image == null) return;
    try {
      await _native.invokeMethod('saveImage', {
        'bytes': _image,
        'name': '${_art!.artist} - ${_art!.title}.jpg',
      });
    } catch (e) {
      _message('그림을 저장하지 못했습니다: $e');
    }
  }

  Future<void> _openUrl(String url) async {
    try {
      await _native.invokeMethod('openUrl', url);
    } catch (e) {
      _message('페이지를 열지 못했습니다: $e');
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _pickDate({bool end = false}) async {
    final date = await showDatePicker(
      context: context,
      initialDate: end ? (_selectedEndDate ?? _selectedDate) : _selectedDate,
      firstDate: end ? _selectedDate : DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (date != null) {
      setState(() {
        if (end) {
          _selectedEndDate = date;
        } else {
          _selectedDate = date;
          if (_selectedEndDate != null && _selectedEndDate!.isBefore(date)) {
            _selectedEndDate = date;
          }
        }
      });
    }
  }

  Future<void> _addEvent() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    setState(() {
      _events.add(
        DayEvent(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          title: title,
          date: _selectedDate,
          endDate: _selectedEndDate,
        ),
      );
      _title.clear();
      _selectedEndDate = null;
    });
    await _persist();
  }

  Future<void> _editEvent(DayEvent event) async {
    final controller = TextEditingController(text: event.title);
    DateTime editDate = event.date;
    DateTime? editEndDate = event.endDate;
    final result = await showDialog<(String, DateTime, DateTime?)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('일정 수정'),
          content: SizedBox(
            width: 330,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '일정 이름'),
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    const SizedBox(width: 35, child: Text('시작')),
                    OutlinedButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: editDate,
                          firstDate: DateTime(1900),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setDialogState(() {
                            editDate = picked;
                            if (editEndDate != null &&
                                editEndDate!.isBefore(picked)) {
                              editEndDate = picked;
                            }
                          });
                        }
                      },
                      child: Text(_dateLabel(editDate)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const SizedBox(width: 35, child: Text('종료')),
                    OutlinedButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: editEndDate ?? editDate,
                          firstDate: editDate,
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setDialogState(() => editEndDate = picked);
                        }
                      },
                      child: Text(
                        editEndDate == null
                            ? '종료일 선택'
                            : _dateLabel(editEndDate!),
                      ),
                    ),
                    if (editEndDate != null)
                      IconButton(
                        tooltip: '종료일 지우기',
                        onPressed: () =>
                            setDialogState(() => editEndDate = null),
                        icon: const Icon(Icons.close, size: 17),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, (
                controller.text.trim(),
                editDate,
                editEndDate,
              )),
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null || result.$1.isEmpty) return;
    setState(() {
      event.title = result.$1;
      event.date = result.$2;
      event.endDate = result.$3;
    });
    await _persist();
  }

  Future<void> _settings() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('설정'),
          content: SizedBox(
            width: 410,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mac 로그인 시 자동 실행'),
                  value: _launchAtLogin,
                  onChanged: (value) async {
                    try {
                      final result =
                          await _native.invokeMethod<bool>(
                            'setLaunchAtLogin',
                            value,
                          ) ??
                          false;
                      setDialogState(() => _launchAtLogin = result);
                      setState(() {});
                      if (result != value) _message('로그인 항목 설정을 확인해 주세요.');
                    } catch (e) {
                      _message('설정을 바꾸지 못했습니다: $e');
                    }
                  },
                ),
                const SizedBox(height: 12),
                const Text(
                  '매일 오전 8시 알림',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 5),
                const Text(
                  '알림을 허용하면 오전 8시에 알려줍니다. Mac을 그날 처음 사용할 때 앱 창이 한 번 표시됩니다.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 9),
                OutlinedButton(
                  onPressed: _notificationsAllowed
                      ? null
                      : () async {
                          final allowed =
                              await _native.invokeMethod<bool>(
                                'requestNotifications',
                              ) ??
                              false;
                          setDialogState(() => _notificationsAllowed = allowed);
                          setState(() {});
                        },
                  child: Text(_notificationsAllowed ? '알림 허용됨' : '알림 권한 요청'),
                ),
                const Divider(height: 32),
                const Text(
                  '그림: 클리블랜드 미술관 CC0 소장품. 처음 불러올 때 인터넷 연결이 필요합니다.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('닫기'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final quote = _quotes[_dayIndex % _quotes.length];
    final sorted = [..._events]..sort((a, b) => a.date.compareTo(b.date));
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final sideWidth = (constraints.maxWidth * .36).clamp(360.0, 470.0);
          return Row(
            children: [
              SizedBox(
                width: sideWidth,
                child: Container(
                  color: _black,
                  child: Theme(
                    data: ThemeData.dark().copyWith(
                      colorScheme: const ColorScheme.dark(
                        primary: _blue,
                        surface: _panel,
                      ),
                      scaffoldBackgroundColor: _black,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(30),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: const BoxDecoration(
                                  color: _blue,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                '하루의 인상',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.5,
                                  color: _white,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                tooltip: '설정',
                                onPressed: _settings,
                                icon: const Icon(
                                  Icons.settings_outlined,
                                  color: _white,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 42),
                          Text(
                            '${now.year}. ${now.month.toString().padLeft(2, '0')}. ${now.day.toString().padLeft(2, '0')}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: _blue,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.4,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            '오늘, 이 순간',
                            style: TextStyle(
                              fontSize: 29,
                              color: _white,
                              fontWeight: FontWeight.w300,
                              letterSpacing: -1.1,
                            ),
                          ),
                          const SizedBox(height: 36),
                          Row(
                            children: [
                              const Text(
                                '일정',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: _white,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${sorted.length}',
                                style: const TextStyle(color: Colors.white54),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: sorted.isEmpty
                                ? Align(
                                    alignment: Alignment.topCenter,
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(18),
                                      decoration: _cardDecoration(),
                                      child: const Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            '아직 등록한 일정이 없습니다.',
                                            style: TextStyle(color: _white),
                                          ),
                                          SizedBox(height: 5),
                                          Text(
                                            '아래에서 첫 일정을 추가해 보세요.',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.white54,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: sorted.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(height: 9),
                                    itemBuilder: (context, i) {
                                      final event = sorted[i];
                                      return Container(
                                        padding: const EdgeInsets.all(15),
                                        decoration: _cardDecoration(),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    event.title,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: _white,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 5),
                                                  Text(
                                                    _rangeLabel(event),
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.white54,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Text(
                                              event.dDay,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                                color: _blue,
                                              ),
                                            ),
                                            PopupMenuButton<String>(
                                              tooltip: '일정 메뉴',
                                              onSelected: (action) async {
                                                if (action == 'edit') {
                                                  await _editEvent(event);
                                                }
                                                if (action == 'delete') {
                                                  setState(
                                                    () => _events.remove(event),
                                                  );
                                                  await _persist();
                                                }
                                              },
                                              itemBuilder: (_) => const [
                                                PopupMenuItem(
                                                  value: 'edit',
                                                  child: Text('수정'),
                                                ),
                                                PopupMenuItem(
                                                  value: 'delete',
                                                  child: Text('삭제'),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                          ),
                          const SizedBox(height: 15),
                          Container(
                            padding: const EdgeInsets.all(17),
                            decoration: _cardDecoration(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '새 일정',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: _white,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _title,
                                  onSubmitted: (_) => _addEvent(),
                                  style: const TextStyle(color: _white),
                                  decoration: const InputDecoration(
                                    hintText: '예: 여행',
                                    isDense: true,
                                    hintStyle: TextStyle(color: Colors.white38),
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 13),
                                Row(
                                  children: [
                                    const SizedBox(
                                      width: 36,
                                      child: Text(
                                        '시작',
                                        style: TextStyle(
                                          color: Colors.white54,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    OutlinedButton(
                                      onPressed: () => _pickDate(),
                                      child: Text(_dateLabel(_selectedDate)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                Row(
                                  children: [
                                    const SizedBox(
                                      width: 36,
                                      child: Text(
                                        '종료',
                                        style: TextStyle(
                                          color: Colors.white54,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    OutlinedButton(
                                      onPressed: () => _pickDate(end: true),
                                      child: Text(
                                        _selectedEndDate == null
                                            ? '선택 안 함'
                                            : _dateLabel(_selectedEndDate!),
                                      ),
                                    ),
                                    if (_selectedEndDate != null)
                                      IconButton(
                                        tooltip: '종료일 지우기',
                                        onPressed: () => setState(
                                          () => _selectedEndDate = null,
                                        ),
                                        icon: const Icon(Icons.close, size: 16),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton(
                                    onPressed: _addEvent,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: _blue,
                                      foregroundColor: _white,
                                    ),
                                    child: const Text('일정 추가'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  color: _white,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                          child: Container(
                            color: const Color(0xFFE9EBEE),
                            child: _image == null
                                ? Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.palette_outlined,
                                          size: 48,
                                          color: Colors.black38,
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          _artError ?? '오늘의 그림을 불러오는 중입니다…',
                                          style: const TextStyle(
                                            color: Colors.black54,
                                          ),
                                        ),
                                        if (_artError != null)
                                          TextButton(
                                            onPressed: _loadArt,
                                            child: const Text('다시 시도'),
                                          ),
                                      ],
                                    ),
                                  )
                                : Image.memory(_image!, fit: BoxFit.cover),
                          ),
                        ),
                      ),
                      Container(
                        color: _white,
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'TODAY’S PAINTING',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2,
                                color: _blue,
                              ),
                            ),
                            const SizedBox(height: 7),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _art?.title ?? '인상주의 컬렉션',
                                    maxLines: 2,
                                    style: const TextStyle(
                                      fontSize: 23,
                                      fontWeight: FontWeight.w300,
                                      letterSpacing: -0.7,
                                      color: _black,
                                    ),
                                  ),
                                ),
                                if (_art != null) ...[
                                  IconButton(
                                    tooltip: '작품 정보',
                                    onPressed: () => _openUrl(_art!.pageUrl),
                                    icon: const Icon(Icons.open_in_new),
                                  ),
                                  IconButton(
                                    tooltip: '그림 저장',
                                    onPressed: _saveArt,
                                    icon: const Icon(Icons.download_outlined),
                                  ),
                                ],
                              ],
                            ),
                            Text(
                              _art?.artist ?? 'Cleveland Museum of Art',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                            const Divider(height: 30),
                            Text(
                              '“${quote.text}”',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w300,
                                color: _black,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Text(
                                  '— ${quote.artist}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                TextButton(
                                  onPressed: () => _openUrl(quote.source),
                                  child: const Text('출처'),
                                ),
                                const Spacer(),
                                const Text(
                                  '그림: 클리블랜드 미술관 · CC0',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.black45,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  BoxDecoration _cardDecoration() => BoxDecoration(
    color: _panel,
    border: Border.all(color: Colors.white.withValues(alpha: .10)),
    borderRadius: BorderRadius.circular(8),
  );
}
