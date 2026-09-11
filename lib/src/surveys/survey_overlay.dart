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
  }

  @override
  void dispose() {
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
    final accent = widget.accentColor ?? theme.primaryColor;

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
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _canSubmit() ? _submit : null,
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                child: const Text('Submit'),
              ),
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
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(11, (i) {
            final isSelected = _selectedScore == i;
            return GestureDetector(
              onTap: () => setState(() => _selectedScore = i),
              child: Container(
                width: 26,
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
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? Colors.white : null,
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
            Text('0 - Not at all', style: TextStyle(fontSize: 10, color: Colors.grey)),
            Text('10 - Extremely likely', style: TextStyle(fontSize: 10, color: Colors.grey)),
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
