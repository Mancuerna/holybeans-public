import 'package:flutter/material.dart';
import 'package:holybeans/domain/roaster_profile.dart';
import 'package:holybeans/l10n/app_localizations.dart';

class RoastersPage extends StatefulWidget {
  const RoastersPage({super.key, required this.profiles, required this.onOpen});
  final List<RoasterProfile> profiles;
  final ValueChanged<String> onOpen;
  @override
  State<RoastersPage> createState() => _RoastersPageState();
}

class _RoastersPageState extends State<RoastersPage> {
  final search = TextEditingController();
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final query = roasterKey(search.text);
    final visible = widget.profiles
        .where((p) => p.key.contains(query))
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(s.roasterProfilesTitle)),
      body: SafeArea(
        child: CustomScrollView(
          key: const ValueKey('roasters-list'),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.roasterDirectoryHint),
                    const SizedBox(height: 16),
                    TextField(
                      key: const ValueKey('roaster-search'),
                      controller: search,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: s.roasterSearch,
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: search.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: s.roasterClearSearch,
                                onPressed: () => setState(search.clear),
                                icon: const Icon(Icons.close_rounded),
                              ),
                      ),
                    ),
                    if (visible.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: Text(
                          widget.profiles.isEmpty
                              ? s.roasterEmpty
                              : s.roasterNoResults,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SliverList.builder(
              itemCount: visible.length,
              itemBuilder: (context, index) {
                final roaster = visible[index];
                return ListTile(
                  key: ValueKey('roaster-row-${roaster.key}'),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 6,
                  ),
                  leading: const Icon(Icons.storefront_outlined),
                  title: Text(roaster.name),
                  subtitle: Text(
                    [
                      s.roasterListSummary(
                        roaster.coffees.length,
                        roaster.brewCount,
                      ),
                      if (roaster.cafeDrinks.isNotEmpty)
                        '${s.cafeDrinksLabel}: ${roaster.cafeDrinks.length}',
                    ].join(' · '),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    FocusScope.of(context).unfocus();
                    widget.onOpen(roaster.name);
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
