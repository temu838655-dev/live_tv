import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart'
    show YoutubePlayerController, YoutubePlayerParams, YoutubePlayerScaffold;

const _base = 'https://iptv-org.github.io/iptv';
const _sections = <(String, String)>[
  ('Việt Nam', '$_base/countries/vn.m3u'),
  ('Tin tức quốc tế', '$_base/categories/news.m3u'),
  ('Phim ảnh', '$_base/categories/movies.m3u'),
  ('Giải trí', '$_base/categories/entertainment.m3u'),
  ('Thiếu nhi', '$_base/categories/kids.m3u'),
  ('Âm nhạc', '$_base/categories/music.m3u'),
];

// Kênh trả phí: không đưa vào danh sách (sửa tại đây nếu cần).
const _block = [
  'k+', 'kplus', 'bein', 'sky sport', 'espn', 'dazn', 'fox sport',
  'supersport', 'premier sport', 'tnt sport', 'eleven', 'canal+',
  'movistar', 'arena sport', 'setanta', 'viaplay', 'sportsnet',
  'nbc sport', 'cbs sport', 'bt sport', 'now sport', 'optus', 'astro ',
];
const _domKeys = [
  'thể thao', 'the thao', 'sport', 'bóng đá', 'bong da', 'vtv6', 'vtv3',
];
const _fbKeys = [
  'football', 'soccer', 'fútbol', 'futbol', 'futebol', 'calcio', 'fussball',
  'fußball', 'bóng đá', 'goal', 'liga', 'champions', 'uefa', 'fifa',
];
const _clubKeys = [
  'real madrid', 'barça', 'barca', 'benfica', 'sporting', 'manchester',
  'mutv', 'liverpool', 'chelsea', 'arsenal', 'juventus', 'milan', 'bayern',
  'psg', 'ajax', 'celtic', 'rangers',
];

const _bg = Color(0xFF0E0F14);
const _card = Color(0xFF1A1C24);
const _accent = Color(0xFFFF4D5E);

class Channel {
  final String name, url, logo;
  const Channel(this.name, this.url, this.logo);
  Map<String, String> toJson() => {'n': name, 'u': url, 'l': logo};
  factory Channel.fromJson(Map<String, dynamic> j) =>
      Channel(j['n'], j['u'], j['l']);
}

List<Channel> parseM3u(String text) {
  final out = <Channel>[];
  final seen = <String>{};
  String? name, logo;
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.startsWith('#EXTINF')) {
      logo = RegExp(r'tvg-logo="([^"]*)"').firstMatch(line)?.group(1) ?? '';
      final raw0 = line.substring(line.lastIndexOf(',') + 1).trim();
      final clean =
          raw0.replaceAll(RegExp(r'\s*[\(\[][^\)\]]*[\)\]]'), '').trim();
      name = clean.isEmpty ? raw0 : clean;
    } else if (line.startsWith('http') && name != null) {
      if (name.isNotEmpty && seen.add(name)) {
        out.add(Channel(name, line, logo ?? ''));
      }
      name = null;
    }
  }
  return out;
}

Map<String, List<Channel>> classify(Map<String, String> m) {
  bool has(String n, List<String> k) {
    final s = n.toLowerCase();
    return k.any(s.contains);
  }

  final dom = <Channel>[], intl = <Channel>[], club = <Channel>[];
  for (final c in parseM3u(m['vn']!)) {
    if (!has(c.name, _block) && has(c.name, _domKeys)) dom.add(c);
  }
  for (final c in parseM3u(m['sp']!)) {
    if (has(c.name, _block)) continue;
    if (has(c.name, _clubKeys)) {
      club.add(c);
    } else if (has(c.name, _fbKeys)) {
      intl.add(c);
    }
  }
  return {'dom': dom, 'intl': intl, 'club': club};
}

class Store extends ChangeNotifier {
  final rows = <String, List<Channel>>{};
  final fb = <String, List<Channel>>{'dom': [], 'intl': [], 'club': []};
  List<Channel> get fbAll => [...fb['dom']!, ...fb['intl']!, ...fb['club']!];
  final favs = <Channel>[];
  SharedPreferences? _p;

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    for (final e in _p!.getStringList('favs') ?? <String>[]) {
      favs.add(Channel.fromJson(jsonDecode(e)));
    }
    for (final s in _sections) {
      final c = _p!.getString('c_${s.$2}');
      if (c != null) {
        rows[s.$1] = (jsonDecode(c) as List)
            .map((e) => Channel.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    }
    final f = _p!.getString('fb');
    if (f != null) {
      (jsonDecode(f) as Map<String, dynamic>).forEach((k, v) {
        fb[k] = (v as List)
            .map((e) => Channel.fromJson(e as Map<String, dynamic>))
            .toList();
      });
    }
    notifyListeners();
    await refresh();
  }

  Future<void> refresh() =>
      Future.wait([..._sections.map(_fetch), _fetchFb()]);

  Future<void> _fetchFb() async {
    try {
      final r = await Future.wait([
        http.get(Uri.parse('$_base/countries/vn.m3u')),
        http.get(Uri.parse('$_base/categories/sports.m3u')),
      ]).timeout(const Duration(seconds: 30));
      if (r.any((e) => e.statusCode != 200)) return;
      final m = await compute(classify, {
        'vn': utf8.decode(r[0].bodyBytes, allowMalformed: true),
        'sp': utf8.decode(r[1].bodyBytes, allowMalformed: true),
      });
      for (final k in m.keys) {
        fb[k] = m[k]!.take(100).toList();
      }
      await _p?.setString(
          'fb',
          jsonEncode({
            for (final e in fb.entries)
              e.key: e.value.map((c) => c.toJson()).toList()
          }));
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _fetch((String, String) s) async {
    try {
      final r =
          await http.get(Uri.parse(s.$2)).timeout(const Duration(seconds: 25));
      if (r.statusCode != 200) return;
      final all = await compute(
          parseM3u, utf8.decode(r.bodyBytes, allowMalformed: true));
      final list = all.take(80).toList();
      if (list.isEmpty) return;
      rows[s.$1] = list;
      await _p?.setString(
          'c_${s.$2}', jsonEncode(list.map((e) => e.toJson()).toList()));
      notifyListeners();
    } catch (_) {}
  }

  bool isFav(Channel c) => favs.any((e) => e.url == c.url);

  void toggleFav(Channel c) {
    if (isFav(c)) {
      favs.removeWhere((e) => e.url == c.url);
    } else {
      favs.add(c);
    }
    _p?.setStringList('favs', favs.map((e) => jsonEncode(e.toJson())).toList());
    notifyListeners();
  }
}

final store = Store();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MaterialApp(
    title: 'Truyền hình',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _bg,
      colorScheme: const ColorScheme.dark(primary: _accent, surface: _bg),
    ),
    locale: const Locale('vi'),
    supportedLocales: const [Locale('vi')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: const Shell(),
  ));
  store.init();
}

void play(BuildContext c, Channel ch, List<Channel> list) {
  final i = list.indexWhere((e) => e.url == ch.url);
  Navigator.push(c,
      MaterialPageRoute(builder: (_) => PlayerPage(list, i < 0 ? 0 : i)));
}

Widget _logo(String url, {double size = 36}) => url.isEmpty
    ? Icon(Icons.live_tv, color: Colors.white24, size: size)
    : CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.contain,
        memCacheWidth: 300,
        fadeInDuration: const Duration(milliseconds: 150),
        errorWidget: (_, __, ___) =>
            Icon(Icons.live_tv, color: Colors.white24, size: size),
      );

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final entries = <(String, List<Channel>)>[
            if (store.rows['Việt Nam'] != null)
              ('Việt Nam', store.rows['Việt Nam']!),
            if (store.fbAll.isNotEmpty)
              ('Bóng đá', store.fbAll.take(40).toList()),
            for (final s in _sections.skip(1))
              if (store.rows[s.$1] != null) (s.$1, store.rows[s.$1]!),
          ];
          final first = store.rows['Việt Nam'] ??
              (store.rows.isNotEmpty ? store.rows.values.first : null);
          return RefreshIndicator(
            color: _accent,
            onRefresh: store.refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverAppBar(
                  floating: true,
                  backgroundColor: const Color(0xE60E0F14),
                  title: const Text('Truyền hình',
                      style: TextStyle(
                          color: _accent,
                          fontWeight: FontWeight.w800,
                          fontSize: 24)),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: () =>
                          showSearch(context: context, delegate: _Search()),
                    ),
                  ],
                ),
                if (first != null && first.isNotEmpty)
                  SliverToBoxAdapter(child: Featured(first.first, first)),
                if (entries.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                        child: CircularProgressIndicator(color: _accent)),
                  ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => _Row(entries[i].$1, entries[i].$2),
                    childCount: entries.length,
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class Featured extends StatelessWidget {
  final Channel ch;
  final List<Channel> list;
  const Featured(this.ch, this.list, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 280,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF3B1D3F), _bg],
        ),
      ),
      child: Stack(children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(90, 56, 90, 96),
            child: _logo(ch.logo, size: 64),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ch.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Row(children: [
              FilledButton.icon(
                onPressed: () => play(context, ch, list),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Xem ngay'),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () => store.toggleFav(ch),
                icon: Icon(store.isFav(ch) ? Icons.check : Icons.add),
                label: const Text('Yêu thích'),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  final String title;
  final List<Channel> list;
  const _Row(this.title, this.list);

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
        child: Text(title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      SizedBox(
        height: 124,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(left: 16),
          itemCount: list.length,
          itemBuilder: (_, i) => _Card(list[i], list),
        ),
      ),
    ]);
  }
}

class _Card extends StatelessWidget {
  final Channel ch;
  final List<Channel> list;
  final double? w;
  const _Card(this.ch, this.list, {this.w = 150});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => play(context, ch, list),
      child: Container(
        width: w,
        margin: w == null ? null : const EdgeInsets.only(right: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: _card, borderRadius: BorderRadius.circular(8)),
              child: _logo(ch.logo),
            ),
          ),
          const SizedBox(height: 6),
          Text(ch.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: Colors.white70)),
        ]),
      ),
    );
  }
}

class _Search extends SearchDelegate<void> {
  _Search() : super(searchFieldLabel: 'Tìm kênh');

  @override
  ThemeData appBarTheme(BuildContext context) =>
      Theme.of(context).copyWith(
        appBarTheme: const AppBarTheme(backgroundColor: _card),
        inputDecorationTheme:
            const InputDecorationTheme(border: InputBorder.none),
      );

  List<Channel> _match() {
    final q = query.toLowerCase().trim();
    final all = {
      for (final c in [
        ...store.rows.values.expand((l) => l),
        ...store.fb.values.expand((l) => l),
        ...store.favs,
      ])
        c.url: c
    }.values;
    return all
        .where((c) => q.isEmpty || c.name.toLowerCase().contains(q))
        .take(100)
        .toList();
  }

  @override
  List<Widget> buildActions(BuildContext c) =>
      [IconButton(icon: const Icon(Icons.clear), onPressed: () => query = '')];

  @override
  Widget buildLeading(BuildContext c) => IconButton(
      icon: const Icon(Icons.arrow_back), onPressed: () => close(c, null));

  @override
  Widget buildResults(BuildContext c) => buildSuggestions(c);

  @override
  Widget buildSuggestions(BuildContext c) {
    final r = _match();
    if (r.isEmpty) {
      return const Center(child: Text('Không tìm thấy kênh nào'));
    }
    return ListView.builder(
      itemCount: r.length,
      itemBuilder: (_, i) => ListTile(
        leading: SizedBox(width: 48, child: _logo(r[i].logo, size: 28)),
        title: Text(r[i].name, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: () => play(c, r[i], r),
      ),
    );
  }
}

class PlayerPage extends StatefulWidget {
  final List<Channel> list;
  final int index;
  const PlayerPage(this.list, this.index, {super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  VideoPlayerController? _c;
  late int _i = widget.index;
  bool _err = false, _ui = true;
  Timer? _hide;
  List<dynamic> _tracks = [];

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();
    _open();
    _scheduleHide();
  }

  Future<void> _open() async {
    final old = _c;
    _c = null;
    _err = false;
    _tracks = [];
    if (old != null) {
      setState(() {});
      await old.dispose();
    }
    final c = VideoPlayerController.networkUrl(
      Uri.parse(widget.list[_i].url),
      formatHint: widget.list[_i].url.toLowerCase().contains('.mp4')
          ? null
          : VideoFormat.hls,
    );
    _c = c;
    try {
      await c.initialize();
      if (!mounted || _c != c) return;
      await c.play();
      setState(() {});
      _loadTracks(c);
    } catch (_) {
      if (mounted && _c == c) setState(() => _err = true);
    }
  }

  void _go(int d) {
    final n = _i + d;
    if (n < 0 || n >= widget.list.length) return;
    setState(() => _i = n);
    _open();
  }

  // Đọc danh sách track âm thanh (nếu bản video_player hỗ trợ).
  Future<void> _loadTracks(VideoPlayerController c) async {
    try {
      final t = await (c as dynamic).getAudioTracks() as List;
      if (mounted && _c == c) setState(() => _tracks = t);
    } catch (_) {}
  }

  String _g(String Function() f) {
    try {
      return f();
    } catch (_) {
      return '';
    }
  }

  (String, String) _describe(dynamic t, int i) {
    final label = _g(() => '${t.label ?? ''}');
    final lang = _g(() => '${t.language ?? ''}');
    final codec = _g(() => '${t.codec ?? ''}').toLowerCase();
    final ch = int.tryParse(_g(() => '${t.channelCount ?? ''}')) ?? 0;
    final layout = ch == 0
        ? ''
        : ch <= 2
            ? 'Stereo'
            : ch == 6
                ? '5.1'
                : ch == 8
                    ? '7.1'
                    : '$ch kênh';
    final fmt = codec.contains('joc') || codec.contains('ec+3')
        ? 'Dolby Atmos'
        : codec.contains('eac3') || codec.contains('ec-3')
            ? 'Dolby Digital Plus'
            : codec.contains('ac3') || codec.contains('ac-3')
                ? 'Dolby Digital'
                : codec.contains('truehd')
                    ? 'Dolby TrueHD'
                    : codec.contains('dts')
                        ? 'DTS'
                        : codec.contains('mp4a') || codec.contains('aac')
                            ? 'AAC'
                            : '';
    final name = label.isNotEmpty
        ? label
        : lang.isNotEmpty
            ? lang
            : 'Âm thanh ${i + 1}';
    return (name, [fmt, layout].where((e) => e.isNotEmpty).join(', '));
  }

  void _audioSheet() {
    final c = _c;
    if (c == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: _card,
      builder: (_) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Âm thanh',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          for (var i = 0; i < _tracks.length; i++)
            ListTile(
              title: Text(_describe(_tracks[i], i).$1),
              subtitle: Text(_describe(_tracks[i], i).$2),
              trailing: _g(() => '${_tracks[i].isSelected}') == 'true'
                  ? const Icon(Icons.check, color: _accent)
                  : null,
              onTap: () async {
                Navigator.pop(context);
                final t = _tracks[i];
                try {
                  await (c as dynamic).selectAudioTrack(t.id);
                } catch (_) {
                  try {
                    await (c as dynamic).selectAudioTrack(t);
                  } catch (_) {}
                }
                _loadTracks(c);
              },
            ),
        ]),
      ),
    );
  }

  Future<void> _seek(int sec) async {
    final c = _c;
    if (c == null) return;
    final p = await c.position ?? Duration.zero;
    await c.seekTo(p + Duration(seconds: sec));
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _ui = false);
    });
  }

  void _toggleUi() {
    setState(() => _ui = !_ui);
    if (_ui) _scheduleHide();
  }

  @override
  void dispose() {
    _hide?.cancel();
    _c?.dispose();
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ch = widget.list[_i];
    final c = _c;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleUi,
        onHorizontalDragEnd: (d) {
          if ((_c?.value.duration.inSeconds ?? 0) > 60) return;
          final v = d.primaryVelocity ?? 0;
          if (v < -300) _go(1);
          if (v > 300) _go(-1);
        },
        child: Stack(fit: StackFit.expand, children: [
          if (c != null && c.value.isInitialized)
            Center(
              child: AspectRatio(
                  aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)),
            ),
          if (!_err)
            c == null
                ? const Center(child: CircularProgressIndicator(color: _accent))
                : ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: c,
                    builder: (_, v, __) {
                      if (v.hasError) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && !_err) setState(() => _err = true);
                        });
                      }
                      return (!v.isInitialized || v.isBuffering)
                          ? const Center(
                              child:
                                  CircularProgressIndicator(color: _accent))
                          : const SizedBox.shrink();
                    },
                  ),
          if (_err)
            Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.signal_wifi_connected_no_internet_4,
                    size: 40, color: Colors.white54),
                const SizedBox(height: 10),
                const Text('Kênh này hiện không phát được'),
                const SizedBox(height: 14),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  OutlinedButton(onPressed: _open, child: const Text('Thử lại')),
                  const SizedBox(width: 10),
                  FilledButton(
                      onPressed: () => _go(1), child: const Text('Kênh kế tiếp')),
                ]),
              ]),
            ),
          IgnorePointer(
            ignoring: !_ui,
            child: AnimatedOpacity(
              opacity: _ui ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black87, Colors.transparent, Colors.black87],
                  ),
                ),
                child: SafeArea(
                  child: Column(children: [
                    Row(children: [
                      IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () => Navigator.pop(context)),
                      Expanded(
                        child: Text(ch.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w600)),
                      ),
                      if (_tracks.isNotEmpty)
                        IconButton(
                            icon: const Icon(Icons.graphic_eq),
                            tooltip: 'Âm thanh',
                            onPressed: _audioSheet),
                      ListenableBuilder(
                        listenable: store,
                        builder: (_, __) => IconButton(
                          icon: Icon(store.isFav(ch)
                              ? Icons.favorite
                              : Icons.favorite_border),
                          color: store.isFav(ch) ? _accent : Colors.white,
                          onPressed: () => store.toggleFav(ch),
                        ),
                      ),
                    ]),
                    const Spacer(),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      IconButton(
                          iconSize: 38,
                          icon: const Icon(Icons.skip_previous),
                          onPressed: () => _go(-1)),
                      const SizedBox(width: 24),
                      if (c != null)
                        ValueListenableBuilder<VideoPlayerValue>(
                          valueListenable: c,
                          builder: (_, v, __) => IconButton(
                            iconSize: 56,
                            icon: Icon(v.isPlaying
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_filled),
                            onPressed: () =>
                                v.isPlaying ? c.pause() : c.play(),
                          ),
                        ),
                      const SizedBox(width: 24),
                      IconButton(
                          iconSize: 38,
                          icon: const Icon(Icons.skip_next),
                          onPressed: () => _go(1)),
                    ]),
                    if (c != null && c.value.duration.inSeconds > 60)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                        child: Row(children: [
                          IconButton(
                              icon: const Icon(Icons.replay_10),
                              onPressed: () => _seek(-10)),
                          Expanded(
                            child: VideoProgressIndicator(c,
                                allowScrubbing: true,
                                colors: const VideoProgressColors(
                                    playedColor: _accent)),
                          ),
                          IconButton(
                              icon: const Icon(Icons.forward_10),
                              onPressed: () => _seek(10)),
                        ]),
                      ),
                    const SizedBox(height: 12),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [HomePage(), FootballPage(), FilmPage(), FavPage()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        backgroundColor: _card,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Trang chủ'),
          NavigationDestination(
              icon: Icon(Icons.sports_soccer_outlined),
              selectedIcon: Icon(Icons.sports_soccer),
              label: 'Bóng đá'),
          NavigationDestination(
              icon: Icon(Icons.movie_outlined),
              selectedIcon: Icon(Icons.movie),
              label: 'Phim'),
          NavigationDestination(
              icon: Icon(Icons.favorite_border),
              selectedIcon: Icon(Icons.favorite),
              label: 'Yêu thích'),
        ],
      ),
    );
  }
}

Widget _grid(List<Channel> list) => GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: list.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 12,
        childAspectRatio: 1.35,
      ),
      itemBuilder: (_, i) => _Card(list[i], list, w: null),
    );

class FootballPage extends StatefulWidget {
  const FootballPage({super.key});

  @override
  State<FootballPage> createState() => _FootballPageState();
}

class _FootballPageState extends State<FootballPage> {
  String _tab = 'all';
  static const _tabs = {
    'all': 'Tất cả',
    'dom': 'Trong nước',
    'intl': 'Quốc tế',
    'club': 'Kênh CLB',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _bg,
        title: const Text('Bóng đá',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final list = _tab == 'all' ? store.fbAll : store.fb[_tab]!;
          return Column(children: [
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  for (final e in _tabs.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(e.value),
                        selected: _tab == e.key,
                        onSelected: (_) => setState(() => _tab = e.key),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: list.isEmpty
                  ? Center(
                      child: store.fbAll.isEmpty
                          ? const CircularProgressIndicator(color: _accent)
                          : const Text('Chưa có kênh trong mục này'))
                  : _grid(list),
            ),
          ]);
        },
      ),
    );
  }
}

class FavPage extends StatelessWidget {
  const FavPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _bg,
        title: const Text('Yêu thích',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) => store.favs.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Chưa có kênh yêu thích. Khi xem kênh, nhấn biểu tượng trái tim để lưu lại.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              )
            : _grid(store.favs),
      ),
    );
  }
}

// Khóa API được nhúng lúc build (GitHub Secrets hoặc --dart-define).
// Có thể dán trực tiếp vào defaultValue nếu build trên máy cá nhân.
bool _has(String k) => k.isNotEmpty && !k.contains('DÁN');

// Khóa TMDB miễn phí: themoviedb.org > Cài đặt > API (API Key v3).
const kTmdbKey =
    String.fromEnvironment('TMDB_KEY', defaultValue: 'DÁN_KHÓA_TMDB_VÀO_ĐÂY');
const _tmdb = 'https://api.themoviedb.org/3';
const _img = 'https://image.tmdb.org/t/p/w342';
const _filmRows = <(String, String, String)>[
  ('Phim lẻ thịnh hành', '/trending/movie/week', 'movie'),
  ('Phim bộ thịnh hành', '/trending/tv/week', 'tv'),
  ('Hoạt hình', '/discover/movie?with_genres=16&sort_by=popularity.desc', 'movie'),
  ('Phim Việt Nam',
      '/discover/movie?with_origin_country=VN&sort_by=popularity.desc', 'movie'),
];

class Film {
  final int id;
  final String type, title, poster, overview, date;
  final double rating;
  Film.fromJson(Map<String, dynamic> j, this.type)
      : id = j['id'],
        title = (j['title'] ?? j['name'] ?? '') as String,
        poster = (j['poster_path'] ?? '') as String,
        overview = (j['overview'] ?? '') as String,
        date = (j['release_date'] ?? j['first_air_date'] ?? '') as String,
        rating = ((j['vote_average'] ?? 0) as num).toDouble();
  String get year => date.length >= 4 ? date.substring(0, 4) : '';
}

Future<Map<String, dynamic>?> tmdb(String path, {String lang = 'vi-VN'}) async {
  try {
    final sep = path.contains('?') ? '&' : '?';
    final r = await http
        .get(Uri.parse('$_tmdb$path${sep}api_key=$kTmdbKey&language=$lang&region=VN'))
        .timeout(const Duration(seconds: 20));
    return r.statusCode == 200
        ? jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>
        : null;
  } catch (_) {
    return null;
  }
}

class InfoPage extends StatefulWidget {
  const InfoPage({super.key});

  @override
  State<InfoPage> createState() => _InfoPageState();
}

class _InfoPageState extends State<InfoPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late final Future<Map<String, List<Film>>> _f = _load();

  Future<Map<String, List<Film>>> _load() async {
    final out = <String, List<Film>>{};
    if (!_has(kTmdbKey)) return out;
    await Future.wait(_filmRows.map((s) async {
      final j = await tmdb(s.$2);
      final list = (j?['results'] as List?)
          ?.map((e) => Film.fromJson(e as Map<String, dynamic>, s.$3))
          .where((f) => f.poster.isNotEmpty)
          .toList();
      if (list != null && list.isNotEmpty) out[s.$1] = list;
    }));
    return out;
  }

  Widget _msg(String t) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(t,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, height: 1.5)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      body: !_has(kTmdbKey)
          ? _msg('Cần thêm khóa TMDB (miễn phí) để xem danh sách phim. Đăng ký tại themoviedb.org, vào Cài đặt > API, lấy API Key (v3), rồi thêm vào GitHub Secrets với tên TMDB_KEY và build lại. Xem README.md.')
          : FutureBuilder<Map<String, List<Film>>>(
              future: _f,
              builder: (c, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(
                      child: CircularProgressIndicator(color: _accent));
                }
                final d = snap.data ?? {};
                if (d.isEmpty) {
                  return _msg('Không tải được danh sách phim. Kiểm tra kết nối mạng hoặc khóa TMDB.');
                }
                return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
                  for (final r in _filmRows)
                    if (d[r.$1] != null) _FilmRow(r.$1, d[r.$1]!),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 24, 16, 0),
                    child: Text(
                        'Sản phẩm này dùng API của TMDB nhưng không được TMDB xác nhận hay chứng nhận.',
                        style: TextStyle(fontSize: 11, color: Colors.white38)),
                  ),
                ]);
              },
            ),
    );
  }
}

class _FilmRow extends StatelessWidget {
  final String title;
  final List<Film> list;
  const _FilmRow(this.title, this.list);

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
        child: Text(title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      SizedBox(
        height: 212,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(left: 16),
          itemCount: list.length,
          itemBuilder: (_, i) => GestureDetector(
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => FilmDetail(list[i]))),
            child: Container(
              width: 120,
              margin: const EdgeInsets.only(right: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    height: 180,
                    width: 120,
                    child: CachedNetworkImage(
                      imageUrl: '$_img${list[i].poster}',
                      fit: BoxFit.cover,
                      memCacheWidth: 300,
                      placeholder: (_, __) => const ColoredBox(color: _card),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(list[i].title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: Colors.white70)),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}

class FilmDetail extends StatefulWidget {
  final Film film;
  const FilmDetail(this.film, {super.key});

  @override
  State<FilmDetail> createState() => _FilmDetailState();
}

class _FilmDetailState extends State<FilmDetail> {
  String? _link, _trailer;
  List<String> _providers = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final f = widget.film;
    final w = await tmdb('/${f.type}/${f.id}/watch/providers');
    final vn = (w?['results'] as Map?)?['VN'] as Map?;
    final names = <String>{
      for (final k in ['flatrate', 'free', 'ads'])
        for (final p in ((vn?[k] as List?) ?? []))
          (p as Map)['provider_name'] as String
    }.toList();
    final v = await tmdb('/${f.type}/${f.id}/videos', lang: 'en-US');
    final vids = ((v?['results'] as List?) ?? []).cast<Map>();
    final t = vids
        .where((e) => e['site'] == 'YouTube' && e['type'] == 'Trailer')
        .firstOrNull;
    if (!mounted) return;
    setState(() {
      _providers = names;
      _link = vn?['link'] as String?;
      _trailer = t?['key'] as String?;
      _loaded = true;
    });
  }

  void _open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final f = widget.film;
    return Scaffold(
      appBar: AppBar(backgroundColor: _bg),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 120,
              height: 180,
              child: CachedNetworkImage(imageUrl: '$_img${f.poster}', fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(f.title,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.star, size: 16, color: Colors.amber),
                const SizedBox(width: 4),
                Text(f.rating.toStringAsFixed(1)),
                const SizedBox(width: 14),
                Text(f.year, style: const TextStyle(color: Colors.white70)),
              ]),
              const SizedBox(height: 12),
              if (_trailer != null)
                OutlinedButton.icon(
                  onPressed: () => _open('https://www.youtube.com/watch?v=$_trailer'),
                  icon: const Icon(Icons.play_circle_outline),
                  label: const Text('Xem trailer'),
                ),
            ]),
          ),
        ]),
        const SizedBox(height: 18),
        Text(f.overview.isEmpty ? 'Chưa có mô tả tiếng Việt cho phim này.' : f.overview,
            style: const TextStyle(height: 1.5, color: Colors.white70)),
        const SizedBox(height: 22),
        const Text('Xem ở đâu tại Việt Nam',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        if (!_loaded)
          const LinearProgressIndicator(color: _accent)
        else if (_providers.isEmpty)
          const Text('Chưa có dịch vụ nào chiếu phim này tại Việt Nam.',
              style: TextStyle(color: Colors.white70))
        else ...[
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final n in _providers) Chip(label: Text(n)),
          ]),
          const SizedBox(height: 12),
          if (_link != null)
            FilledButton(
                onPressed: () => _open(_link!), child: const Text('Mở trang xem phim')),
          const SizedBox(height: 8),
          const Text('Thông tin nơi xem do JustWatch cung cấp qua TMDB.',
              style: TextStyle(fontSize: 11, color: Colors.white38)),
        ],
      ]),
    );
  }
}

// Khóa YouTube Data API v3 (miễn phí): console.cloud.google.com.
const kYoutubeKey = String.fromEnvironment('YOUTUBE_KEY',
    defaultValue: 'DÁN_KHÓA_YOUTUBE_VÀO_ĐÂY');

class Vid {
  final String id, title, thumb;
  const Vid(this.id, this.title, this.thumb);
}

String _unesc(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&#39;', "'")
    .replaceAll('&quot;', '"');

// Chỉ lấy phim thuộc danh mục "Phim" của YouTube và cho phép nhúng.
Future<List<Vid>> ytMovies(String q, String lang) async {
  try {
    final u = Uri.https('www.googleapis.com', '/youtube/v3/search', {
      'part': 'snippet',
      'type': 'video',
      'videoType': 'movie',
      'videoEmbeddable': 'true',
      'regionCode': 'VN',
      'relevanceLanguage': lang,
      'maxResults': '25',
      'q': q,
      'key': kYoutubeKey,
    });
    final r = await http.get(u).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) return [];
    final items = jsonDecode(utf8.decode(r.bodyBytes))['items'] as List;
    return [
      for (final i in items)
        Vid(i['id']['videoId'] as String, _unesc(i['snippet']['title'] as String),
            i['snippet']['thumbnails']['medium']['url'] as String)
    ];
  } catch (_) {
    return [];
  }
}

// Phim kinh điển thuộc phạm vi công cộng trên Internet Archive.
Future<List<Vid>> archiveFilms() async {
  try {
    final u = Uri.https('archive.org', '/advancedsearch.php', {
      'q': 'collection:feature_films AND mediatype:movies',
      'fl[]': ['identifier', 'title'],
      'sort[]': 'downloads desc',
      'rows': '40',
      'output': 'json',
    });
    final r = await http.get(u).timeout(const Duration(seconds: 20));
    final docs = jsonDecode(utf8.decode(r.bodyBytes))['response']['docs'] as List;
    return [
      for (final d in docs)
        Vid('${d['identifier']}', '${d['title']}',
            'https://archive.org/services/img/${d['identifier']}')
    ];
  } catch (_) {
    return [];
  }
}

Future<String?> archiveUrl(String id) async {
  try {
    final r = await http
        .get(Uri.https('archive.org', '/metadata/$id'))
        .timeout(const Duration(seconds: 20));
    final files = (jsonDecode(r.body)['files'] as List).cast<Map>();
    final mp4 = files
        .where((f) => '${f['name']}'.toLowerCase().endsWith('.mp4'))
        .toList();
    if (mp4.isEmpty) return null;
    final best = mp4.firstWhere(
        (f) => '${f['format']}'.toLowerCase().startsWith('h.264'),
        orElse: () => mp4.first);
    return Uri(
        scheme: 'https',
        host: 'archive.org',
        pathSegments: ['download', id, ...'${best['name']}'.split('/')]).toString();
  } catch (_) {
    return null;
  }
}

void _openYt(BuildContext c, Vid v) => Navigator.push(
    c, MaterialPageRoute(builder: (_) => YtPage(v)));

Future<void> _openArchive(BuildContext c, Vid v) async {
  final url = await archiveUrl(v.id);
  if (!c.mounted) return;
  if (url == null) {
    ScaffoldMessenger.of(c).showSnackBar(
        const SnackBar(content: Text('Không mở được phim này. Hãy thử phim khác.')));
    return;
  }
  final ch = Channel(v.title, url, v.thumb);
  play(c, ch, [ch]);
}

class FilmPage extends StatelessWidget {
  const FilmPage({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            backgroundColor: _bg,
            title: const Text('Phim',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
            bottom: const TabBar(
              indicatorColor: _accent,
              tabs: [Tab(text: 'Xem ngay'), Tab(text: 'Thông tin phim')],
            ),
          ),
          body: const TabBarView(children: [WatchTab(), InfoPage()]),
        ),
      );
}

class WatchTab extends StatefulWidget {
  const WatchTab({super.key});

  @override
  State<WatchTab> createState() => _WatchTabState();
}

class _WatchTabState extends State<WatchTab>
    with AutomaticKeepAliveClientMixin {
  late final Future<List<Vid>> _vn = ytMovies('phim việt nam', 'vi');
  late final Future<List<Vid>> _dub = ytMovies('phim lồng tiếng thuyết minh', 'vi');
  late final Future<List<Vid>> _world = ytMovies('full movie', 'en');
  late final Future<List<Vid>> _arc = archiveFilms();

  @override
  bool get wantKeepAlive => true;

  Widget _note(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
        child: Text(t,
            style: const TextStyle(fontSize: 12.5, height: 1.5, color: Colors.white54)),
      );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final yt = _has(kYoutubeKey);
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      if (yt) ...[
        _VidRow('Phim Việt Nam', _vn, _openYt),
        _VidRow('Phim lồng tiếng, thuyết minh', _dub, _openYt),
        _VidRow('Phim nước ngoài', _world, _openYt),
        _note('Phim lấy từ danh mục phim chính thức của YouTube. Bấm CC trong trình phát để bật phụ đề tiếng Việt khi phim có. Số lượng phim thay đổi theo từng thời điểm.'),
      ] else
        _note('Để xem phim Việt Nam và phim nước ngoài từ YouTube, hãy thêm khóa YouTube Data API v3 vào GitHub Secrets với tên YOUTUBE_KEY rồi build lại. Xem README.md.'),
      _VidRow('Phim kinh điển miễn phí', _arc, _openArchive),
      _note('Phim kinh điển thuộc phạm vi công cộng, nguồn Internet Archive, phần lớn là phim tiếng Anh, không có phụ đề tiếng Việt.'),
    ]);
  }
}

class _VidRow extends StatelessWidget {
  final String title;
  final Future<List<Vid>> future;
  final void Function(BuildContext, Vid) onTap;
  const _VidRow(this.title, this.future, this.onTap);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Vid>>(
      future: future,
      builder: (c, snap) {
        final done = snap.connectionState == ConnectionState.done;
        final list = snap.data ?? [];
        if (done && list.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
            child: Text(title,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          SizedBox(
            height: 150,
            child: !done
                ? const Center(child: CircularProgressIndicator(color: _accent))
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(left: 16),
                    itemCount: list.length,
                    itemBuilder: (_, i) => GestureDetector(
                      onTap: () => onTap(c, list[i]),
                      child: Container(
                        width: 200,
                        margin: const EdgeInsets.only(right: 10),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(
                                  width: 200,
                                  height: 112,
                                  child: CachedNetworkImage(
                                    imageUrl: list[i].thumb,
                                    fit: BoxFit.cover,
                                    memCacheWidth: 400,
                                    placeholder: (_, __) =>
                                        const ColoredBox(color: _card),
                                    errorWidget: (_, __, ___) =>
                                        const ColoredBox(color: _card),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(list[i].title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12.5, color: Colors.white70)),
                            ]),
                      ),
                    ),
                  ),
          ),
        ]);
      },
    );
  }
}

class YtPage extends StatefulWidget {
  final Vid vid;
  const YtPage(this.vid, {super.key});

  @override
  State<YtPage> createState() => _YtPageState();
}

class _YtPageState extends State<YtPage> {
  late final YoutubePlayerController _c = YoutubePlayerController.fromVideoId(
    videoId: widget.vid.id,
    autoPlay: true,
    params: const YoutubePlayerParams(
        showFullscreenButton: true, strictRelatedVideos: true),
  );

  @override
  void dispose() {
    _c.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return YoutubePlayerScaffold(
      controller: _c,
      aspectRatio: 16 / 9,
      builder: (context, player) => Scaffold(
        appBar: AppBar(backgroundColor: _bg),
        body: ListView(children: [
          player,
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.vid.title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              const Text(
                  'Bấm CC để bật phụ đề. Bấm biểu tượng bánh răng để đổi chất lượng hoặc ngôn ngữ âm thanh nếu phim có.',
                  style: TextStyle(color: Colors.white70, height: 1.5)),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => launchUrl(
                    Uri.parse('https://www.youtube.com/watch?v=${widget.vid.id}'),
                    mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Mở trong YouTube'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
