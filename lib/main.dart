import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// Brand colors — dark + warm orange
const Color claudeOrange = Color(0xFFE8792E);
const Color claudeOrangeDark = Color(0xFFD06825);
const Color claudeOrangeLight = Color(0xFFF0985A);
const Color claudeBg = Color(0xFF0D0D0D);
const Color claudeSurface = Color(0xFF181818);
const Color claudeSurfaceLight = Color(0xFF222222);
const Color claudeBarBg = Color(0xFF2A2A2A);

void main() {
  runApp(const MenuBarApp());
}

class MenuBarApp extends StatelessWidget {
  const MenuBarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Claude Usage Tracker',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: claudeBg,
        colorScheme: const ColorScheme.dark(
          primary: claudeOrange,
          surface: claudeBg,
        ),
        useMaterial3: true,
      ),
      home: const UsageDashboard(),
    );
  }
}

// --- Data Models ---

class AccountInfo {
  final String displayName;
  final String email;
  final String orgName;
  final String billingType;
  final bool hasExtraUsage;
  final String? extraUsageDisabledReason;

  AccountInfo({
    required this.displayName,
    required this.email,
    required this.orgName,
    required this.billingType,
    required this.hasExtraUsage,
    this.extraUsageDisabledReason,
  });
}

class RateLimitInfo {
  final String type;
  final int tokenCount;
  final int resetsAt;
  final bool isUsingOverage;
  final double? utilization; // from CLI when above warning threshold

  RateLimitInfo({
    required this.type,
    required this.tokenCount,
    required this.resetsAt,
    required this.isUsingOverage,
    this.utilization,
  });

  bool get isCritical => utilization != null;
  int get percentUsed => ((utilization ?? 0) * 100).round();

  String get displayName {
    switch (type) {
      case 'five_hour':
        return 'Current Session (5h)';
      case 'seven_day':
        return 'Current Week';
      default:
        return type.replaceAll('_', ' ');
    }
  }

  String get formattedTokens {
    if (tokenCount >= 1000000) {
      return '${(tokenCount / 1000000).toStringAsFixed(1)}M';
    } else if (tokenCount >= 1000) {
      return '${(tokenCount / 1000).toStringAsFixed(1)}K';
    }
    return '$tokenCount';
  }

  String get resetTimeFormatted {
    final resetDate =
        DateTime.fromMillisecondsSinceEpoch(resetsAt * 1000, isUtc: true)
            .toLocal();
    final now = DateTime.now();
    final diff = resetDate.difference(now);
    final timeStr = DateFormat('h:mma').format(resetDate).toLowerCase();
    final tzName = resetDate.timeZoneName;
    if (diff.inDays == 0) {
      return 'Resets $timeStr ($tzName)';
    } else {
      final dateStr = DateFormat('MMM d').format(resetDate);
      return 'Resets $dateStr at $timeStr ($tzName)';
    }
  }
}

class ProjectStats {
  final String name;
  final int totalInputTokens;
  final int totalOutputTokens;
  final int sessionCount;
  final int messageCount;

  ProjectStats({
    required this.name,
    required this.totalInputTokens,
    required this.totalOutputTokens,
    required this.sessionCount,
    required this.messageCount,
  });

  int get totalTokens => totalInputTokens + totalOutputTokens;

  String get formattedTokens {
    if (totalTokens >= 1000000) {
      return '${(totalTokens / 1000000).toStringAsFixed(1)}M';
    } else if (totalTokens >= 1000) {
      return '${(totalTokens / 1000).toStringAsFixed(1)}K';
    }
    return '$totalTokens';
  }
}

class RecentSession {
  final String prompt;
  final DateTime timestamp;
  final String project;

  RecentSession({
    required this.prompt,
    required this.timestamp,
    required this.project,
  });
}

// --- Main Dashboard ---

class UsageDashboard extends StatefulWidget {
  const UsageDashboard({super.key});

  @override
  State<UsageDashboard> createState() => _UsageDashboardState();
}

class _UsageDashboardState extends State<UsageDashboard> {
  AccountInfo? _account;
  List<RateLimitInfo> _rateLimits = [];
  List<ProjectStats> _projectStats = [];
  List<RecentSession> _recentSessions = [];
  int _totalTokensIn = 0;
  int _totalTokensOut = 0;
  int _totalSessions = 0;
  int _totalProjects = 0;
  bool _loading = true;
  String? _error;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    _refreshTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    setState(() => _loading = _account == null);
    // Load local data first (fast)
    try {
      await Future.wait([
        _loadAccountInfo(),
        _loadRecentSessions(),
      ]);
    } catch (e) {
      debugPrint('Error loading local data: $e');
    }
    // Load project stats separately (can be slow)
    try {
      await _loadProjectStats();
    } catch (e) {
      debugPrint('Error loading project stats: $e');
    }
    // Load rate limits last (runs CLI, takes a few seconds)
    try {
      await _loadUsageInfo();
    } catch (e) {
      debugPrint('Error loading usage info: $e');
    }
    setState(() => _loading = false);
  }

  String get _home {
    final env = Platform.environment['HOME'] ?? '';
    // When running from Xcode, HOME might be empty or sandboxed
    if (env.isEmpty || env.contains('Containers')) {
      return '/Users/pratikbaid';
    }
    return env;
  }

  Future<void> _loadAccountInfo() async {
    final configFile = File('$_home/.claude.json');
    if (await configFile.exists()) {
      final content = await configFile.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final oauth = json['oauthAccount'] as Map<String, dynamic>? ?? {};
      setState(() {
        _account = AccountInfo(
          displayName: oauth['displayName'] as String? ?? 'Unknown',
          email: oauth['emailAddress'] as String? ?? 'Unknown',
          orgName: oauth['organizationName'] as String? ?? 'Unknown',
          billingType: oauth['billingType'] as String? ?? 'Unknown',
          hasExtraUsage: oauth['hasExtraUsageEnabled'] as bool? ?? false,
          extraUsageDisabledReason:
              json['cachedExtraUsageDisabledReason'] as String?,
        );
        _loading = false;
      });
    }
  }

  Future<void> _loadUsageInfo() async {
    try {
      // Calculate token usage from session files
      final projectsDir = Directory('$_home/.claude/projects/');
      if (!await projectsDir.exists()) return;

      final now = DateTime.now().toUtc();
      final fiveHoursAgo = now.subtract(const Duration(hours: 5));
      final sevenDaysAgo = now.subtract(const Duration(days: 7));

      int tokens5h = 0;
      int tokens7d = 0;

      final projectDirs = await projectsDir.list().toList();
      for (final entity in projectDirs) {
        if (entity is! Directory) continue;
        final files = await entity.list().toList();
        for (final file in files) {
          if (file is! File || !file.path.endsWith('.jsonl')) continue;
          try {
            final lines = await file.readAsLines();
            for (final line in lines) {
              try {
                final d = jsonDecode(line) as Map<String, dynamic>;
                if (d['type'] != 'assistant') continue;
                final ts = d['timestamp'] as String?;
                if (ts == null) continue;
                final dt = DateTime.parse(ts);
                final msg = d['message'] as Map<String, dynamic>? ?? {};
                final usage = msg['usage'] as Map<String, dynamic>? ?? {};
                final total = (usage['input_tokens'] as int? ?? 0) +
                    (usage['output_tokens'] as int? ?? 0) +
                    (usage['cache_creation_input_tokens'] as int? ?? 0);
                if (dt.isAfter(fiveHoursAgo)) tokens5h += total;
                if (dt.isAfter(sevenDaysAgo)) tokens7d += total;
              } catch (_) {}
            }
          } catch (_) {}
        }
      }

      // Also run CLI to get reset times and utilization (when critical)
      int resetsAt5h = 0;
      int resetsAt7d = 0;
      double? util5h;
      double? util7d;
      try {
        final result = await Process.run(
          '$_home/.local/bin/claude',
          ['-p', '.', '--output-format', 'stream-json', '--verbose'],
          environment: {...Platform.environment, 'HOME': _home},
          workingDirectory: _home,
        );
        final output = result.stdout as String;
        for (final line in output.split('\n')) {
          if (line.trim().isEmpty) continue;
          try {
            final json = jsonDecode(line) as Map<String, dynamic>;
            if (json['type'] == 'rate_limit_event') {
              final info = json['rate_limit_info'] as Map<String, dynamic>;
              final type = info['rateLimitType'] as String? ?? '';
              final resets = info['resetsAt'] as int? ?? 0;
              final util = (info['utilization'] as num?)?.toDouble();
              if (type == 'five_hour') {
                resetsAt5h = resets;
                util5h = util;
              }
              if (type == 'seven_day') {
                resetsAt7d = resets;
                util7d = util;
              }
            }
          } catch (_) {}
        }
      } catch (_) {}

      // If we didn't get reset times from CLI, estimate them
      if (resetsAt5h == 0) {
        resetsAt5h = now
            .add(const Duration(hours: 5))
            .millisecondsSinceEpoch ~/ 1000;
      }
      if (resetsAt7d == 0) {
        final daysUntilMonday = (DateTime.monday - now.weekday + 7) % 7;
        resetsAt7d = now
            .add(Duration(days: daysUntilMonday == 0 ? 7 : daysUntilMonday))
            .millisecondsSinceEpoch ~/ 1000;
      }

      setState(() {
        _rateLimits = [
          RateLimitInfo(
            type: 'five_hour',
            tokenCount: tokens5h,
            resetsAt: resetsAt5h,
            isUsingOverage: false,
            utilization: util5h,
          ),
          RateLimitInfo(
            type: 'seven_day',
            tokenCount: tokens7d,
            resetsAt: resetsAt7d,
            isUsingOverage: false,
            utilization: util7d,
          ),
        ];
      });
    } catch (e) {
      debugPrint('Error loading usage: $e');
    }
  }

  Future<void> _loadProjectStats() async {
    final projectsDir = Directory('$_home/.claude/projects/');
    if (!await projectsDir.exists()) return;

    final projectDirs = await projectsDir.list().toList();
    final stats = <ProjectStats>[];
    int grandTotalIn = 0;
    int grandTotalOut = 0;
    int grandTotalSessions = 0;

    for (final entity in projectDirs) {
      if (entity is! Directory) continue;
      final dirName = entity.path.split('/').last;
      final projectName = dirName.replaceAll('-', '/').replaceFirst('/', '');

      int tokensIn = 0;
      int tokensOut = 0;
      int sessionCount = 0;
      int messageCount = 0;

      final files = await entity.list().toList();
      for (final file in files) {
        if (file is! File || !file.path.endsWith('.jsonl')) continue;
        sessionCount++;
        try {
          final lines = await file.readAsLines();
          for (final line in lines) {
            try {
              final d = jsonDecode(line) as Map<String, dynamic>;
              if (d['type'] == 'assistant') {
                messageCount++;
                final msg = d['message'] as Map<String, dynamic>? ?? {};
                final usage = msg['usage'] as Map<String, dynamic>? ?? {};
                tokensIn += (usage['input_tokens'] as int? ?? 0);
                tokensIn += (usage['cache_creation_input_tokens'] as int? ?? 0);
                tokensOut += (usage['output_tokens'] as int? ?? 0);
              } else if (d['type'] == 'user') {
                messageCount++;
              }
            } catch (_) {}
          }
        } catch (_) {}
      }

      if (sessionCount > 0) {
        stats.add(ProjectStats(
          name: _shortenPath(projectName),
          totalInputTokens: tokensIn,
          totalOutputTokens: tokensOut,
          sessionCount: sessionCount,
          messageCount: messageCount,
        ));
        grandTotalIn += tokensIn;
        grandTotalOut += tokensOut;
        grandTotalSessions += sessionCount;
      }
    }

    // Sort by total tokens descending
    stats.sort((a, b) => b.totalTokens.compareTo(a.totalTokens));

    setState(() {
      _projectStats = stats;
      _totalTokensIn = grandTotalIn;
      _totalTokensOut = grandTotalOut;
      _totalSessions = grandTotalSessions;
      _totalProjects = stats.length;
    });
  }

  Future<void> _loadRecentSessions() async {
    final historyFile = File('$_home/.claude/history.jsonl');
    if (!await historyFile.exists()) return;

    final lines = await historyFile.readAsLines();
    final sessions = <RecentSession>[];

    for (final line in lines.reversed) {
      try {
        final d = jsonDecode(line) as Map<String, dynamic>;
        final display = d['display'] as String? ?? '';
        final timestamp = d['timestamp'] as int? ?? 0;
        final project = d['project'] as String? ?? '';
        if (display.isNotEmpty) {
          sessions.add(RecentSession(
            prompt: display,
            timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp),
            project: _shortenPath(project),
          ));
        }
        if (sessions.length >= 5) break;
      } catch (_) {}
    }

    setState(() => _recentSessions = sessions);
  }

  String _shortenPath(String path) {
    final parts = path.split('/');
    if (parts.length <= 2) return path;
    return parts.sublist(parts.length - 2).join('/');
  }

  String _formatTokens(int tokens) {
    if (tokens >= 1000000) {
      return '${(tokens / 1000000).toStringAsFixed(1)}M';
    } else if (tokens >= 1000) {
      return '${(tokens / 1000).toStringAsFixed(1)}K';
    }
    return '$tokens';
  }

  String _formatBillingType(String type) {
    switch (type) {
      case 'stripe_subscription':
        return 'Pro Subscription';
      case 'enterprise':
        return 'Enterprise';
      case 'free':
        return 'Free';
      default:
        return type;
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: claudeOrange),
              SizedBox(height: 12),
              Text('Fetching usage data...',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: Image.asset(
                    'assets/app_icon.png',
                    width: 34,
                    height: 34,
                  ),
                ),
                const SizedBox(width: 10),
                const Text('Claude Usage',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                const Spacer(),
                _RefreshButton(onRefresh: _loadData),
              ],
            ),
            const SizedBox(height: 16),

            // Account Card
            if (_account != null) ...[
              _SectionCard(children: [
                _buildInfoRow(Icons.person_outline, _account!.displayName),
                _buildInfoRow(Icons.email_outlined, _account!.email),
                _buildInfoRow(Icons.business_outlined, _account!.orgName),
                _buildInfoRow(Icons.credit_card_outlined,
                    _formatBillingType(_account!.billingType)),
              ]),
              const SizedBox(height: 12),
            ],

            // Rate Limits
            if (_rateLimits.isNotEmpty)
              ..._rateLimits.map((rl) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _UsageCard(info: rl),
                  )),

            // Overview Stats
            _SectionCard(children: [
              const Text('Overview',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: claudeOrange)),
              const SizedBox(height: 10),
              Row(
                children: [
                  _MiniStat(
                      label: 'Tokens In',
                      value: _formatTokens(_totalTokensIn),
                      icon: Icons.arrow_downward),
                  _MiniStat(
                      label: 'Tokens Out',
                      value: _formatTokens(_totalTokensOut),
                      icon: Icons.arrow_upward),
                  _MiniStat(
                      label: 'Sessions',
                      value: '$_totalSessions',
                      icon: Icons.chat_bubble_outline),
                  _MiniStat(
                      label: 'Projects',
                      value: '$_totalProjects',
                      icon: Icons.folder_outlined),
                ],
              ),
            ]),
            const SizedBox(height: 12),

            // Per-Project Breakdown
            if (_projectStats.isNotEmpty) ...[
              _SectionCard(children: [
                const Text('Projects',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: claudeOrange)),
                const SizedBox(height: 8),
                ..._projectStats.take(5).map((p) => _ProjectRow(
                      stats: p,
                      maxTokens: _projectStats.first.totalTokens,
                    )),
              ]),
              const SizedBox(height: 12),
            ],

            // Recent Activity
            if (_recentSessions.isNotEmpty) ...[
              _SectionCard(children: [
                const Text('Recent Activity',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: claudeOrange)),
                const SizedBox(height: 8),
                ..._recentSessions
                    .map((s) => _RecentSessionRow(session: s)),
              ]),
              const SizedBox(height: 12),
            ],

            // Extra Usage
            if (_account != null)
              _SectionCard(children: [
                const Text('Extra Usage',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: claudeOrange)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      _account!.hasExtraUsage
                          ? Icons.check_circle
                          : Icons.cancel_outlined,
                      size: 14,
                      color: _account!.hasExtraUsage
                          ? Colors.green
                          : Colors.white38,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _account!.hasExtraUsage
                          ? 'Enabled'
                          : 'Not enabled',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ],
                ),
              ]),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(color: Colors.red, fontSize: 11)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.white38),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 12, color: Colors.white70),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

// --- Widgets ---

class _RefreshButton extends StatefulWidget {
  final VoidCallback onRefresh;
  const _RefreshButton({required this.onRefresh});

  @override
  State<_RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<_RefreshButton> {
  bool _refreshing = false;

  Future<void> _handleRefresh() async {
    setState(() => _refreshing = true);
    widget.onRefresh();
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: _refreshing
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: claudeOrange))
          : const Icon(Icons.refresh, size: 16),
      color: Colors.white38,
      onPressed: _refreshing ? null : _handleRefresh,
      tooltip: 'Refresh',
      iconSize: 16,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final List<Widget> children;
  const _SectionCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: claudeSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _UsageCard extends StatelessWidget {
  final RateLimitInfo info;
  const _UsageCard({required this.info});

  @override
  Widget build(BuildContext context) {
    final pct = info.percentUsed;
    final barColor = pct >= 90
        ? Colors.red.shade400
        : pct >= 70
            ? claudeOrange
            : claudeOrangeLight;

    return _SectionCard(children: [
      Row(
        children: [
          Text(info.displayName,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white)),
          const Spacer(),
          Text(
            '${info.formattedTokens} tokens',
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: claudeOrange),
          ),
        ],
      ),
      const SizedBox(height: 8),
      if (info.isCritical) ...[
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 10,
                  child: LinearProgressIndicator(
                    value: info.utilization!,
                    backgroundColor: claudeBarBg,
                    valueColor: AlwaysStoppedAnimation<Color>(barColor),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text('$pct% used',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: barColor)),
          ],
        ),
        const SizedBox(height: 4),
      ] else
        Row(
          children: [
            Icon(Icons.check_circle, size: 13, color: Colors.green.shade400),
            const SizedBox(width: 6),
            Text('Below rate limit threshold',
                style: TextStyle(fontSize: 11, color: Colors.green.shade400)),
          ],
        ),
      const SizedBox(height: 4),
      Text(info.resetTimeFormatted,
          style: TextStyle(
              fontSize: 11, color: Colors.white.withValues(alpha: 0.45))),
    ]);
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _MiniStat(
      {required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 16, color: claudeOrange),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(fontSize: 10, color: Colors.white38)),
        ],
      ),
    );
  }
}

class _ProjectRow extends StatelessWidget {
  final ProjectStats stats;
  final int maxTokens;
  const _ProjectRow({required this.stats, required this.maxTokens});

  @override
  Widget build(BuildContext context) {
    final fraction = maxTokens > 0 ? stats.totalTokens / maxTokens : 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.folder_outlined, size: 12, color: Colors.white38),
              const SizedBox(width: 6),
              Expanded(
                child: Text(stats.name,
                    style:
                        const TextStyle(fontSize: 11, color: Colors.white70),
                    overflow: TextOverflow.ellipsis),
              ),
              Text(stats.formattedTokens,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: claudeOrangeLight)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: LinearProgressIndicator(
                value: fraction,
                backgroundColor: claudeBarBg,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(claudeOrange),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${stats.sessionCount} sessions  •  ${stats.messageCount} messages',
            style: TextStyle(
                fontSize: 10, color: Colors.white.withValues(alpha: 0.35)),
          ),
        ],
      ),
    );
  }
}

class _RecentSessionRow extends StatelessWidget {
  final RecentSession session;
  const _RecentSessionRow({required this.session});

  @override
  Widget build(BuildContext context) {
    final timeAgo = _timeAgo(session.timestamp);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.chat_outlined, size: 12,
              color: Colors.white.withValues(alpha: 0.3)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(session.prompt,
                    style:
                        const TextStyle(fontSize: 11, color: Colors.white70),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text('$timeAgo  •  ${session.project}',
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: 0.35))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d').format(dt);
  }
}
