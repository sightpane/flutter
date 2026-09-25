// sightpane — error tracking, product analytics and session replay you host yourself.
// Copyright (C) 2026 Can Us
//
// Licensed under the Apache License, Version 2.0 (the "License"); you may not
// use this file except in compliance with the License. You may obtain a copy of
// the License at <http://www.apache.org/licenses/LICENSE-2.0>. Unless required
// by applicable law or agreed to in writing, software distributed under the
// License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS
// OF ANY KIND, either express or implied.
//
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../client.dart';
import '../models.dart';

/// Type of in-app survey question.
enum SurveyType {
  nps,
  csat,
  rating,
  openText,
  singleChoice,
}

/// In-app survey targeting rules.
class SurveyTargeting {
  const SurveyTargeting({
    this.urlPattern,
    this.eventTrigger,
    this.sampleRate = 1.0,
  });

  final String? urlPattern;
  final String? eventTrigger;
  final double sampleRate;

  factory SurveyTargeting.fromJson(Map<String, dynamic> json) {
    return SurveyTargeting(
      urlPattern: json['url_pattern'] as String?,
      eventTrigger: json['event_trigger'] as String?,
      sampleRate: (json['sample_rate'] as num?)?.toDouble() ?? 1.0,
    );
  }

  Map<String, dynamic> toJson() => {
    if (urlPattern != null) 'url_pattern': urlPattern,
    if (eventTrigger != null) 'event_trigger': eventTrigger,
    'sample_rate': sampleRate,
  };

  bool matchesRoute(String? route) {
    if (urlPattern == null || urlPattern!.trim().isEmpty) return true;
    if (route == null || route.trim().isEmpty) return false;
    final pattern = urlPattern!.trim();
    final current = route.trim();
    if (pattern == current) return true;

    final cleanCurrent = current.replaceAll(RegExp(r'^#'), '');
    final cleanPattern = pattern.replaceAll(RegExp(r'^#'), '');
    if (cleanPattern == cleanCurrent) return true;

    final normCurrent = cleanCurrent.endsWith('/') && cleanCurrent.length > 1
        ? cleanCurrent.substring(0, cleanCurrent.length - 1)
        : cleanCurrent;
    final normPattern = cleanPattern.endsWith('/') && cleanPattern.length > 1
        ? cleanPattern.substring(0, cleanPattern.length - 1)
        : cleanPattern;
    if (normPattern == normCurrent) return true;

    if (cleanPattern.endsWith('*')) {
      final prefix = cleanPattern.substring(0, cleanPattern.length - 1);
      return cleanCurrent.startsWith(prefix);
    }
    return false;
  }
}

/// In-app survey configuration from Sightpane backend.
class SightpaneSurvey {
  const SightpaneSurvey({
    required this.id,
    required this.name,
    required this.type,
    required this.question,
    this.description = '',
    this.choices = const [],
    this.targeting = const SurveyTargeting(),
    this.active = true,
  });

  final String id;
  final String name;
  final SurveyType type;
  final String question;
  final String description;
  final List<String> choices;
  final SurveyTargeting targeting;
  final bool active;

  factory SightpaneSurvey.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? 'nps';
    final type = switch (typeStr) {
      'csat' => SurveyType.csat,
      'rating' => SurveyType.rating,
      'open_text' || 'openText' => SurveyType.openText,
      'single_choice' || 'singleChoice' => SurveyType.singleChoice,
      _ => SurveyType.nps,
    };

    final targetingJson = json['targeting'];
    final targeting = targetingJson is Map<String, dynamic>
        ? SurveyTargeting.fromJson(targetingJson)
        : const SurveyTargeting();

    final choicesRaw = json['choices'];
    final choices = choicesRaw is List
        ? choicesRaw.map((e) => e.toString()).toList()
        : const <String>[];

    return SightpaneSurvey(
      id: json['id'].toString(),
      name: json['name'] as String? ?? '',
      type: type,
      question: json['question'] as String? ?? '',
      description: json['description'] as String? ?? '',
      choices: choices,
      targeting: targeting,
      active: json['active'] as bool? ?? true,
    );
  }

  SurveyPrompt toPrompt() => SurveyPrompt(
    id: id,
    type: type,
    question: question,
    description: description,
    choices: choices,
  );
}

/// In-app survey question definition.
class SurveyPrompt {
  const SurveyPrompt({
    required this.id,
    required this.type,
    required this.question,
    this.description = '',
    this.choices = const [],
  });

  final String id;
  final SurveyType type;
  final String question;
  final String description;
  final List<String> choices;
}

/// Completed survey answer submitted by the user.
class SurveyAnswer {
  const SurveyAnswer({
    required this.surveyId,
    this.score,
    this.responseText = '',
  });

  final String surveyId;
  final int? score;
  final String responseText;
}

/// Non-intrusive in-app survey card widget.
class SightpaneSurveyCard extends StatefulWidget {
  const SightpaneSurveyCard({
    super.key,
    required this.prompt,
    required this.onSubmit,
    this.onDismiss,
    this.accentColor,
    this.backgroundColor,
  });

  final SurveyPrompt prompt;
  final ValueChanged<SurveyAnswer> onSubmit;
  final VoidCallback? onDismiss;
  final Color? accentColor;
  final Color? backgroundColor;

  @override
  State<SightpaneSurveyCard> createState() => _SightpaneSurveyCardState();
}

class _SightpaneSurveyCardState extends State<SightpaneSurveyCard> {
  int? _selectedScore;
  String? _selectedChoice;
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _textController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    super.dispose();
  }

  void _submit() {
    int? score = _selectedScore;
    String text = _textController.text.trim();
    if (widget.prompt.type == SurveyType.singleChoice) {
      text = _selectedChoice ?? '';
    }

    final answer = SurveyAnswer(
      surveyId: widget.prompt.id,
      score: score,
      responseText: text,
    );

    // Record breadcrumb on the session timeline
    String scoreDesc = score != null ? ' with score $score' : '';
    if (text.isNotEmpty && score == null) {
      scoreDesc = ': "$text"';
    }
    final data = <String, Object?>{
      'survey_id': widget.prompt.id,
    };
    if (score != null) {
      data['score'] = score;
    }
    if (text.isNotEmpty) {
      data['response'] = text;
    }

    Sightpane.addBreadcrumb(SightpaneBreadcrumb(
      category: 'survey',
      message: 'Answered ${widget.prompt.type.name} survey$scoreDesc',
      level: SightpaneLevel.info,
      data: data,
    ));

    widget.onSubmit(answer);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = widget.backgroundColor ?? (isDark ? const Color(0xFF1E1E24) : Colors.white);
    final accent = widget.accentColor ?? theme.colorScheme.primary;

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.prompt.question,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (widget.prompt.description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          widget.prompt.description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (widget.onDismiss != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: widget.onDismiss,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _buildInputControl(accent),
            const SizedBox(height: 14),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _textController,
              builder: (context, _, _) {
                final canSubmit = _canSubmit();
                return Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: canSubmit ? _submit : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    child: const Text('Submit'),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  bool _canSubmit() {
    switch (widget.prompt.type) {
      case SurveyType.nps:
      case SurveyType.csat:
      case SurveyType.rating:
        return _selectedScore != null;
      case SurveyType.singleChoice:
        return _selectedChoice != null;
      case SurveyType.openText:
        return _textController.text.trim().isNotEmpty;
    }
  }

  Widget _buildInputControl(Color accent) {
    switch (widget.prompt.type) {
      case SurveyType.nps:
        return _buildNPSScale(accent);
      case SurveyType.csat:
      case SurveyType.rating:
        return _buildStarOrRatingScale(accent, maxScore: widget.prompt.type == SurveyType.csat ? 5 : 5);
      case SurveyType.singleChoice:
        return _buildSingleChoice(accent);
      case SurveyType.openText:
        return _buildOpenText();
    }
  }

  Widget _buildNPSScale(Color accent) {
    return Column(
      children: [
        Row(
          children: List.generate(11, (i) {
            final isSelected = _selectedScore == i;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: GestureDetector(
                  onTap: () => setState(() => _selectedScore = i),
                  child: Container(
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected ? accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isSelected ? accent : Colors.grey.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      '$i',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? Colors.white : null,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 6),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                '0 - Not at all',
                style: TextStyle(fontSize: 10, color: Colors.grey),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                '10 - Extremely likely',
                style: TextStyle(fontSize: 10, color: Colors.grey),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStarOrRatingScale(Color accent, {required int maxScore}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(maxScore, (index) {
        final score = index + 1;
        final isSelected = _selectedScore != null && _selectedScore! >= score;
        return IconButton(
          icon: Icon(
            isSelected ? Icons.star : Icons.star_border,
            color: isSelected ? (widget.accentColor ?? Colors.amber) : Colors.grey,
            size: 28,
          ),
          onPressed: () => setState(() => _selectedScore = score),
        );
      }),
    );
  }

  Widget _buildSingleChoice(Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widget.prompt.choices.map((choice) {
        final isSelected = _selectedChoice == choice;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: InkWell(
            onTap: () => setState(() => _selectedChoice = choice),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isSelected ? accent : Colors.grey.withValues(alpha: 0.3),
                  width: isSelected ? 1.5 : 1.0,
                ),
                color: isSelected ? accent.withValues(alpha: 0.08) : Colors.transparent,
              ),
              child: Text(choice, style: const TextStyle(fontSize: 13)),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildOpenText() {
    return TextField(
      controller: _textController,
      maxLines: 3,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: 'Share your feedback...',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.all(10),
      ),
    );
  }
}

/// In-app survey overlay that monitors navigation route changes, evaluates survey targeting
/// rules, and displays interactive survey cards when criteria are met.
class SightpaneSurveyOverlay extends StatefulWidget {
  const SightpaneSurveyOverlay({
    super.key,
    required this.child,
    this.accentColor,
    this.backgroundColor,
    this.activeSurveys,
  });

  final Widget child;
  final Color? accentColor;
  final Color? backgroundColor;

  /// Optional preloaded surveys. If null, surveys are fetched from the Sightpane backend.
  final List<SightpaneSurvey>? activeSurveys;

  @override
  State<SightpaneSurveyOverlay> createState() => SightpaneSurveyOverlayState();
}

class SightpaneSurveyOverlayState extends State<SightpaneSurveyOverlay> {
  List<SightpaneSurvey>? _surveys;
  SightpaneSurvey? _activeSurvey;
  bool _visible = false;
  bool _submitted = false;
  final Set<String> _dismissedOrCompleted = <String>{};
  final math.Random _random = math.Random();
  Timer? _dismissTimer;
  StreamSubscription<String>? _events;

  @override
  void initState() {
    super.initState();
    if (widget.activeSurveys != null) {
      _surveys = List.of(widget.activeSurveys!);
      _evaluateTargeting(Sightpane.maybeClient?.currentRoute);
    } else {
      _fetchSurveys();
    }
    Sightpane.maybeClient?.routeNotifier.addListener(_onRouteChanged);
    _events = Sightpane.maybeClient?.capturedEvents.listen(_onEvent);
  }

  @override
  void didUpdateWidget(SightpaneSurveyOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeSurveys != oldWidget.activeSurveys && widget.activeSurveys != null) {
      _surveys = List.of(widget.activeSurveys!);
      _evaluateTargeting(Sightpane.maybeClient?.currentRoute);
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _events?.cancel();
    Sightpane.maybeClient?.routeNotifier.removeListener(_onRouteChanged);
    super.dispose();
  }

  Future<void> _fetchSurveys() async {
    try {
      final client = Sightpane.maybeClient;
      if (client != null) {
        final fetched = await client.fetchActiveSurveys();
        if (mounted) {
          setState(() {
            _surveys = fetched;
          });
          _evaluateTargeting(client.currentRoute);
        }
      }
    } catch (_) {
      // Ignore network errors on survey fetch
    }
  }

  void _onRouteChanged() {
    final route = Sightpane.maybeClient?.currentRoute;
    _evaluateTargeting(route);
  }

  void _onEvent(String event) =>
      _evaluateTargeting(Sightpane.maybeClient?.currentRoute, event: event);

  /// Evaluates targeting rules against current route and event.
  void evaluateTargeting({String? route, String? event}) {
    _evaluateTargeting(route ?? Sightpane.maybeClient?.currentRoute, event: event);
  }

  void _evaluateTargeting(String? route, {String? event}) {
    if (!mounted || _activeSurvey != null || _surveys == null || _surveys!.isEmpty) {
      return;
    }

    for (final survey in _surveys!) {
      if (!survey.active) continue;
      if (_dismissedOrCompleted.contains(survey.id)) continue;

      // Event trigger check. An event only shows the surveys waiting for it:
      // the others are shown on navigation, and rolling their sample rate again
      // on every event would show them far more often than asked.
      final trigger = survey.targeting.eventTrigger;
      if (trigger != null && trigger.isNotEmpty) {
        if (event != trigger) continue;
      } else if (event != null) {
        continue;
      }

      // Route check
      if (!survey.targeting.matchesRoute(route)) {
        continue;
      }

      // Sample rate check
      if (survey.targeting.sampleRate < 1.0) {
        if (_random.nextDouble() > survey.targeting.sampleRate) {
          continue;
        }
      }

      // Trigger this survey!
      setState(() {
        _activeSurvey = survey;
        _visible = true;
        _submitted = false;
      });
      break;
    }
  }

  void _handleDismiss() {
    if (_activeSurvey == null) return;
    _dismissedOrCompleted.add(_activeSurvey!.id);
    _hide();
  }

  Future<void> _handleSubmit(SurveyAnswer answer) async {
    final surveyId = _activeSurvey?.id ?? answer.surveyId;
    _dismissedOrCompleted.add(surveyId);

    // Call backend
    await Sightpane.maybeClient?.submitSurveyResponse(
      surveyId: surveyId,
      score: answer.score,
      responseText: answer.responseText,
    );

    if (!mounted) return;
    setState(() {
      _submitted = true;
    });

    _dismissTimer?.cancel();
    _dismissTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        _hide();
      }
    });
  }

  void _hide() {
    setState(() {
      _visible = false;
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _activeSurvey = null;
          _submitted = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isMobile = size.width < 540;

    return Stack(
      children: [
        widget.child,
        if (_activeSurvey != null)
          // The card gets an Overlay of its own. Mounted in MaterialApp.builder,
          // as the README shows, this widget sits beside the Navigator rather
          // than under it, and the open-text TextField needs an Overlay
          // ancestor for its selection handles and toolbar. Outside the card
          // the layer is transparent to taps.
          Positioned.fill(
            child: Overlay.wrap(
              child: Stack(
                children: [
                  Positioned(
                    left: isMobile ? 16 : null,
                    right: 16,
                    // No Scaffold between here and the keyboard to lift the
                    // card, so it moves up by the keyboard's height itself.
                    bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
                    width: isMobile ? null : 380,
                    child: AnimatedSlide(
                      offset: _visible ? Offset.zero : const Offset(0, 1.2),
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      child: AnimatedOpacity(
                        opacity: _visible ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 250),
                        child: _submitted
                            ? _buildThankYouCard(context)
                            : SightpaneSurveyCard(
                                key: ValueKey(_activeSurvey!.id),
                                prompt: _activeSurvey!.toPrompt(),
                                onSubmit: _handleSubmit,
                                onDismiss: _handleDismiss,
                                accentColor: widget.accentColor,
                                backgroundColor: widget.backgroundColor,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildThankYouCard(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = widget.backgroundColor ?? (isDark ? const Color(0xFF1E1E24) : Colors.white);
    final accent = widget.accentColor ?? theme.primaryColor;

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: accent, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Thank you for your feedback!',
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

