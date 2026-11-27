import 'package:flutter/material.dart';
import '../services/ai_transaction_service.dart';
import '../services/invoice_extractor_service.dart';
import '../services/storage_service.dart';

/// Shared AI API Keys & Model Selector dialog used across screens.
/// Returns `true` if keys or selected models were saved.
Future<bool> showAiSettingsDialog(BuildContext context) async {
  final storage = StorageService.instance;
  final currentGrok = await storage.getGrokApiKey() ?? '';
  final currentGemini = await storage.getGeminiApiKey() ?? '';
  final savedGrokModel = await storage.getSelectedGrokModel();
  final savedGeminiModel = await storage.getSelectedGeminiModel();
  final cachedGrokModels = await storage.getCachedGrokModels();
  final cachedGeminiModels = await storage.getCachedGeminiModels();

  if (!context.mounted) return false;

  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => _AiSettingsDialogContent(
      initialGrokKey: currentGrok,
      initialGeminiKey: currentGemini,
      initialGrokModel: savedGrokModel,
      initialGeminiModel: savedGeminiModel,
      cachedGrokModels: cachedGrokModels,
      cachedGeminiModels: cachedGeminiModels,
    ),
  );
  return saved == true;
}

class _AiSettingsDialogContent extends StatefulWidget {
  final String initialGrokKey;
  final String initialGeminiKey;
  final String? initialGrokModel;
  final String? initialGeminiModel;
  final List<String> cachedGrokModels;
  final List<String> cachedGeminiModels;

  const _AiSettingsDialogContent({
    required this.initialGrokKey,
    required this.initialGeminiKey,
    required this.initialGrokModel,
    required this.initialGeminiModel,
    required this.cachedGrokModels,
    required this.cachedGeminiModels,
  });

  @override
  State<_AiSettingsDialogContent> createState() => _AiSettingsDialogContentState();
}

class _AiSettingsDialogContentState extends State<_AiSettingsDialogContent> {
  late final TextEditingController _grokController;
  late final TextEditingController _geminiController;
  late List<String> _grokModels;
  late List<String> _geminiModels;
  late String _selectedGrokModel;
  late String _selectedGeminiModel;
  bool _obscureGrok = true;
  bool _obscureGemini = true;
  bool _isTesting = false;
  bool _isFetchingModels = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _grokController = TextEditingController(text: widget.initialGrokKey);
    _geminiController = TextEditingController(text: widget.initialGeminiKey);

    _grokModels = List<String>.from(
      widget.cachedGrokModels.isNotEmpty
          ? widget.cachedGrokModels
          : InvoiceExtractorService.defaultGrokModelsForKey(widget.initialGrokKey),
    );
    _geminiModels = List<String>.from(
      widget.cachedGeminiModels.isNotEmpty
          ? widget.cachedGeminiModels
          : InvoiceExtractorService.defaultGeminiModels,
    );

    _selectedGrokModel = (widget.initialGrokModel != null && widget.initialGrokModel!.isNotEmpty)
        ? widget.initialGrokModel!
        : _grokModels.first;
    if (!_grokModels.contains(_selectedGrokModel)) {
      _grokModels = [_selectedGrokModel, ..._grokModels];
    }

    _selectedGeminiModel = (widget.initialGeminiModel != null && widget.initialGeminiModel!.isNotEmpty)
        ? widget.initialGeminiModel!
        : _geminiModels.first;
    if (!_geminiModels.contains(_selectedGeminiModel)) {
      _geminiModels = [_selectedGeminiModel, ..._geminiModels];
    }

    if (widget.initialGrokKey.trim().isNotEmpty || widget.initialGeminiKey.trim().isNotEmpty) {
      Future.microtask(() => _refreshModels(showFeedback: false));
    }
  }

  @override
  void dispose() {
    _grokController.dispose();
    _geminiController.dispose();
    super.dispose();
  }

  Future<void> _refreshModels({bool showFeedback = true}) async {
    if (!mounted) return;
    setState(() => _isFetchingModels = true);
    try {
      final fetchedGrok = await InvoiceExtractorService.instance.fetchAvailableGrokModels(
        _grokController.text.trim(),
      );
      final fetchedGemini = await InvoiceExtractorService.instance.fetchAvailableGeminiModels(
        _geminiController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        if (fetchedGrok.isNotEmpty) {
          _grokModels = List<String>.from(fetchedGrok);
          if (!_grokModels.contains(_selectedGrokModel)) {
            _selectedGrokModel = _grokModels.first;
          }
        }
        if (fetchedGemini.isNotEmpty) {
          _geminiModels = List<String>.from(fetchedGemini);
          if (!_geminiModels.contains(_selectedGeminiModel)) {
            _selectedGeminiModel = _geminiModels.first;
          }
        }
        if (showFeedback) {
          _testResult = 'Loaded ${_grokModels.length} Grok & ${_geminiModels.length} Gemini models.';
        }
      });
    } finally {
      if (mounted) {
        setState(() => _isFetchingModels = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1B2042) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1E293B);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final inputBg = isDark ? const Color(0xFF10132B) : const Color(0xFFF8FAFC);
    final inputBorder = isDark ? const Color(0xFF2C3360) : const Color(0xFFCBD5E1);

    return AlertDialog(
      backgroundColor: cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          const Text('🔑', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'AI API Keys',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textPrimary),
            ),
          ),
          IconButton(
            tooltip: 'Refresh available models',
            onPressed: _isFetchingModels ? null : () => _refreshModels(),
            icon: _isFetchingModels
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6366F1)),
                  )
                : const Icon(Icons.sync_rounded, color: Color(0xFF6366F1)),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select your preferred models and keys. Available models load directly from each provider.',
              style: TextStyle(fontSize: 12, color: textSecondary),
            ),
            const SizedBox(height: 14),

            // Grok Key + Model
            Row(
              children: [
                Text('⚡ Grok API Key',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textPrimary)),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('PRIMARY',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF6366F1))),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _grokController,
              obscureText: _obscureGrok,
              style: TextStyle(fontSize: 13, color: textPrimary),
              decoration: InputDecoration(
                hintText: 'gsk_... (Groq), sk-or-... (OpenRouter), or xai-...',
                hintStyle: TextStyle(fontSize: 11.5, color: textSecondary.withValues(alpha: 0.65)),
                filled: true,
                fillColor: inputBg,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: inputBorder),
                ),
                suffixIcon: IconButton(
                  icon: Icon(_obscureGrok ? Icons.visibility_off : Icons.visibility,
                      size: 18, color: textSecondary),
                  onPressed: () => setState(() => _obscureGrok = !_obscureGrok),
                ),
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: ValueKey('dlg_grok_${_selectedGrokModel}_${_grokModels.length}'),
              initialValue: _grokModels.contains(_selectedGrokModel) ? _selectedGrokModel : _grokModels.first,
              isExpanded: true,
              menuMaxHeight: 320,
              style: TextStyle(fontSize: 12.5, color: textPrimary),
              dropdownColor: cardBg,
              decoration: InputDecoration(
                labelText: 'Grok / Groq Model',
                labelStyle: TextStyle(fontSize: 12, color: textSecondary),
                filled: true,
                fillColor: inputBg,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: inputBorder),
                ),
              ),
              items: _grokModels
                  .map((m) => DropdownMenuItem<String>(
                        value: m,
                        child: Text(m, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedGrokModel = val);
              },
            ),
            const SizedBox(height: 16),

            // Gemini Key + Model
            Row(
              children: [
                Text('✨ Gemini API Key',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textPrimary)),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('FALLBACK',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _geminiController,
              obscureText: _obscureGemini,
              style: TextStyle(fontSize: 13, color: textPrimary),
              decoration: InputDecoration(
                hintText: 'AIza... (Google Gemini API Key)',
                hintStyle: TextStyle(fontSize: 11.5, color: textSecondary.withValues(alpha: 0.65)),
                filled: true,
                fillColor: inputBg,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: inputBorder),
                ),
                suffixIcon: IconButton(
                  icon: Icon(_obscureGemini ? Icons.visibility_off : Icons.visibility,
                      size: 18, color: textSecondary),
                  onPressed: () => setState(() => _obscureGemini = !_obscureGemini),
                ),
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: ValueKey('dlg_gem_${_selectedGeminiModel}_${_geminiModels.length}'),
              initialValue: _geminiModels.contains(_selectedGeminiModel) ? _selectedGeminiModel : _geminiModels.first,
              isExpanded: true,
              menuMaxHeight: 320,
              style: TextStyle(fontSize: 12.5, color: textPrimary),
              dropdownColor: cardBg,
              decoration: InputDecoration(
                labelText: 'Gemini Model',
                labelStyle: TextStyle(fontSize: 12, color: textSecondary),
                filled: true,
                fillColor: inputBg,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: inputBorder),
                ),
              ),
              items: _geminiModels
                  .map((m) => DropdownMenuItem<String>(
                        value: m,
                        child: Text(m, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedGeminiModel = val);
              },
            ),
            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF6366F1)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    onPressed: _isTesting
                        ? null
                        : () async {
                            setState(() {
                              _isTesting = true;
                              _testResult = 'Testing selected models...';
                            });
                            final res = await AiTransactionService.instance.testConnection(
                              grokKey: _grokController.text.trim(),
                              geminiKey: _geminiController.text.trim(),
                              grokModel: _selectedGrokModel,
                              geminiModel: _selectedGeminiModel,
                            );
                            if (!mounted) return;
                            setState(() {
                              _isTesting = false;
                              if (res.isEmpty) {
                                _testResult = '⚠️ Enter at least one API key to test.';
                              } else {
                                _testResult = res.entries
                                    .map((e) => '${e.key.toUpperCase()}: ${e.value}')
                                    .join('\n');
                              }
                            });
                          },
                    icon: _isTesting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6366F1)),
                          )
                        : const Icon(Icons.bolt_rounded, size: 16, color: Color(0xFF6366F1)),
                    label: Text(
                      _isTesting ? 'Testing...' : 'Test Connection',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF6366F1), fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),

            if (_testResult != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF161A36) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _testResult!.contains('Connected') || _testResult!.contains('Loaded')
                        ? const Color(0xFF10B981)
                        : const Color(0xFF6366F1),
                    width: 1.2,
                  ),
                ),
                child: Text(
                  _testResult!,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _testResult!.contains('Connected') || _testResult!.contains('Loaded')
                        ? const Color(0xFF10B981)
                        : (_testResult!.contains('Error') || _testResult!.contains('failed')
                            ? const Color(0xFFEF4444)
                            : textPrimary),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Cancel', style: TextStyle(color: textSecondary)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF6366F1),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: () async {
            final navigator = Navigator.of(context);
            final storage = StorageService.instance;
            await storage.setGrokApiKey(_grokController.text.trim());
            await storage.setGeminiApiKey(_geminiController.text.trim());
            await storage.setSelectedGrokModel(_selectedGrokModel);
            await storage.setSelectedGeminiModel(_selectedGeminiModel);
            if (mounted) {
              navigator.pop(true);
            }
          },
          child: const Text('Save Keys'),
        ),
      ],
    );
  }
}
