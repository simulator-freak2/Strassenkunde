import 'package:flutter/material.dart';

import '../data/profile.dart';
import '../data/storage.dart';
import 'profile_home_page.dart';

class ProfilesPage extends StatefulWidget {
  final Storage storage;
  const ProfilesPage({super.key, required this.storage});

  @override
  State<ProfilesPage> createState() => _ProfilesPageState();
}

class _ProfilesPageState extends State<ProfilesPage> {
  List<Profile>? _profiles;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await widget.storage.loadProfiles();
    if (mounted) setState(() => _profiles = list);
  }

  Future<void> _create() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Neues Profil'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'Name', hintText: 'z. B. Max – FF Musterstadt'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Anlegen')),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    final p = await widget.storage.createProfile(name.trim());
    await _reload();
    if (mounted) _open(p);
  }

  Future<void> _delete(Profile p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Profil löschen?'),
        content: Text('„${p.name}“ mit Kartendaten, Lernstand und '
            'Prüfungsergebnissen wird endgültig gelöscht.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.storage.deleteProfile(p);
    await _reload();
  }

  Future<void> _open(Profile p) async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                ProfileHomePage(storage: widget.storage, profile: p)));
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final list = _profiles;
    final canCreate = list != null && list.length < maxProfiles;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Straßenkunde – Profile'),
        actions: [
          IconButton(
            tooltip: 'Info',
            icon: const Icon(Icons.info_outline),
            onPressed: () => showAboutDialog(
              context: context,
              applicationName: 'Straßenkunde',
              applicationVersion: '1.0',
              applicationLegalese:
                  'Ortskunde-Trainer für die Feuerwehr.\n\n'
                  'Kartendaten © OpenStreetMap-Mitwirkende, '
                  'verfügbar unter der Open Database License (ODbL).\n\n'
                  'Datenordner: ${widget.storage.root.path}',
            ),
          ),
        ],
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.person_add),
              label: const Text('Neues Profil'))
          : null,
      body: list == null
          ? const Center(child: CircularProgressIndicator())
          : list.isEmpty
              ? _Empty(onCreate: _create)
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 700),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                      children: [
                        Text('${list.length} von $maxProfiles Profilen',
                            style: Theme.of(context).textTheme.labelLarge),
                        const SizedBox(height: 8),
                        for (final p in list)
                          Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                  child: Text(p.name.characters.first.toUpperCase())),
                              title: Text(p.name),
                              subtitle: Text(p.areas.isEmpty
                                  ? 'Noch kein Gebiet eingerichtet'
                                  : p.areas
                                      .map((a) => a.name.split(',').first)
                                      .join(', ')),
                              onTap: () => _open(p),
                              trailing: IconButton(
                                tooltip: 'Profil löschen',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _delete(p),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
    );
  }
}

class _Empty extends StatelessWidget {
  final VoidCallback onCreate;
  const _Empty({required this.onCreate});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.local_fire_department,
                size: 72, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text('Willkommen bei Straßenkunde',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text(
              'Lege ein Profil an, wähle deinen Ausrückebereich und das '
              'Gerätehaus – dann kann es mit dem Lernen losgehen.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.person_add),
                label: const Text('Profil anlegen')),
          ]),
        ),
      );
}
