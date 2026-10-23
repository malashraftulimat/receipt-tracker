import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/app_palette.dart';
import '../../core/utils/redaction.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/language_switcher.dart';
import '../../core/widgets/press_scale.dart';
import '../../core/utils/barcode_utils.dart';
import '../../core/utils/responsive.dart';
import '../../data/providers.dart';
import '../../data/services/camera/camera_frame.dart';
import '../../data/services/image_input.dart';
import '../../data/services/ocr/ai_receipt_ocr_service.dart';
import '../../domain/models/receipt.dart';
import '../../domain/models/receipt_draft.dart';
import '../../domain/parser/receipt_parser.dart';
import '../../domain/parser/receipt_text_merger.dart';
import '../review/review_page.dart';
import 'scan_session.dart';
import '../../core/localization/localization.dart';

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
  bool _cameraBlocked = false;
  String? _cameraError;
  final List<String> _chunkTexts = <String>[];
  final List<Uint8List> _chunkImages = <Uint8List>[];
  String? _error;
  AiReceiptOcrException? _aiFailure;
  String _processingLabel = 'scan.ai_analyzing';
  double? _focusX;
  double? _focusY;
  int _focusRingId = 0;

  /// Android / iOS use the native ML Kit camera pipeline, while the web build
  /// uses `mobile_scanner`'s HTML5/WebRTC implementation (getUserMedia + ZXing).
  /// Both feed the same barcode + OCR UI.
  bool get _hasLiveCamera =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    if (_hasLiveCamera) {
      _installWebBarcodeLibrary();
      _scanner = _createScanner();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startScanner();
      });
    }
  }

  @override
  void dispose() {
    _scanner?.removeListener(_handleScannerState);
    _scanner?.dispose();
    // Captured chunks live in memory only; drop them when leaving the scanner.
    _chunkTexts.clear();
    _chunkImages.clear();
    super.dispose();
  }

  /// Serve ZXing from the app bundle (web/zxing.min.js) rather than unpkg, so
  /// barcode detection keeps working on GitHub Pages without an extra CDN hop.
  void _installWebBarcodeLibrary() {
    if (!kIsWeb) return;
    MobileScannerPlatform.instance.setBarcodeLibraryScriptUrl(
      Uri.base.resolve('zxing.min.js').toString(),
    );
  }

  MobileScannerController _createScanner() {
    final controller = MobileScannerController(
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
    controller.addListener(_handleScannerState);
    return controller;
  }

  /// Permission / unsupported errors are the only cases where we replace the
  /// live preview with the image-upload fallback.
  void _handleScannerState() {
    final scanner = _scanner;
    if (scanner == null || !mounted) return;

    final state = scanner.value;
    final error = state.error;
    if (error == null) {
      if (_cameraBlocked && state.isRunning) {
        setState(() {
          _cameraBlocked = false;
          _cameraError = null;
        });
      }
      return;
    }

    final blocked =
        error.errorCode == MobileScannerErrorCode.permissionDenied ||
            error.errorCode == MobileScannerErrorCode.unsupported;
    if (!blocked || _cameraBlocked) return;

    setState(() {
      _cameraBlocked = true;
      _cameraError = switch (error.errorCode) {
        MobileScannerErrorCode.permissionDenied =>
          'scan.camera_denied_body',
        MobileScannerErrorCode.unsupported => 'scan.camera_unavailable_body',
        _ => error.errorDetails?.message ?? 'scan.camera_start_failed',
      };
    });
  }

  Future<void> _retryCamera() async {
    final old = _scanner;
    old?.removeListener(_handleScannerState);
    await old?.dispose();
    if (!mounted) return;

    final controller = _createScanner();
    setState(() {
      _scanner = controller;
      _cameraBlocked = false;
      _cameraError = null;
    });
    await _startScanner();
  }

  Future<void> _startScanner() async {
    try {
      await _scanner?.start();
      await _prepareWebCamera();
    } catch (_) {
      // Permission denied / already running: the state listener handles UI.
    }
  }

  /// Applies the highest practical resolution and continuous autofocus to the
  /// MediaStreamTrack behind mobile_scanner's web <video> element.
  Future<void> _prepareWebCamera() async {
    if (!kIsWeb) return;
    try {
      await CameraFrame.prepareForCapture();
    } catch (_) {
      // Focus tuning is best-effort and must never stop scanning.
    }
  }

  Future<void> _focusPreview(TapDownDetails details, Size size) async {
    if (!kIsWeb || size.width <= 0 || size.height <= 0) return;
    final x = details.localPosition.dx / size.width;
    final y = details.localPosition.dy / size.height;
    setState(() {
      _focusX = x.clamp(0.0, 1.0);
      _focusY = y.clamp(0.0, 1.0);
      _focusRingId += 1;
    });
    await CameraFrame.focusAt(x, y);
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

  /// Gets the still image used for OCR.
  ///
  /// Web: captures the current frame from the same live camera stream.
  /// Android/iOS: uses the native camera via `image_picker` (ML Kit input).
  /// If no frame is available, both platforms fall back to the photo picker.
  Future<Uint8List?> _acquireImageBytes() async {
    if (kIsWeb) {
      final frame = await CameraFrame.capture();
      if (frame != null) {
        // The frame is in memory, so the camera can be released during OCR.
        await _stopScanner();
        return frame;
      }
    }

    await _stopScanner();
    final file = await ImageInput.pickReceiptImage();
    if (file == null) return null;
    return file.readAsBytes();
  }

  Future<void> _restartScannerIfNeeded() async {
    if (!_hasLiveCamera || _cameraBlocked || _navigating) return;
    await _startScanner();
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
      _processingLabel = 'scan.ai_analyzing';
      _error = null;
      _aiFailure = null;
    });

    try {
      final bytes = await _acquireImageBytes();
      if (bytes == null) {
        if (mounted) setState(() => _processing = false);
        await _restartScannerIfNeeded();
        return;
      }
      await _recognizeAndReview(bytes);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      await _restartScannerIfNeeded();
    } finally {
      if (mounted && _processing) setState(() => _processing = false);
    }
  }

  /// iOS Safari path: native camera via <input type=file capture=environment>.
  Future<void> _captureWithDeviceCamera() async {
    if (_processing || _navigating) return;

    setState(() {
      _processing = true;
      _processingLabel = 'scan.ai_analyzing';
      _error = null;
      _aiFailure = null;
    });

    try {
      final bytes = await CameraFrame.pickFromDeviceCamera();
      if (bytes == null) {
        if (mounted) setState(() => _processing = false);
        return;
      }
      await _stopScanner();
      await _recognizeAndReview(bytes);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      await _restartScannerIfNeeded();
    } finally {
      if (mounted && _processing) setState(() => _processing = false);
    }
  }

  Future<void> _recognizeAndReview(Uint8List bytes) async {
    final barcode = ref.read(scanSessionProvider).barcode;
    final result = await ref.read(receiptOcrPipelineProvider).recognize(
      bytes,
      barcodeId: barcode,
      onFallback: (aiError) {
        if (!mounted) return;
        setState(() {
          _processingLabel = 'scan.analyzing_fallback';
          _aiFailure = aiError is AiReceiptOcrException ? aiError : null;
        });
      },
    );
    final parsed = result.parsed;

    final draft = ReceiptDraft.fromParsed(
      parsed,
      barcodeId: barcode,
      source: barcode == null ? ReceiptSource.ocr : ReceiptSource.barcode,
    );

    if (!mounted) return;
    setState(() {
      _processing = false;
      _aiFailure =
          result.usedFallback ? (result.aiFailure ?? _aiFailure) : null;
    });
    if (result.usedFallback) {
      final failure = result.aiFailure;
      final message = result.aiDailyLimitReached
          ? (failure?.message ?? AiReceiptOcrService.dailyLimitMessage)
          : result.aiKeyMissing
              ? 'AI key missing — using on-device OCR.'
              : result.aiServiceUnavailable
                  ? 'the_ai_service_is_getting_ready_please_try_a'
                  : 'ai_was_unavailable_so_the_receipt_was_read_w';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: AppText(message)),
      );
    }
    await _openReview(draft, bytes, parsed: parsed);
  }

  // -------------------------------------------------------------------------
  // Long receipt: capture overlapping chunks and merge the OCR text
  // -------------------------------------------------------------------------

  Future<void> _captureChunk() async {
    if (_processing || _navigating) return;

    setState(() {
      _processing = true;
      _processingLabel = 'scan.ondevice_analyzing';
      _error = null;
    });

    try {
      final bytes = await _acquireImageBytes();
      if (bytes == null) return;

      final result = await ref.read(ocrServiceProvider).recognize(bytes);
      if (!mounted) return;

      setState(() {
        _chunkTexts.add(result.text);
        _chunkImages.add(bytes);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText('${_chunkTexts.length} 枚目を読み取りました。続きを撮影してください'),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _processing = false);
        await _startScanner();
      }
    }
  }

  void _clearChunks() {
    if (_chunkTexts.isEmpty && _chunkImages.isEmpty) return;
    setState(() {
      _chunkTexts.clear();
      _chunkImages.clear();
    });
  }

  Future<void> _mergeChunks() async {
    if (_chunkTexts.isEmpty || _processing || _navigating) return;

    final merged = const ReceiptTextMerger().merge(_chunkTexts);
    final barcode = ref.read(scanSessionProvider).barcode;
    final parsed = const ReceiptParser().parse(
      merged,
      scannedBarcode: barcode,
    );
    final draft = ReceiptDraft.fromParsed(
      parsed,
      barcodeId: barcode,
      source: barcode == null ? ReceiptSource.ocr : ReceiptSource.barcode,
    );
    final cover = _chunkImages.isEmpty ? null : _chunkImages.first;

    _clearChunks();
    await _openReview(draft, cover, parsed: parsed);
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
          content: AppText('「${saved.displayMerchant}」を保存しました'),
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

  /// Quick entry for an expense without a receipt (rent, transfers, ...).
  /// Uses the same receipts collection with `source = manual`.
  Future<void> _openQuickPayment() async {
    if (_navigating) return;
    setState(() => _navigating = true);
    await _stopScanner();
    if (!mounted) return;

    await context.push<Receipt>('/payment/new');

    if (!mounted) return;
    setState(() => _navigating = false);
    await _restartScannerIfNeeded();
  }

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(scanSessionProvider);
    final notifier = ref.read(scanSessionProvider.notifier);

    if (!_hasLiveCamera || _cameraBlocked) {
      return Scaffold(
        appBar: AppBar(
          title: const AppText('scan'),
          actions: headerActions(
            context,
            showLanguageLabel: context.isExpanded,
          ),
        ),
        body: _NoCameraView(
          onPickImage: _captureAndRecognize,
          onManual: _openManual,
          onQuickPayment: _openQuickPayment,
          onDeviceCamera: kIsWeb ? _captureWithDeviceCamera : null,
          busy: _processing,
          error: _cameraError ?? _error,
          cameraDenied: _cameraBlocked,
          canRetryCamera: _hasLiveCamera,
          onRetryCamera: _retryCamera,
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppPalette.backgroundDeep,
      appBar: AppBar(
        backgroundColor: AppPalette.backgroundDeep,
        foregroundColor: AppPalette.text,
        title: const AppText('scan'),
        actions: headerActions(
          context,
          showLanguageLabel: context.isExpanded,
          actions: <Widget>[
            IconButton(
              tooltip: context.tr('add_payment'),
              onPressed: _processing ? null : _openQuickPayment,
              icon: const Icon(Icons.add_card_outlined),
            ),
            if (!kIsWeb)
              IconButton(
                tooltip: context.tr('light'),
                onPressed: _toggleTorch,
                icon: const Icon(Icons.flashlight_on_outlined),
              ),
          ],
        ),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = constraints.biggest;
                return Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) => _focusPreview(details, size),
                      child: MobileScanner(
                        controller: _scanner!,
                        onDetect: _onDetect,
                      ),
                    ),
                    const IgnorePointer(child: _ScanFrame()),
                    if (_focusX != null && _focusY != null)
                      Positioned(
                        left: _focusX! * size.width - 36,
                        top: _focusY! * size.height - 36,
                        child: IgnorePointer(
                          child: _TapFocusRing(
                            key: ValueKey<int>(_focusRingId),
                          ),
                        ),
                      ),
                    if (_processing)
                      _ProcessingOverlay(
                        label: _processingLabel,
                        failure: _aiFailure,
                      ),
                  ],
                );
              },
            ),
          ),
          Theme(
            data: AppTheme.dark,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                context.pagePadding,
                14,
                context.pagePadding,
                20,
              ),
              decoration: BoxDecoration(
                color: AppPalette.background,
                border: Border(
                  top: BorderSide(
                    color: AppPalette.cyan.withValues(alpha: 0.35),
                  ),
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: AppPalette.cyan.withValues(alpha: 0.1),
                    blurRadius: 24,
                    offset: const Offset(0, -8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SegmentedButton<ScanMode>(
                    segments: <ButtonSegment<ScanMode>>[
                      for (final mode in ScanMode.values)
                        ButtonSegment<ScanMode>(
                          value: mode,
                          label: AppText(mode.label),
                        ),
                    ],
                    selected: <ScanMode>{session.mode},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) =>
                        notifier.setMode(selection.first),
                  ),
                  const SizedBox(height: 10),
                  AppText(
                    session.mode.hint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppPalette.textMuted,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const AppText(
                    'the_photo_is_sent_to_google_s_gemini_api_for',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppPalette.textFaint,
                      fontSize: 10.5,
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
                  if (_aiFailure != null) ...<Widget>[
                    const SizedBox(height: 10),
                    if (_aiFailure!.kind == AiReceiptFailureKind.missingKey)
                      _AiNoticeCard(
                        icon: Icons.key_off_outlined,
                        color: AppPalette.cyan,
                        title: 'scan.ai_key_missing_title',
                        message:
                            'scan.ai_key_missing_body',
                        onOpenSettings: () => context.push('/settings'),
                      )
                    else if (_aiFailure!.kind ==
                        AiReceiptFailureKind.dailyLimit)
                      _AiNoticeCard(
                        icon: Icons.hourglass_bottom_outlined,
                        color: AppPalette.amber,
                        title: 'scan.ai_daily_limit_title',
                        message: _aiFailure!.message,
                        onOpenSettings: () => context.push('/settings'),
                      )
                    else
                      _AiDiagnosticLine(failure: _aiFailure!),
                  ],
                  const SizedBox(height: 14),
                  if (session.mode == ScanMode.longReceipt)
                    _LongReceiptControls(
                      chunkCount: _chunkTexts.length,
                      busy: _processing,
                      onAdd: _captureChunk,
                      onMerge: _mergeChunks,
                      onClear: _clearChunks,
                    )
                  else
                    _ActionButtons(
                      mode: session.mode,
                      hasBarcode: session.barcode != null,
                      busy: _processing,
                      onCapture: _captureAndRecognize,
                      onManual: _openManual,
                      onQuickPayment: _openQuickPayment,
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
                  if (kIsWeb) ...<Widget>[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _processing ? null : _captureWithDeviceCamera,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppPalette.cyan,
                        side: BorderSide(
                          color: AppPalette.cyan.withValues(alpha: 0.55),
                        ),
                      ),
                      icon: const Icon(Icons.phone_iphone),
                      label: const AppText('use_device_camera'),
                    ),
                  ],
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
    required this.onQuickPayment,
    required this.onUseBarcodeOnly,
  });

  final ScanMode mode;
  final bool hasBarcode;
  final bool busy;
  final VoidCallback onCapture;
  final VoidCallback onManual;
  final VoidCallback onQuickPayment;
  final VoidCallback onUseBarcodeOnly;

  @override
  Widget build(BuildContext context) {
    if (mode == ScanMode.barcode && !hasBarcode) {
      return Row(
        children: <Widget>[
          Expanded(
            child: PressScale(
              child: FilledButton.icon(
                onPressed: busy ? null : onCapture,
                style: FilledButton.styleFrom(
                  backgroundColor: AppPalette.cyan,
                  foregroundColor: AppPalette.backgroundDeep,
                ),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const AppText('capture_receipt'),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: busy ? null : onManual,
              icon: const Icon(Icons.edit_outlined),
              label: const AppText('manual_entry'),
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
                child: PressScale(
                  child: FilledButton.icon(
                    onPressed: busy ? null : onCapture,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppPalette.cyan,
                      foregroundColor: AppPalette.backgroundDeep,
                    ),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const AppText('capture_and_auto_fill_2'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: busy ? null : onUseBarcodeOnly,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppPalette.emerald,
                  side: BorderSide(
                    color: AppPalette.emerald.withValues(alpha: 0.5),
                  ),
                ),
                child: const AppText('save_this_barcode'),
              ),
            ],
          ),
        ] else
          SizedBox(
            width: double.infinity,
            child: PressScale(
              child: FilledButton.icon(
                onPressed: busy ? null : onCapture,
                style: FilledButton.styleFrom(
                  backgroundColor: AppPalette.cyan,
                  foregroundColor: AppPalette.backgroundDeep,
                  minimumSize: const Size(0, 52),
                ),
                icon: const Icon(Icons.photo_camera_outlined),
                label: AppText(
                  mode == ScanMode.barcode ? 'capture_receipt' : 'capture_and_read_receipt',
                ),
              ),
            ),
          ),
        if (mode != ScanMode.barcode) ...<Widget>[
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 4,
            children: <Widget>[
              TextButton(
                onPressed: busy ? null : onManual,
                child: const AppText('enter_manually_2'),
              ),
              TextButton.icon(
                onPressed: busy ? null : onQuickPayment,
                icon: const Icon(Icons.add_card_outlined, size: 16),
                label: const AppText('record_a_payment_only'),
              ),
            ],
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

    final accent = valid ? AppPalette.emerald : AppPalette.amber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppPalette.surfaceAlt.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            valid ? Icons.qr_code_2 : Icons.warning_amber_outlined,
            color: accent,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                AppText(
                  valid ? 'barcode_detected' : 'barcode_check_digit_mismatch',
                  style: const TextStyle(
                    color: AppPalette.textMuted,
                    fontSize: 11,
                  ),
                ),
                AppText(
                  BarcodeUtils.format(barcode),
                  style: const TextStyle(
                    color: AppPalette.text,
                    fontSize: 14,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: context.tr('clear'),
            onPressed: onClear,
            icon: const Icon(
              Icons.close,
              color: AppPalette.textMuted,
              size: 18,
            ),
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
        color: AppPalette.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppPalette.danger.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.error_outline,
            color: AppPalette.danger,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AppText(
              message,
              style: const TextStyle(
                color: AppPalette.text,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Friendly, actionable card shown instead of raw diagnostics.
class _AiNoticeCard extends StatelessWidget {
  const _AiNoticeCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.color,
    required this.onOpenSettings,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color color;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: AppText(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          AppText(
            message,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onOpenSettings,
            icon: const Icon(Icons.settings_outlined, size: 18),
            label: const AppText('scan.open_settings'),
          ),
        ],
      ),
    );
  }
}

/// Rounded guide frame for the barcode / receipt.
class _AiDiagnosticLine extends StatelessWidget {
  const _AiDiagnosticLine({required this.failure});

  final AiReceiptOcrException failure;

  @override
  Widget build(BuildContext context) {
    final raw = failure.diagnostics ??
        redactSensitiveText(failure.cause?.toString() ?? failure.toString());
    final runtimeType = failure.cause?.runtimeType.toString() ?? '-';

    return Container(
      decoration: BoxDecoration(
        color: AppPalette.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppPalette.amber.withValues(alpha: 0.35),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          dense: true,
          leading: const Icon(
            Icons.bug_report_outlined,
            size: 18,
            color: AppPalette.amber,
          ),
          title: const AppText(
            'ai_error_details',
            style: TextStyle(
              color: AppPalette.amber,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            '${failure.kind.name}'
            '${failure.modelName == null ? '' : ' · ${failure.modelName}'}',
            style: const TextStyle(
              color: AppPalette.textMuted,
              fontSize: 10.5,
            ),
          ),
          children: <Widget>[
            SelectableText(
              'kind: ${failure.kind.name}\n'
              'model: ${failure.modelName ?? '-'}\n'
              'message: ${failure.message}\n'
              'runtimeType: $runtimeType\n'
              'raw: $raw',
              style: const TextStyle(
                color: AppPalette.textMuted,
                fontFamily: 'monospace',
                fontSize: 10.5,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanFrame extends StatelessWidget {
  const _ScanFrame();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            (constraints.maxWidth * 0.8).clamp(220.0, 420.0).toDouble();
        final height =
            (constraints.maxHeight * 0.55).clamp(160.0, 320.0).toDouble();
        return Center(
          child: CustomPaint(
            painter: _CornerPainter(
              AppPalette.cyan.withValues(alpha: 0.9),
            ),
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

class _TapFocusRing extends StatefulWidget {
  const _TapFocusRing({super.key});

  @override
  State<_TapFocusRing> createState() => _TapFocusRingState();
}

class _TapFocusRingState extends State<_TapFocusRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = _controller.value;
        return Opacity(
          opacity: (1 - progress).clamp(0.0, 1.0),
          child: Transform.scale(scale: 1 + progress * 0.45, child: child),
        );
      },
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppPalette.cyan, width: 2),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: AppPalette.cyan.withValues(alpha: 0.35),
              blurRadius: 12,
            ),
          ],
        ),
        child: const Center(
          child: SizedBox(
            width: 8,
            height: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppPalette.cyan,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProcessingOverlay extends StatelessWidget {
  const _ProcessingOverlay({required this.label, this.failure});

  final String label;
  final AiReceiptOcrException? failure;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppPalette.backgroundDeep.withValues(alpha: 0.78),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const CircularProgressIndicator(color: AppPalette.cyan),
                const SizedBox(height: 14),
                AppText(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppPalette.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (failure != null) ...<Widget>[
                  const SizedBox(height: 14),
                  _AiDiagnosticLine(failure: failure!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoCameraView extends StatelessWidget {
  const _NoCameraView({
    required this.onPickImage,
    required this.onManual,
    required this.onQuickPayment,
    required this.busy,
    this.onDeviceCamera,
    this.error,
    this.cameraDenied = false,
    this.canRetryCamera = false,
    this.onRetryCamera,
  });

  final VoidCallback onPickImage;
  final VoidCallback onManual;
  final VoidCallback onQuickPayment;
  final VoidCallback? onDeviceCamera;
  final bool busy;
  final String? error;
  final bool cameraDenied;
  final bool canRetryCamera;
  final VoidCallback? onRetryCamera;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title =
        cameraDenied ? 'scan.camera_permission_title' : 'scan.camera_unavailable_title';
    final description = cameraDenied
        ? 'ブラウザまたは端末の設定でこのサイトのカメラ利用を許可し、'
            '「カメラを再試行」を押してください。'
            'if_you_cannot_allow_it_you_can_still_choose'
        : 'scan.no_camera_ocr_help';

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(context.pagePadding * 1.5),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                cameraDenied
                    ? Icons.no_photography_outlined
                    : Icons.camera_alt_outlined,
                size: 52,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 16),
              AppText(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              AppText(
                description,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              const AppText(
                'the_photo_is_sent_to_google_s_gemini_api_for',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, height: 1.4),
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
                  child: AppText(
                    error!,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              if (canRetryCamera && onRetryCamera != null) ...<Widget>[
                FilledButton.tonalIcon(
                  onPressed: busy ? null : onRetryCamera,
                  icon: const Icon(Icons.refresh),
                  label: const AppText('retry_camera'),
                ),
                const SizedBox(height: 8),
              ],
              FilledButton.icon(
                onPressed: busy ? null : onPickImage,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.photo_library_outlined),
                label: AppText(busy ? 'analysing' : 'choose_an_image_for_ocr'),
              ),
              if (onDeviceCamera != null) ...<Widget>[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: busy ? null : onDeviceCamera,
                  icon: const Icon(Icons.phone_iphone),
                  label: const AppText('use_device_camera'),
                ),
              ],
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: busy ? null : onManual,
                icon: const Icon(Icons.edit_outlined),
                label: const AppText('enter_manually'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: busy ? null : onQuickPayment,
                icon: const Icon(Icons.add_card_outlined),
                label: const AppText('record_a_payment_only'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LongReceiptControls extends StatelessWidget {
  const _LongReceiptControls({
    required this.chunkCount,
    required this.busy,
    required this.onAdd,
    required this.onMerge,
    required this.onClear,
  });

  final int chunkCount;
  final bool busy;
  final VoidCallback onAdd;
  final VoidCallback onMerge;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            const Icon(Icons.receipt_long, color: AppPalette.cyan, size: 18),
            const SizedBox(width: 8),
            AppText(
              '取り込み済み: $chunkCount 枚',
              style: const TextStyle(
                color: AppPalette.text,
                fontSize: 13,
              ),
            ),
            const Spacer(),
            if (chunkCount > 0)
              TextButton(
                onPressed: busy ? null : onClear,
                child: const AppText('clear'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.icon(
                onPressed: busy ? null : onAdd,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: AppText(
                  busy ? 'reading' : (chunkCount == 0 ? 'capture_first_part' : 'capture_next_part'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: busy || chunkCount == 0 ? null : onMerge,
              child: const AppText('merge_and_review'),
            ),
          ],
        ),
      ],
    );
  }
}
