import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'news_demo_api.dart';

class NewsDemoScreen extends StatefulWidget {
  const NewsDemoScreen({super.key, required this.apiBaseUrl, this.client});
  final String apiBaseUrl;
  final NewsDemoClient? client;
  @override
  State<NewsDemoScreen> createState() => _NewsDemoScreenState();
}

class _NewsDemoScreenState extends State<NewsDemoScreen> {
  late final NewsDemoClient _api;
  final _text = TextEditingController();
  final _answers = <Map<String, dynamic>>[];
  Map<String, dynamic>? _status;
  String? _error;
  String? _errorCode;
  String? _previousId;
  String? _requestId;
  String? _submitted;
  bool _busy = false;
  bool _verifying = false;
  bool _statusLoading = false;

  @override
  void initState() {
    super.initState();
    _api = widget.client ?? NewsDemoApi(baseUrl: widget.apiBaseUrl);
    _refresh();
  }

  Future<void> _refresh() async {
    if (_statusLoading) return;
    setState(() => _statusLoading = true);
    try {
      final status = await _api.status();
      if (mounted) setState(() => _status = status);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not refresh demo availability.');
      }
    } finally {
      if (mounted) setState(() => _statusLoading = false);
    }
  }

  Future<void> _ask({bool retry = false}) async {
    if (_busy) return;
    final question = retry ? _submitted ?? '' : _text.text.trim();
    if (question.length < 3 || question.length > 300) {
      setState(() => _error = 'Enter a question between 3 and 300 characters.');
      return;
    }
    if (!retry) {
      _requestId = NewsDemoApi.newRequestId();
      _submitted = question;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _errorCode = null;
    });
    try {
      final answer = await _api.ask(question, _requestId!, _previousId);
      if (!mounted) return;
      if (answer['status'] == 'processing') {
        setState(() {
          _error =
              'Your answer is still processing. Check again shortly; this does not use another question.';
          _errorCode = 'connection';
        });
        return;
      }
      setState(() {
        _answers.add({'question': question, ...answer});
        _previousId = answer['requestId'] as String?;
        _requestId = null;
        _submitted = null;
        _text.clear();
        if (_status != null) _status!['remaining'] = answer['remaining'];
      });
      await _refresh();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is NewsDemoError
              ? error.message
              : 'The demo could not complete this request.';
          _errorCode = error is NewsDemoError ? error.code : null;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_verifying) return;
    setState(() => _verifying = true);
    try {
      await _api.sendVerification();
      if (mounted) {
        setState(
          () => _error =
              'Verification email sent. Open its link, then retry your question. Check spam if needed.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not send verification. Please wait and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _openSource(String url) async {
    final uri = Uri.tryParse(url);
    try {
      if (uri == null ||
          !uri.hasAuthority ||
          !{'http', 'https'}.contains(uri.scheme) ||
          !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('Cannot open source');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to open this source.')),
        );
      }
    }
  }

  String _expiry() {
    final time = DateTime.tryParse(_status?['expiresAt']?.toString() ?? '');
    if (time == null) return 'Not scheduled';
    return '${time.toLocal().toString().substring(0, 16)} (device time)';
  }

  @override
  void dispose() {
    _text.dispose();
    _api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Ask the news'),
      actions: [
        IconButton(
          tooltip: 'Refresh demo status',
          onPressed: _busy || _statusLoading ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.all(20),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              Text(
                'Today’s news. The story behind it.',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              const Text(
                'ONE-DAY TEXT DEMO • New registrations only • Email verification required',
              ),
              const SizedBox(height: 8),
              Text(
                '${_status?['remaining'] ?? '—'} of 100 questions remaining across all users. Ends ${_expiry()}.',
              ),
              const SizedBox(height: 8),
              const Text(
                'Each follow-up or failed provider attempt counts. Shared AI allows one question at a time, with a 60-second cooldown after each attempt. Up to two searches and ten source excerpts per question. No voice in this demo.',
              ),
              if (_statusLoading) const LinearProgressIndicator(),
              if (_status != null && _status!['active'] != true)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'The demo is closed, not yet active, or its shared quota is exhausted.',
                  ),
                ),
              const SizedBox(height: 20),
              for (final answer in _answers)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          answer['question'] as String,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Divider(height: 28),
                        if (answer['clarification'] != null)
                          Text(answer['clarification'] as String),
                        for (final section
                            in answer['sections'] as List? ?? []) ...[
                          Text(
                            section['heading'] as String,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 6),
                          SelectableText(
                            '${section['text']} [${(section['sourceIds'] as List).join(', ')}]',
                          ),
                          const SizedBox(height: 14),
                        ],
                        if ((answer['uncertainty'] as String? ?? '').isNotEmpty)
                          Text(answer['uncertainty'] as String),
                        if (answer['notice'] != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              answer['notice'] as String,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        for (final source in answer['sources'] as List? ?? [])
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Text('[${source['id']}]'),
                            title: Text(source['title'] as String? ?? 'Source'),
                            subtitle: Text(
                              Uri.tryParse(
                                    source['url'] as String? ?? '',
                                  )?.host ??
                                  '',
                            ),
                            trailing: const Icon(Icons.open_in_new, size: 18),
                            onTap: () => _openSource(source['url'] as String),
                          ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('demo-question'),
                controller: _text,
                enabled: !_busy,
                maxLength: 300,
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _ask(),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: _previousId == null
                      ? 'Ask about a news event'
                      : 'Ask a follow-up',
                  hintText: 'What happened at Jantar Mantar today?',
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(_error!),
                ),
              if (_errorCode == 'verify_email') ...[
                OutlinedButton(
                  onPressed: _verifying ? null : _verify,
                  child: const Text('Send verification email'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _ask(retry: true),
                  child: const Text('I verified my email — retry'),
                ),
              ],
              if (_errorCode == 'connection')
                OutlinedButton(
                  onPressed: _busy ? null : () => _ask(retry: true),
                  child: const Text('Check same request'),
                ),
              FilledButton.icon(
                key: const Key('demo-submit'),
                onPressed: _busy || _status?['active'] != true
                    ? null
                    : () => _ask(),
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.question_answer_outlined),
                label: Text(
                  _busy
                      ? 'Finding sources and background…'
                      : 'Ask (uses one question)',
                ),
              ),
              if (_previousId != null)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _previousId = null;
                          _requestId = null;
                          _submitted = null;
                          _text.clear();
                          _error = null;
                          _errorCode = null;
                        }),
                  child: const Text('Start a different topic'),
                ),
              const SizedBox(height: 20),
              const Text(
                'Questions are sent to the news-search and AI providers. Don’t include personal or confidential information. News may be incomplete; source links are provided for verification.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
