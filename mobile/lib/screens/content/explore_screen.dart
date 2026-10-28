import 'dart:async';

import 'package:flutter/material.dart';

import '../../config.dart';
import '../../services/content.dart';
import '../../services/session.dart';
import '../../widgets/common.dart';
import '../../widgets/post_card.dart';
import '../plans_screen.dart';
import 'post_screen.dart';

/// Explore: app bar (name, search, crown), category chips, Latest list.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});
  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  List<Json> _categories = [];
  String? _category;
  final List<Json> _posts = [];
  bool _loading = true;
  bool _more = true;
  String? _error;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    Content.categories().then((c) {
      if (mounted) setState(() => _categories = c);
    }).catchError((_) {});
    _reload();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) _loadMore();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _posts.clear();
      _more = true;
    });
    await _loadMore(force: true);
  }

  Future<void> _loadMore({bool force = false}) async {
    if (!_more || (!force && _loading)) return;
    _loading = true;
    try {
      final page = await Content.posts(category: _category, offset: _posts.length, limit: 20);
      if (!mounted) return;
      setState(() {
        _posts.addAll(page);
        _more = page.length == 20;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [BrandMark(size: 30), SizedBox(width: 10), Text(AppConfig.appName)]),
        actions: [
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchScreen())),
          ),
          if (!session.hidePaid) CrownButton(onTap: () => openPlans(context)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: CustomScrollView(controller: _scroll, slivers: [
          SliverToBoxAdapter(
            child: SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  _chip('All', null),
                  for (final c in _categories) _chip('${c['name']}', '${c['slug']}'),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text('Latest', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
          ),
          if (_error != null && _posts.isEmpty)
            SliverFillRemaining(child: ErrorRetry(message: _error!, onRetry: _reload))
          else if (!_loading && _posts.isEmpty)
            const SliverFillRemaining(child: EmptyState(text: 'No Record Found'))
          else
            SliverList.builder(
              itemCount: _posts.length + (_more ? 1 : 0),
              itemBuilder: (c, i) => i >= _posts.length
                  ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
                      child: PostCard(post: _posts[i], onTap: () => PostScreen.open(context, '${_posts[i]['id']}')),
                    ),
            ),
        ]),
      ),
    );
  }

  Widget _chip(String label, String? slug) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: _category == slug,
          showCheckmark: false,
          onSelected: (_) {
            setState(() => _category = slug);
            _reload();
          },
        ),
      );
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<Json>? _results;
  bool _busy = false;

  void _search(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (text.trim().length < 2) {
        setState(() => _results = null);
        return;
      }
      setState(() => _busy = true);
      try {
        final r = await Content.posts(query: text, limit: 40);
        if (mounted) setState(() => _results = r);
      } catch (e) {
        if (mounted) showSnack(context, friendlyError(e), error: true);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: TextField(
            controller: _q,
            autofocus: true,
            onChanged: _search,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(hintText: 'Search videos and channels', isDense: true),
          ),
        ),
        body: _busy && _results == null
            ? const Center(child: CircularProgressIndicator())
            : _results == null
                ? const EmptyState(text: 'Type at least 2 letters', icon: Icons.search)
                : _results!.isEmpty
                    ? const EmptyState(text: 'No Record Found')
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _results!.length,
                        itemBuilder: (c, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: PostCard(post: _results![i], onTap: () => PostScreen.open(context, '${_results![i]['id']}')),
                        ),
                      ),
      );
}
