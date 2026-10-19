const fs = require('fs');

// ---------------------------------------------------------------- detail card
let p = 'lib/features/receipts/receipt_detail_page.dart';
let s = fs.readFileSync(p, 'utf8');

const itemsCard = [
  '              if (receipt.items.isNotEmpty) ...<Widget>[',
  '                const SizedBox(height: 14),',
  '                _InfoCard(',
  "                  title: '明細（商品）',",
  '                  children: <Widget>[',
  '                    for (final item in receipt.items)',
  '                      _ItemRow(item: item),',
  '                  ],',
  '                ),',
  '              ],',
  '              if (receipt.dueDate != null) ...<Widget>[',
].join('\n');

s = s.replace(
  '              if (receipt.dueDate != null) ...<Widget>[',
  itemsCard,
);

const itemRow = [
  'class _ItemRow extends StatelessWidget {',
  '  const _ItemRow({required this.item});',
  '',
  '  final ReceiptItem item;',
  '',
  '  @override',
  '  Widget build(BuildContext context) {',
  '    final theme = Theme.of(context);',
  '    final taxColor = item.taxRate == 8',
  '        ? const Color(0xFF2E7D32)',
  '        : theme.colorScheme.primary;',
  '',
  '    return Padding(',
  '      padding: const EdgeInsets.symmetric(vertical: 4),',
  '      child: Row(',
  '        children: <Widget>[',
  '          Expanded(',
  '            child: Column(',
  '              crossAxisAlignment: CrossAxisAlignment.start,',
  '              children: <Widget>[',
  '                Text(',
  '                  item.name,',
  '                  style: theme.textTheme.bodySmall?.copyWith(',
  '                    fontWeight: FontWeight.w600,',
  '                  ),',
  '                ),',
  '                Text(',
  "                  '\\\\${item.quantity} × \\\\${formatYen(item.effectiveUnitPrice)}'",
  '                  '\\${item.taxRate == null ? \\'\\' : \\' ・ \\${item.taxRate}%\\'}',',
  '                  style: theme.textTheme.labelSmall?.copyWith(',
  '                    color: theme.colorScheme.onSurfaceVariant,',
  '                  ),',
  '                ),',
  '              ],',
  '            ),',
  '          ),',
  '          if (item.taxRate != null)',
  '            Container(',
  '              margin: const EdgeInsets.only(right: 8),',
  '              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),',
  '              decoration: BoxDecoration(',
  '                color: taxColor.withValues(alpha: 0.14),',
  '                borderRadius: BorderRadius.circular(6),',
  '              ),',
  '              child: Text(',
  "                '\\\\${item.taxRate}%',",
  '                style: TextStyle(',
  '                  fontSize: 10,',
  '                  fontWeight: FontWeight.w700,',
  '                  color: taxColor,',
  '                ),',
  '              ),',
  '            ),',
  '          Text(',
  '            formatYen(item.totalPrice),',
  '            style: theme.textTheme.bodySmall?.copyWith(',
  '              fontWeight: FontWeight.w700,',
  '            ),',
  '          ),',
  '        ],',
  '      ),',
  '    );',
  '  }',
  '}',
  '',
  'class _DueDateRow extends StatelessWidget {',
].join('\n');

s = s.replace('class _DueDateRow extends StatelessWidget {', itemRow);

// import ReceiptItem
s = s.replace(
  "import '../../domain/models/receipt.dart';",
  "import '../../domain/models/receipt.dart';\nimport '../../domain/models/receipt_item.dart';",
);

fs.writeFileSync(p, s);

// ---------------------------------------------------------------- SQL
const schemaPath = 'supabase/schema.sql';
let schema = fs.readFileSync(schemaPath, 'utf8');

const itemsTable = [
  '-- ---------------------------------------------------------------------------',
  '-- 1c. Itemized receipt lines',
  '-- ---------------------------------------------------------------------------',
  '',
  'create table if not exists public.receipt_items (',
  '  id          uuid primary key default gen_random_uuid(),',
  '  receipt_id  uuid not null references public.receipts (id) on delete cascade,',
  '  name        text not null,',
  '  quantity    integer not null default 1,',
  '  unit_price  integer,',
  '  total_price integer not null default 0,',
  '  tax_rate    integer check (tax_rate in (8, 10) or tax_rate is null),',
  '  category_id uuid references public.categories (id) on delete set null,',
  '  sort_order  integer not null default 0,',
  '  created_at  timestamptz not null default now()',
  ');',
  '',
  'create index if not exists receipt_items_receipt_idx',
  '  on public.receipt_items (receipt_id, sort_order);',
  '',
].join('\n');

schema = schema.replace(
  '-- ---------------------------------------------------------------------------\n-- 2. updated_at trigger',
  itemsTable + '-- ---------------------------------------------------------------------------\n-- 2. updated_at trigger',
);

schema = schema.replace(
  'alter table public.budgets    enable row level security;',
  'alter table public.budgets    enable row level security;\nalter table public.receipt_items enable row level security;',
);

const itemsPolicy = [
  'drop policy if exists receipt_items_owner_all on public.receipt_items;',
  'create policy receipt_items_owner_all on public.receipt_items',
  '  for all using (',
  '    exists (',
  '      select 1 from public.receipts r',
  '      where r.id = receipt_id and r.user_id = auth.uid()',
  '    )',
  '  ) with check (',
  '    exists (',
  '      select 1 from public.receipts r',
  '      where r.id = receipt_id and r.user_id = auth.uid()',
  '    )',
  '  );',
].join('\n');

schema = schema.replace(
  'drop policy if exists budgets_owner_all on public.budgets;',
  itemsPolicy + '\n\ndrop policy if exists budgets_owner_all on public.budgets;',
);

fs.writeFileSync(schemaPath, schema);
console.log('detail items + sql done');