import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/localization.dart';
import '../../core/theme/app_palette.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../data/providers.dart';
import '../../domain/models/coupon.dart';

/// Coupons extracted from scanned receipts, with manual actions mirroring the
/// notification buttons ("Mark as Used" / "Remind Tomorrow").
class CouponsPage extends ConsumerWidget {
  const CouponsPage({super.key});

  Future<void> _enableNotifications(BuildContext context, WidgetRef ref) async {
    final granted =
        await ref.read(couponReminderServiceProvider).enableNotifications();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: AppText(
          granted ? 'クーポンの通知を有効にしました' : '通知の許可が必要です',
        ),
      ),
    );
    if (granted) {
      await ref.read(couponReminderServiceProvider).sync();
      ref.invalidate(couponsProvider);
    }
  }

  Future<void> _markUsed(
    BuildContext context,
    WidgetRef ref,
    Coupon coupon,
  ) async {
    await ref.read(couponReminderServiceProvider).markUsed(coupon.id);
    if (!context.mounted) return;
    ref.invalidate(couponsProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: AppText('「${coupon.name}」を使用済みにしました')),
    );
  }

  Future<void> _remindTomorrow(
    BuildContext context,
    WidgetRef ref,
    Coupon coupon,
  ) async {
    await ref.read(couponReminderServiceProvider).remindTomorrow(coupon.id);
    if (!context.mounted) return;
    ref.invalidate(couponsProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: AppText('明日またお知らせします')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(couponsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const AppText('クーポン'),
        actions: <Widget>[
          IconButton(
            tooltip: context.tr('通知を有効にする'),
            onPressed: () => _enableNotifications(context, ref),
            icon: const Icon(Icons.notifications_active_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: AppText('クーポンを読み込めませんでした\n$error'),
          ),
        ),
        data: (coupons) {
          final now = DateTime.now();
          final usable = coupons
              .where((coupon) => coupon.isUsableAt(now))
              .toList(growable: false);
          final finished = coupons
              .where((coupon) => !coupon.isUsableAt(now))
              .toList(growable: false);

          return RefreshIndicator(
            onRefresh: () async {
              await ref.read(couponReminderServiceProvider).sync();
              ref.invalidate(couponsProvider);
            },
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                context.pagePadding,
                8,
                context.pagePadding,
                32,
              ),
              children: <Widget>[
                if (coupons.isEmpty)
                  const _EmptyCoupons()
                else ...<Widget>[
                  if (usable.isEmpty)
                    const AppText('有効なクーポンはありません')
                  else
                    ...usable.map(
                      (coupon) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _CouponCard(
                          coupon: coupon,
                          now: now,
                          onUsed: () => _markUsed(context, ref, coupon),
                          onRemind: () =>
                              _remindTomorrow(context, ref, coupon),
                        ),
                      ),
                    ),
                  if (finished.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 16),
                    const AppText(
                      '期限切れ・使用済み',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppPalette.textMuted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...finished.map(
                      (coupon) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _CouponCard(
                          coupon: coupon,
                          now: now,
                          onUsed: null,
                          onRemind: null,
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _EmptyCoupons extends StatelessWidget {
  const _EmptyCoupons();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppPalette.card(context, accent: AppPalette.cyan, radius: 18),
      child: Column(
        children: <Widget>[
          const Icon(Icons.confirmation_number_outlined,
              size: 40, color: AppPalette.cyan),
          const SizedBox(height: 10),
          AppText(
            'レシートにクーポンが印刷されていると、ここに自動で保存されます。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          AppText(
            '有効なクーポンは毎日お知らせします（通知の許可が必要です）。',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _CouponCard extends StatelessWidget {
  const _CouponCard({
    required this.coupon,
    required this.now,
    required this.onUsed,
    required this.onRemind,
  });

  final Coupon coupon;
  final DateTime now;
  final VoidCallback? onUsed;
  final VoidCallback? onRemind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expired = coupon.status == CouponStatus.expired ||
        coupon.isExpiredAt(now);
    final used = coupon.status == CouponStatus.used;
    final accent = used
        ? AppPalette.textFaint
        : expired
            ? AppPalette.amber
            : AppPalette.cyan;

    return Container(
      decoration: AppPalette.card(context, accent: accent, radius: 18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  used
                      ? Icons.check_circle_outline
                      : expired
                          ? Icons.event_busy_outlined
                          : Icons.confirmation_number_outlined,
                  size: 18,
                  color: accent,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: AppText(
                    coupon.name,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (coupon.discountAmountOrPercent != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: AppText(
                      coupon.discountAmountOrPercent!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            AppText(
              _subtitle(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (onUsed != null || onRemind != null) ...<Widget>[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: <Widget>[
                  if (onUsed != null)
                    FilledButton.tonalIcon(
                      onPressed: onUsed,
                      icon: const Icon(Icons.check, size: 16),
                      label: const AppText('使用済み'),
                    ),
                  if (onRemind != null)
                    OutlinedButton.icon(
                      onPressed: onRemind,
                      icon: const Icon(Icons.alarm_add_outlined, size: 16),
                      label: const AppText('明日通知'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _subtitle() {
    final parts = <String>[
      if (coupon.merchant != null && coupon.merchant!.isNotEmpty)
        coupon.merchant!,
    ];
    if (coupon.status == CouponStatus.used) {
      parts.add('使用済み');
    } else if (coupon.status == CouponStatus.expired ||
        coupon.isExpiredAt(now)) {
      parts.add('期限切れ');
    }
    final until = coupon.validUntil;
    if (until != null) {
      final days = coupon.daysUntilExpiry(now);
      final date = formatDateShortJa(until);
      if (days != null && days >= 0 && !coupon.isExpiredAt(now)) {
        parts.add(days == 0 ? '本日まで（$date）' : 'あと$days日（$date）');
      } else {
        parts.add('$date まで');
      }
    } else if (coupon.validFrom != null) {
      parts.add('${formatDateShortJa(coupon.validFrom!)} から');
    } else {
      parts.add('有効期限なし');
    }
    return parts.join(' ・ ');
  }
}
