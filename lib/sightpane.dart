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

/// sightpane — error tracking (Sentry style), product analytics (PostHog
/// style) and session replay that works on every platform.
///
/// Session replay is built on frame images of the [SightpaneReplay] boundary rather
/// than on the DOM, which is why it behaves the same on web, desktop and
/// mobile.
library;

export 'src/breadcrumbs.dart' show BreadcrumbBuffer;
export 'src/device.dart' show SightpaneDevice;
export 'src/client.dart'
    show Sightpane, SightpaneClient, SightpaneSpan, SightpaneTransaction;
export 'src/http_client.dart' show SightpaneHttpClient;
export 'src/models.dart';
export 'src/options.dart';
export 'src/queue.dart' show SightpaneQueue;
export 'src/replay/mask.dart'
    show SightpaneMask, MaskRegistry, SightpaneUnmask, HogUnmask, UnmaskRegistry;
export 'src/replay/recorder.dart' show ReplayRecorder;
export 'src/replay/replay_widget.dart' show SightpaneReplay;
export 'src/session.dart' show SightpaneSession;
export 'src/storage.dart'
    show SightpaneStorage, InMemorySightpaneStorage, FileSightpaneStorage;
export 'src/transport.dart' show SightpaneTransport, HttpTransport;
export 'src/widgets/navigator_observer.dart' show SightpaneNavigatorObserver;
export 'src/widgets/user_interaction.dart'
    show SightpaneUserInteractionWidget, describeTapTarget;
export 'src/surveys/survey_overlay.dart'
    show SightpaneSurveyCard, SurveyPrompt, SurveyAnswer, SurveyType;
