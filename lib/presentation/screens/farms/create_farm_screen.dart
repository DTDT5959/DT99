import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/farm_provider.dart';
import '../layout/layout_editor_screen.dart';

/// Step 1 of farm creation: name + optional description. On "Continue" a
/// farm row is created immediately (so autosave has something to attach
/// posts to) and we push straight into the layout editor canvas.
class CreateFarmScreen extends StatefulWidget {
  const CreateFarmScreen({super.key});

  @override
  State<CreateFarmScreen> createState() => _CreateFarmScreenState();
}

class _CreateFarmScreenState extends State<CreateFarmScreen> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  bool _saving = false;

  Future<void> _continue() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a farm name')),
      );
      return;
    }
    setState(() => _saving = true);
    final farm = await context.read<FarmProvider>().createFarm(
          name: _nameController.text,
          description: _descController.text,
        );
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => LayoutEditorScreen(farmId: farm.id, farmName: farm.name)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Farm')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Farm Name', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'e.g. North Farm'),
            ),
            const SizedBox(height: 20),
            Text('Description (optional)', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _descController,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'Any notes about this farm...'),
            ),
            const Spacer(),
            FilledButton(
              onPressed: _saving ? null : _continue,
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}
