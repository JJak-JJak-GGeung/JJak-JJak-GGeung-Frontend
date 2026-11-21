import 'dart:convert';
import 'dart:typed_data';

import '../../api.dart';

/// In-memory stand-in for the settlement server, built from public A data.
///
/// It answers the same paths as the FastAPI server so every screen can be
/// clicked end to end without a deployment. Everything it returns is example
/// data: screens show an "예시 응답" banner while it is in use, and a pass on
/// this backend never counts as an integration pass.
class DemoBackend implements Backend {
  DemoBackend() {
    reset(DemoScenario.initialInvoice);
  }

  static const periodId = 'sample';
  static const storeName = '가온 장어식당';
  static const supplierName = '달마루 수산';

  DemoScenario scenario = DemoScenario.initialInvoice;
  int _revision = 1;
  final _uploaded = <String>[]; // document ids in upload order
  final _receipts = <String, Json>{}; // delivery line id -> receipt
  bool _replacementConfirmed = false;
  final _memos = <String, List<Json>>{}; // transaction id -> memos
  final _approvals = <Json>[];
  final _keys = <String, Json>{}; // request_key -> response
  final _failedOnce = <String>{};
  int _sequence = 0;

  /// Puts the example period into one of the A stages.
  void reset(DemoScenario value) {
    scenario = value;
    _revision = 1;
    _uploaded.clear();
    _receipts.clear();
    _replacementConfirmed = false;
    _memos.clear();
    _approvals.clear();
    _keys.clear();
    _failedOnce.clear();
    if (value == DemoScenario.empty) return;
    _uploaded.addAll(['D1', 'D2', 'D3', 'D4']);
    _revision = 5;
    if (value == DemoScenario.receiptMissing) return;
    _linkReceipt('L1', 'L3a');
    if (value == DemoScenario.receiptZero) {
      _receipts['L2'] = {
        'receipt_id': 'R-zero',
        'target_delivery_line_id': 'L2',
        'source_line_id': null,
        'received_qty': '0',
        'unit': 'kg',
        'evidence_text': '입고 직후 계량 · 0kg 확인',
        'confirmed_by': '예시 점주',
        'confirmed_at': '2026-11-14T09:10:00+09:00',
      };
      _revision = 7;
      return;
    }
    _linkReceipt('L2', 'L3b');
    _revision = 6;
    if (value == DemoScenario.corrected) {
      _memos['T-A131'] = [_memo('T-A131', _sampleMemo, 'VOICE_MEMO')];
      _uploaded.add('D5');
      _replacementConfirmed = true;
      _revision = 8;
    }
  }

  static const _sampleMemo =
      '거래처는 11월 13일에 장어 40킬로를 다 보냈다고 합니다. 우리 가게 기록에는 36킬로입니다.';

  // ---------------------------------------------------------------- documents

  static final Map<String, Json> _documents = {
    'D1': _doc('D1', 'A01_납품명세_1109.png', 'DELIVERY', 'DL-A091',
        '2026-11-09', null, null, null, [
      _line('L1', 'DL-A091', '2026-11-09', '60', 1),
    ]),
    'D2': _doc('D2', 'A02_납품명세_1113.png', 'DELIVERY', 'DL-A131',
        '2026-11-13', null, null, null, [
      _line('L2', 'DL-A131', '2026-11-13', '40', 1),
    ]),
    'D3': _doc('D3', 'A03_점포수령기록.png', 'RECEIPT', null, null, null, null,
        null, [
      _line('L3a', 'DL-A091', '2026-11-09', '60', 1, price: false),
      _line('L3b', 'DL-A131', '2026-11-13', '36', 2, price: false),
    ]),
    'D4': _doc('D4', 'A04_주간청구서.png', 'INVOICE', 'INV-A01', '2026-11-16',
        '2026-11-18', null, null, [
      _line('L4a', 'DL-A091', '2026-11-09', '60', 1),
      _line('L4b', 'DL-A131', '2026-11-13', '40', 2),
    ]),
    'D5': _doc('D5', 'A05_수정청구서.png', 'CORRECTED_INVOICE', 'INV-A01-R1',
        '2026-11-17', '2026-11-18', 'INV-A01',
        '11월 13일 납품분을 양측 확인 후 36kg으로 수정했습니다.', [
      _line('L5a', 'DL-A091', '2026-11-09', '60', 1),
      _line('L5b', 'DL-A131', '2026-11-13', '36', 2),
    ]),
  };

  static Json _doc(
          String id,
          String filename,
          String type,
          String? docNo,
          String? docDate,
          String? due,
          String? replaces,
          String? agreement,
          List<Json> lines) =>
      {
        'document_id': id,
        'filename': filename,
        'file_hash': 'demo-$id',
        'doc_type': type,
        'extraction_status': 'COMPLETED',
        'supplier_name_read': supplierName,
        'doc_no': docNo,
        'doc_date': docDate,
        'period_start': '2026-11-09',
        'period_end': '2026-11-15',
        'payment_due_on': due,
        'replaces_doc_no': replaces,
        'agreement_text': agreement,
        'agreement_source_location':
            agreement == null ? null : {'page': 1, 'text': agreement},
        'lines': [
          for (final line in lines) {...line, 'document_id': id}
        ],
      };

  static Json _line(String id, String no, String date, String qty, int row,
          {bool price = true}) =>
      {
        'line_id': id,
        'delivery_no': no,
        'delivery_date': date,
        'item': '손질 장어',
        'spec': null,
        'unit': 'kg',
        'qty_read': qty,
        'unit_price_read': price ? '20000' : null,
        'amount_read': price ? int.parse(qty) * 20000 : null,
        'source_location': {'page': 1, 'row': row},
      };

  /// Text version of an example original, used by the original viewer
  /// because the demo has no image bytes.
  Json? documentText(String id) {
    final doc = _documents[id];
    if (doc == null) return null;
    final type = doc['doc_type'];
    return {
      'title': switch (type) {
        'DELIVERY' => '납품 명세서 ${doc['doc_no']}',
        'RECEIPT' => '점포 수령 기록',
        'INVOICE' => '정산 청구서 ${doc['doc_no']}',
        _ => '정산 청구서 · 수정본 ${doc['doc_no']}',
      },
      'header': [
        '공급처 $supplierName · 받는 점포 $storeName',
        '정산 기간 2026-11-09 ~ 11-15',
        if (doc['payment_due_on'] != null) '합의 지급일 ${doc['payment_due_on']}',
        if (doc['replaces_doc_no'] != null) '대체 청구 ${doc['replaces_doc_no']}',
      ],
      'rows': [
        for (final line in objects(doc['lines']))
          {
            'row': object(line['source_location'])['row'],
            'text': [
              line['delivery_date'],
              line['delivery_no'],
              line['item'],
              '${line['qty_read']}kg',
              if (line['amount_read'] != null)
                '${_comma(line['amount_read'])}원',
            ].join(' · '),
          }
      ],
      'footer': doc['agreement_text'],
    };
  }

  static String _comma(Object? v) => v
      .toString()
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

  // ------------------------------------------------------------- computation

  void _linkReceipt(String deliveryLine, String receiptLine) {
    final source = objects(_documents['D3']!['lines'])
        .firstWhere((l) => l['line_id'] == receiptLine);
    _receipts[deliveryLine] = {
      'receipt_id': 'R-$receiptLine',
      'target_delivery_line_id': deliveryLine,
      'source_line_id': receiptLine,
      'received_qty': source['qty_read'],
      'unit': 'kg',
      'confirmed_by': '예시 점주',
      'confirmed_at': '2026-11-14T09:00:00+09:00',
    };
  }

  bool _has(String id) => _uploaded.contains(id);

  Json? get _currentInvoice => _has('D5') && _replacementConfirmed
      ? _documents['D5']
      : _has('D4')
          ? _documents['D4']
          : null;

  Json? _invoiceLine(String deliveryNo) {
    final invoice = _currentInvoice;
    if (invoice == null) return null;
    for (final line in objects(invoice['lines'])) {
      if (line['delivery_no'] == deliveryNo) return line;
    }
    return null;
  }

  List<Json> get _deliveries => [
        for (final id in ['D1', 'D2'])
          if (_has(id)) ...objects(_documents[id]!['lines'])
      ];

  static String _txId(Json deliveryLine) =>
      'T-${deliveryLine['delivery_no'].toString().replaceFirst('DL-', '')}';

  Json _item(Json delivery) {
    final invoiceLine = _invoiceLine(delivery['delivery_no']);
    final receipt = _receipts[delivery['line_id']];
    final billed = invoiceLine == null ? null : num.parse(invoiceLine['qty_read']);
    final received =
        receipt == null ? null : num.parse(receipt['received_qty'].toString());
    final delta = billed == null || received == null ? null : billed - received;
    final invoice = _currentInvoice;
    return {
      'transaction_id': _txId(delivery),
      'delivery_no': delivery['delivery_no'],
      'delivery_date': delivery['delivery_date'],
      'item': delivery['item'],
      'declared_qty': delivery['qty_read'],
      'billed_qty': _dec(billed),
      'received_qty': _dec(received),
      'unit': 'kg',
      'delta_qty': _dec(delta),
      'check_amount': delta == null ? null : (delta * 20000).round(),
      'billed_amount': invoiceLine?['amount_read'],
      'unit_price': invoiceLine == null ? null : '20000',
      'evidence_refs': [
        _ref(delivery, 'DELIVERY'),
        if (receipt != null && receipt['source_line_id'] != null)
          _ref(
              objects(_documents['D3']!['lines'])
                  .firstWhere((l) => l['line_id'] == receipt['source_line_id']),
              'RECEIPT'),
        if (invoiceLine != null) _ref(invoiceLine, invoice!['doc_type']),
      ],
    };
  }

  /// Decimal string without a trailing ".0".
  static String? _dec(num? v) => v == null
      ? null
      : v == v.roundToDouble()
          ? v.round().toString()
          : v.toString();

  static Json _ref(Json line, String kind) => {
        'document_id': line['document_id'],
        'line_id': line['line_id'],
        'kind': kind,
        'source_location': line['source_location'],
      };

  Json _approvalFor(int revision) => _approvals.firstWhere(
      (a) => a['input_revision'] == revision,
      orElse: () => <String, dynamic>{});

  Json _period() {
    final items = [for (final d in _deliveries) _item(d)];
    num? sum(String key) {
      num total = 0;
      for (final item in items) {
        final value = item[key];
        if (value == null) return null;
        total += value is num ? value : num.parse(value.toString());
      }
      return items.isEmpty ? null : total;
    }

    final invoice = _currentInvoice;
    final billedQty = invoice == null ? null : sum('billed_qty');
    final receivedQty = sum('received_qty');
    final delta =
        billedQty == null || receivedQty == null ? null : billedQty - receivedQty;
    final blockers = <String>[
      if (items.isEmpty) 'DELIVERY_MISSING',
      if (invoice == null) 'INVOICE_MISSING',
      if (items.any((i) => i['received_qty'] == null)) 'RECEIPT_MISSING',
      if (_has('D5') && !_replacementConfirmed) 'REPLACEMENT_UNCONFIRMED',
      if (items.any((i) => i['delta_qty'] != null && i['delta_qty'] != '0'))
        'QTY_MISMATCH',
    ];
    final approval = _approvalFor(_revision);
    final approved = approval.isNotEmpty;
    final conflicting = _memos.values.any((list) => list.isNotEmpty) &&
        blockers.contains('QTY_MISMATCH');
    final billedAmount = invoice == null ? null : sum('billed_amount');
    return {
      'period_id': periodId,
      'store_id': 'sample-store',
      'store_name': storeName,
      'supplier_id': 'sample-supplier',
      'supplier_name': supplierName,
      'period_start': '2026-11-09',
      'period_end': '2026-11-15',
      'is_example': true,
      'input_revision': _revision,
      'payment_due_on': invoice?['payment_due_on'],
      'summary': {
        'declared_qty': _dec(sum('declared_qty')),
        'billed_qty': _dec(billedQty),
        'received_qty': _dec(receivedQty),
        'unit': 'kg',
        'delta_qty': _dec(delta),
        'check_amount': delta == null ? null : sum('check_amount'),
        'billed_amount': billedAmount,
        'unit_price': invoice == null ? null : '20000',
      },
      'items': items,
      'documents': [for (final id in _uploaded) _documentResponse(id)],
      'billing_history': [
        if (_has('D4'))
          {
            'document_id': 'D4',
            'doc_no': 'INV-A01',
            'billed_qty': '100',
            'billed_amount': 2000000,
            'status': _replacementConfirmed && _has('D5') ? 'REPLACED' : 'CURRENT',
          },
        if (_has('D5'))
          {
            'document_id': 'D5',
            'doc_no': 'INV-A01-R1',
            'replaces_doc_no': 'INV-A01',
            'billed_qty': '96',
            'billed_amount': 1920000,
            'agreement_text': _documents['D5']!['agreement_text'],
            'agreement_ref': {
              'document_id': 'D5',
              'line_id': null,
              'kind': 'CORRECTED_INVOICE',
              'source_location': _documents['D5']!['agreement_source_location'],
            },
            'status': _replacementConfirmed ? 'CURRENT' : 'CANDIDATE',
          },
      ],
      'confirmation_scope':
          _receipts.isEmpty ? 'DOCUMENTS_ONLY' : 'RECEIPTS_INCLUDED',
      'match_result': items.isEmpty || blockers.contains('RECEIPT_MISSING') ||
              invoice == null
          ? 'MISSING_DATA'
          : blockers.contains('QTY_MISMATCH')
              ? 'MISMATCH'
              : 'MATCHED',
      'fact_status': conflicting
          ? 'CONFLICTING'
          : _receipts.isEmpty
              ? 'UNCONFIRMED'
              : 'OWNER_CONFIRMED',
      'work_status': approved
          ? 'APPROVED'
          : blockers.contains('QTY_MISMATCH')
              ? 'WAITING_REPLY'
              : blockers.isNotEmpty
                  ? 'NEEDS_INFO'
                  : 'OPEN',
      'blockers': blockers,
      'can_approve': !approved && blockers.isEmpty,
      'approvable_amount': blockers.isEmpty ? billedAmount : null,
      'approved_amount': approved ? approval['approved_amount'] : null,
      'approval_id': approved ? approval['approval_id'] : null,
      'payment_status': 'UNCONFIRMED',
    };
  }

  Json _documentResponse(String id, {bool duplicate = false}) => {
        ..._documents[id]!,
        if (_failedOnce.contains(id)) ...{
          'extraction_status': 'FAILED',
          'lines': <Json>[],
        },
        'duplicate': duplicate,
        'input_revision': _revision,
      };

  Json _memo(String tx, String text, String mode) => {
        'memo_id': 'M-${++_sequence}',
        'transaction_id': tx,
        'kind': 'owner_call_memo',
        'confirmed_text': text,
        'source_mode': mode,
        'author': '예시 점주',
        'confirmed_at': '2026-11-14T10:${(_sequence % 60).toString().padLeft(2, '0')}:00+09:00',
      };

  // ---------------------------------------------------------------- requests

  Future<T> _later<T>(T Function() body) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return body();
  }

  static Json _copy(Json value) => object(jsonDecode(jsonEncode(value)));

  void _expect(Json body) {
    final expected = body['expected_revision'];
    if (expected != _revision) throw const ApiError(409, 'STALE_REVISION');
  }

  Json? _replay(Json body) {
    final key = body['request_key']?.toString();
    return key == null ? null : _keys[key];
  }

  @override
  Future<dynamic> get(String path) => _later(() {
        final uri = Uri.parse(path);
        final segments = uri.pathSegments;
        if (path == '/api/stores') {
          return {
            'stores': [
              {'id': 'sample-store', 'name': storeName}
            ]
          };
        }
        if (segments.length == 2 && segments[1] == 'suppliers') {
          return {
            'suppliers': [
              {'id': 'sample-supplier', 'name': supplierName}
            ]
          };
        }
        if (segments.length == 2 && segments[1] == 'periods') {
          return {
            'is_example': true,
            'periods': [
              {
                'period_id': periodId,
                'label': '2026-11-09 ~ 2026-11-15',
                'period_start': '2026-11-09',
                'period_end': '2026-11-15',
              }
            ]
          };
        }
        if (segments.length == 3 && segments[1] == 'periods') {
          return _period();
        }
        if (segments.length == 4 &&
            segments[1] == 'periods' &&
            segments[3] == 'approvals') {
          return {
            'approvals': [
              for (final a in _approvals.reversed)
                {
                  'approval_id': a['approval_id'],
                  'period_id': periodId,
                  'version_no': a['version_no'],
                  'input_revision': a['input_revision'],
                  'approved_amount': a['approved_amount'],
                  'approved_at': a['approved_at'],
                  'approved_by': a['approved_by'],
                  'payment_status': 'UNCONFIRMED',
                  'is_current': a['input_revision'] == _revision,
                }
            ]
          };
        }
        if (segments.length == 3 && segments[1] == 'approvals') {
          final found = _approvals.firstWhere(
              (a) => a['approval_id'] == segments[2],
              orElse: () => throw const ApiError(404));
          return _copy(found);
        }
        if (segments.length == 3 && segments[1] == 'transactions') {
          final period = _period();
          final item = objects(period['items']).firstWhere(
              (i) => i['transaction_id'] == segments[2],
              orElse: () => throw const ApiError(404));
          final delivery = _deliveries.firstWhere(
              (d) => _txId(d) == segments[2]);
          final receipt = _receipts[delivery['line_id']];
          return {
            ...item,
            'supplier_name': supplierName,
            'work_status': period['work_status'],
            'memos': _memos[segments[2]] ?? [],
            'receipts': [if (receipt != null) receipt],
          };
        }
        throw const ApiError(404);
      });

  @override
  Future<Json> post(String path, Json body) => _later(() {
        final replay = _replay(body);
        if (replay != null) return _copy(replay);
        final segments = Uri.parse(path).pathSegments;
        Json result;
        if (path == '/api/periods') {
          // The example data covers one week only.
          if (body['week_start'] != '2026-11-09') {
            throw const ApiError(422, 'DEMO_SAMPLE_WEEK_ONLY');
          }
          return {
            'period_id': periodId,
            'label': '2026-11-09 ~ 2026-11-15',
            'period_start': '2026-11-09',
            'period_end': '2026-11-15',
            'created': false,
          };
        }
        if (segments.length == 4 && segments[3] == 'confirmations') {
          _expect(body);
          result = _confirm(body);
        } else if (segments.length == 4 && segments[3] == 'memos') {
          _expect(body);
          final text = body['confirmed_text']?.toString().trim() ?? '';
          if (text.isEmpty) throw const ApiError(422);
          final memo = _memo(segments[2], text,
              body['source_mode'] == 'VOICE_MEMO' ? 'VOICE_MEMO' : 'TYPED_TEXT');
          (_memos[segments[2]] ??= []).add(memo);
          _revision++;
          result = {...memo, 'input_revision': _revision};
        } else if (segments.length == 4 && segments[3] == 'approvals') {
          result = _approve(body);
        } else if (segments.length == 4 && segments[3] == 'extraction') {
          _failedOnce.remove(segments[2]);
          _revision++;
          result = _documentResponse(segments[2]);
        } else {
          throw const ApiError(404);
        }
        final key = body['request_key']?.toString();
        if (key != null) _keys[key] = _copy(result);
        return result;
      });

  Json _confirm(Json body) {
    switch (body['kind']) {
      case 'receipt_link':
        final source = body['source_line_id'];
        final target = body['target_id'];
        final receiptLine = objects(_documents['D3']!['lines'])
            .where((l) => l['line_id'] == source)
            .toList();
        if (receiptLine.isEmpty ||
            !_deliveries.any((d) => d['line_id'] == target)) {
          throw const ApiError(422);
        }
        _linkReceipt(target, source);
      case 'receipt_entry' || 'line_correction':
        final target = body['target_id'];
        if (!_deliveries.any((d) => d['line_id'] == target)) {
          throw const ApiError(422);
        }
        final fields = body['kind'] == 'line_correction'
            ? object(body['corrected_fields'])
            : body;
        _receipts[target] = {
          'receipt_id': 'R-${++_sequence}',
          'target_delivery_line_id': target,
          'source_line_id': null,
          'received_qty': fields['received_qty'],
          'unit': fields['unit'],
          'evidence_text': body['evidence_text'],
          'supersedes_receipt_id': body['supersedes_receipt_id'],
          'confirmed_by': '예시 점주',
          'confirmed_at': '2026-11-14T11:00:00+09:00',
        };
      case 'replacement':
        if (body['document_id'] != 'D5' || body['target_id'] != 'D4') {
          throw const ApiError(422);
        }
        _replacementConfirmed = true;
      default:
        throw const ApiError(422);
    }
    _revision++;
    return {'input_revision': _revision, 'settlement': _period()};
  }

  Json _approve(Json body) {
    final existing = _approvalFor(_revision);
    if (body['expected_revision'] != _revision) {
      throw const ApiError(409, 'STALE_REVISION');
    }
    if (existing.isNotEmpty) return _summary(existing);
    final period = _period();
    if (period['can_approve'] != true) throw const ApiError(422, 'BLOCKED');
    final approval = {
      'approval_id': 'S-${_approvals.length + 1}-r$_revision',
      'period_id': periodId,
      'input_revision': _revision,
      'version_no': _approvals.length + 1,
      'approved_amount': period['approvable_amount'],
      'approved_by': '예시 점주',
      'approved_at': '2026-11-17T14:00:00+09:00',
      'payment_status': 'UNCONFIRMED',
      'snapshot': {
        ..._copy(period),
        'work_status': 'APPROVED',
        'can_approve': false,
        'approved_amount': period['approvable_amount'],
      },
    };
    _approvals.add(approval);
    return _summary(approval);
  }

  static Json _summary(Json approval) => {
        for (final key in [
          'approval_id',
          'period_id',
          'input_revision',
          'version_no',
          'approved_amount'
        ])
          key: approval[key],
      };

  // ----------------------------------------------------------------- uploads

  static const _order = {
    'DELIVERY': ['D1', 'D2'],
    'RECEIPT': ['D3'],
    'INVOICE': ['D4'],
    'CORRECTED_INVOICE': ['D5'],
  };

  @override
  Future<Json> upload(String path, Uint8List bytes, String name, String mime,
          [Map<String, String> fields = const {}]) =>
      _later(() {
        if (path == '/api/transcriptions') {
          return {'draft_text': _sampleMemo};
        }
        final type = fields['doc_type'] ?? 'DELIVERY';
        final candidates = _order[type] ?? const <String>[];
        final next = candidates.where((id) => !_has(id)).toList();
        if (next.isEmpty) {
          return _documentResponse(candidates.last, duplicate: true);
        }
        final id = next.first;
        _uploaded.add(id);
        if (name.toLowerCase().contains('fail')) _failedOnce.add(id);
        _revision++;
        return _documentResponse(id);
      });

  @override
  Future<Uint8List> original(String documentId) async => Uint8List(0);
}

enum DemoScenario {
  empty('빈 정산에서 시작'),
  receiptMissing('수령 미확인 (null)'),
  receiptZero('수령 0kg 확인'),
  initialInvoice('최초 청구 100/96'),
  corrected('수정 청구 연결 후');

  const DemoScenario(this.label);
  final String label;
}
