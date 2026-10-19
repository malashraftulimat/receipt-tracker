import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/barcode_utils.dart';
import '../../core/utils/responsive.dart';
import '../../data/providers.dart';
import '../../data/services/image_input.dart';
import '../../domain/models/receipt.dart';
import '../../domain/models/receipt_draft.dart';
import '../../domain/parser/receipt_parser.dart';
import '../review/review_page.dart';
import 'scan_session.dart';

/// Live camera view with a 1D-barcode engine and a receipt-OCR engine.
class ScanPage extends ConsumerStatefulWidget {
  const ScanPage({super.key});

  @override
  ConsumerState<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends ConsumerState<ScanPage> {
  MobileScannerController? _scanner;
  bool _processing = false;
  bool _navigating = false;
  String? _error;

  /// Live preview works on Android/iOS **and** in the browser
  /// (mobile_scanner's web implementation uses ZXing + getUserMedia).
  /// Windows/macOS/Linux still fall back to image picking.
  bool get _hasLiveCamera =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    if (_hasLiveCamera) {
      _scanner = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        facing: CameraFacing.back,
        formats: const <BarcodeFormat>[
          BarcodeFormat.ean13,
          BarcodeFormat.ean8,
          BarcodeFormat.upcA,
          BarcodeFormat.code128,
          BarcodeFormat.code39,
          BarcodeFormat.itf,
        ],
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startScanner();
      });
    }
  }

  @override
  void dispose() {
    _scanner?.dispose();
    super.dispose();
  }

  Future<void> _startScanner() async {
    try {
      await _scanner?.start();
    } catch (_) {
      // Camera permission denied / already running — ignore.
    }
  }

  Future<void> _stopScanner() async {
    try {
      await _scanner?.stop();
    } catch (_) {
      // ignore
    }
  }

  Future<void> _toggleTorch() async {
    try {
      await _scanner?.toggleTorch();
    } catch (_) {
      // ignore
    }
  }

  // -------------------------------------------------------------------------
  // Barcode engine
  // -------------------------------------------------------------------------

  void _onDetect(BarcodeCapture capture) {
    if (_processing || _navigating) return;
    if (ref.read(scanSessionProvider).mode == ScanMode.ocr) return;

    String? value;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue?.trim();
      if (raw != null && raw.isNotEmpty) {
        value = raw;
        break;
      }
    }
    if (value == null) return;

    HapticFeedback.mediumImpact();
    final session = ref.read(scanSessionProvider.notifier);
    session.setBarcode(value);

    if (ref.read(scanSessionProvider).mode == ScanMode.barcode) {
      _openReview(
        ReceiptDraft(barcodeId: value, source: ReceiptSource.barcode),
        null,
      );
    }
  }

  // -------------------------------------------------------------------------
  // OCR engine
  // -------------------------------------------------------------------------

  Future<void> _captureAndRecognize() async {
    if (_processing || _navigating) return;

    setState(() {
      _processing = true;
      _error = null;
    });
    await _stopScanner();

    try {
      final file = await ImageInput.pickReceiptImage();
      if (file == null) return;

      final bytes = await file.readAsBytes();
      final barcode = ref.read(scanSessionProvider).barcode;
      final result = await ref.read(ocrServiceProvider).recognize(bytes);
      final parsed = const ReceiptParser().parse(
        result.text,
        scannedBarcode: barcode,
      );

      final draft = ReceiptDraft.fromParsed(
        parsed,
        barcodeId: barcode,
        source: barcode == null ? ReceiptSource.ocr : ReceiptSource.barcode,
      );

      if (!mounted) return;
      setState(() => _processing = false);
      await _openReview(draft, bytes, parsed: parsed);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted && _processing) setState(() => _processing = false);
    }
  }

  Future<void> _openReview(
    ReceiptDraft draft,
    Uint8List? imageBytes, {
    ParsedReceipt? parsed,
  }) async {
    if (_navigating) return;
    setState(() => _navigating = true);
    await _stopScanner();
    if (!mounted) return;

    final saved = await context.push<Receipt>(
      '/review',
      extra: ReviewArgs(
        draft: draft,
        imageBytes: imageBytes,
        parsed: parsed,
      ),
    );

    if (!mounted) return;
    if (saved != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('「${saved.displayMerchant}」を保存しました'),
        ),
      );
      if (context.canPop()) context.pop();
      return;
    }

    setState(() => _navigating = false);
    await _startScanner();
  }

  Future<void> _openManual() => _openReview(
        ReceiptDraft(source: ReceiptSource.manual),
        null,
      );

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(scanSessionProvider);
    final notifier = ref.read(scanSessionProvider.notifier);

    if (!_hasLiveCamera) {
      return Scaffold(
        appBar: AppBar(title: const Text('スキャン')),
        body: _NoCameraView(
          onPickImage: _captureAndRecognize,
          onManual: _openManual,
          busy: _processing,
          error: _error,
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('スキャン'),
        actions: <Widget>[
          IconButton(
            tooltip: 'ライト',
            onPressed: _toggleTorch,
            icon: const Icon(Icons.flashlight_on_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                MobileScanner(
                  controller: _scanner!,
                  onDetect: _onDetect,
                ),
                const IgnorePointer(child: _ScanFrame()),
                if (_processing) const _ProcessingOverlay(),
              ],
            ),
          ),
          Theme(
            data: AppTheme.dark,
            child: Container(
              color: Colors.black,
              padding: EdgeInsets.fromLTRB(
                context.pagePadding,
                14,
                context.pagePadding,
                20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SegmentedButton<ScanMode>(
                    segments: <ButtonSegment<ScanMode>>[
                      for (final mode in ScanMode.values)
                        ButtonSegment<ScanMode>(
                          value: mode,
                          label: Text(mode.label),
                        ),
                    ],
                    selected: <ScanMode>{session.mode},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) =>
                        notifier.setMode(selection.first),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    session.mode.hint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  if (session.barcode != null) ...<Widget>[
                    const SizedBox(height: 12),
                    _BarcodeBanner(
                      barcode: session.barcode!,
                      onClear: notifier.clearBarcode,
                    ),
                  ],
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: 12),
                    _ErrorBanner(message: _error!),
                  ],
                  const SizedBox(height: 14),
                  _ActionButtons(
                    mode: session.mode,
                    hasBarcode: session.barcode != null,
                    busy: _processing,
                    onCapture: _captureAndRecognize,
                    onManual: _openManual,
                    onUseBarcodeOnly: () {
                      final barcode = session.barcode;
                      if (barcode == null) return;
                      _openReview(
                        ReceiptDraft(
                          barcodeId: barcode,
                          source: ReceiptSource.barcode,
                        ),
                        null,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({
    required this.mode,
    required this.hasBarcode,
    required this.busy,
    required this.onCapture,
    required this.onManual,
    required this.onUseBarcodeOnly,
  });

  final ScanMode mode;
  final bool hasBarcode;
  final bool busy;
  final VoidCallback onCapture;
  final VoidCallback onManual;
  final VoidCallback onUseBarcodeOnly;

  @override
  Widget build(BuildContext context) {
    if (mode == ScanMode.barcode && !hasBarcode) {
      return Row(
        children: <Widget>[
          Expanded(
            child: OutlinedButton.icon(
              onPressed: busy ? null : onCapture,
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('レシートを撮影'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: busy ? null : onManual,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('手入力'),
            ),
          ),
        ],
      );
    }

    return Column(
      children: <Widget>[
        if (mode == ScanMode.auto && hasBarcode) ...<Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy ? null : onCapture,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('撮影して自動入力'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: busy ? null : onUseBarcodeOnly,
                child: const Text('このまま登録'),
              ),
            ],
          ),
        ] else
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: busy ? null : onCapture,
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(
                mode == ScanMode.barcode ? 'レシートを撮影' : 'レシートを撮影して読み取る',
              ),
            ),
          ),
        if (mode != ScanMode.barcode) ...<Widget>[
          const SizedBox(height: 8),
          TextButton(
            onPressed: busy ? null : onManual,
            child: const Text('手入力で登録する'),
          ),
        ],
      ],
    );
  }
}

class _BarcodeBanner extends StatelessWidget {
  const _BarcodeBanner({required this.barcode, required this.onClear});

  final String barcode;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final valid = BarcodeUtils.looksLikeJan(barcode)
        ? BarcodeUtils.isValidEan13(barcode)
        : true;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            valid ? Icons.qr_code_2 : Icons.warning_amber_outlined,
            color: valid ? Colors.greenAccent : Colors.orangeAccent,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  valid ? 'バーコード検出' : 'バーコード（チェックディジット不一致）',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
                Text(
                  BarcodeUtils.format(barcode),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'クリア',
            onPressed: onClear,
            icon: const Icon(Icons.close, color: Colors.white70, size: 18),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rounded guide frame for the barcode / receipt.
class _ScanFrame extends StatelessWidget {
  const _ScanFrame();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth * 0.8).clamp(220.0, 420.0).toDouble();
        final height =
            (constraints.maxHeight * 0.55).clamp(160.0, 320.0).toDouble();
        return Center(
          child: CustomPaint(
            painter: _CornerPainter(Colors.white.withValues(alpha: 0.85)),
            child: SizedBox(width: width, height: height),
          ),
        );
      },
    );
  }
}

class _CornerPainter extends CustomPainter {
  const _CornerPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const arm = 26.0;
    final paths = <Path>[
      Path()
        ..moveTo(0, arm)
        ..lineTo(0, 0)
        ..lineTo(arm, 0),
      Path()
        ..moveTo(size.width - arm, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width, arm),
      Path()
        ..moveTo(size.width, size.height - arm)
        ..lineTo(size.width, size.height)
        ..lineTo(size.width - arm, size.height),
      Path()
        ..moveTo(arm, size.height)
        ..lineTo(0, size.height)
        ..lineTo(0, size.height - arm),
    ];
    for (final path in paths) {
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CornerPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ProcessingOverlay extends StatelessWidget {
  const _ProcessingOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 14),
            Text(
              'レシートを解析しています…',
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoCameraView extends StatelessWidget {
  const _NoCameraView({
    required this.onPickImage,
    required this.onManual,
    required this.busy,
    this.error,
  });

  final VoidCallback onPickImage;
  final VoidCallback onManual;
  final bool busy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(context.pagePadding * 1.5),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.no_photography_outlined,
                size: 52,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                'このデバイスではライブカメラを利用できません',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'レシート画像を選択すると、サーバーOCR（Supabase Edge Function）で'
                '店舗名・日付・合計・消費税を自動入力します。'
                'ブラウザではカメラ非対応のため、スマートフォンで撮影した画像を選択してください。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (error != null) ...<Widget>[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    error!,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: busy ? null : onPickImage,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.photo_library_outlined),
                label: Text(busy ? '解析中…' : '画像を選択してOCR'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: busy ? null : onManual,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('手入力で登録'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
