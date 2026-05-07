---
phase: 4
plan: "02"
title: "Event + subscriber generators (track_relay:event NAME, track_relay:subscriber NAME)"
status: complete
completed: 2026-05-07
tasks_completed: 5
tasks_total: 5
commit_hashes:
  - 5a8a23e
  - 2974f78
  - 5b5b74a
  - 371c36a
deviations: []
pre_existing_issues: []
ac_results:
  - criterion: "EventGenerator < Rails::Generators::NamedBase; produces ONE file per event under config/track_relay/<file_name>.rb"
    verdict: pass
    evidence: "lib/generators/track_relay/event/event_generator.rb (commit 5a8a23e)"
  - criterion: "SubscriberGenerator < Rails::Generators::NamedBase; produces ONE file under app/track_relay/subscribers/<file_name>_subscriber.rb (path matches plan 04-01)"
    verdict: pass
    evidence: "lib/generators/track_relay/subscriber/subscriber_generator.rb (commit 5b5b74a)"
  - criterion: "Each generated event is its own catalog block: TrackRelay.catalog do ... end — never appends to existing files"
    verdict: pass
    evidence: "lib/generators/track_relay/event/templates/event.rb.tt (commit 2974f78)"
  - criterion: "Subscriber template uses NamedBase ERB vars file_name and class_name correctly"
    verdict: pass
    evidence: "lib/generators/track_relay/subscriber/templates/subscriber.rb.tt (commit 371c36a)"
  - criterion: "Both generators are non-interactive and follow Devise/ActiveAdmin conventions"
    verdict: pass
    evidence: "Both generators have a single action method and no user prompts; smoke-test ruby probe loaded both classes successfully"
  - criterion: "lib/generators/track_relay/event/event_generator.rb provides EventGenerator class containing class EventGenerator < Rails::Generators::NamedBase"
    verdict: pass
    evidence: "commit 5a8a23e; grep verified"
  - criterion: "lib/generators/track_relay/event/templates/event.rb.tt provides event catalog stub template containing event :<%= file_name %>"
    verdict: pass
    evidence: "commit 2974f78; grep verified"
  - criterion: "lib/generators/track_relay/subscriber/subscriber_generator.rb provides SubscriberGenerator class containing class SubscriberGenerator < Rails::Generators::NamedBase"
    verdict: pass
    evidence: "commit 5b5b74a; grep verified"
  - criterion: "lib/generators/track_relay/subscriber/templates/subscriber.rb.tt provides subscriber class stub template containing <%= class_name %>Subscriber < TrackRelay::Subscribers::Base"
    verdict: pass
    evidence: "commit 371c36a; grep verified"
  - criterion: "event_generator.rb links to templates/event.rb.tt via template"
    verdict: pass
    evidence: "template \"event.rb.tt\", \"config/track_relay/#{file_name}.rb\" call site"
  - criterion: "subscriber_generator.rb links to templates/subscriber.rb.tt via template"
    verdict: pass
    evidence: "template \"subscriber.rb.tt\", \"app/track_relay/subscribers/#{file_name}_subscriber.rb\" call site"
  - criterion: "subscriber generator output path matches install generator output path (app/track_relay/subscribers/) — shared convention from 04-01"
    verdict: pass
    evidence: "Both subscriber_generator.rb and lib/generators/track_relay/install/install_generator.rb#create_application_subscriber emit into app/track_relay/subscribers/"
---

Shipped `rails g track_relay:event NAME` and `rails g track_relay:subscriber NAME` as two NamedBase generators producing self-contained, non-interactive stubs that match the install generator's path conventions from plan 04-01.

## What Was Built

- EventGenerator emitting `config/track_relay/<file_name>.rb` with a self-contained `TrackRelay.catalog do ... end` block (Railtie globs and merges)
- Event template covering all 5 supported param types (integer/string/float/boolean/datetime) as commented stubs
- SubscriberGenerator emitting `app/track_relay/subscribers/<file_name>_subscriber.rb` (matches 04-01 ApplicationSubscriber path)
- Subscriber template subclassing `TrackRelay::Subscribers::Base` (not ApplicationSubscriber, so it works pre-install) with documented payload shape, commented `synchronous!`, `filter only:`, and registration block
- Verified both classes load via ruby probe; full suite still 392/0

## Files Modified

- `lib/generators/track_relay/event/event_generator.rb` -- created: EventGenerator class with `create_event_file` action templating to `config/track_relay/#{file_name}.rb`
- `lib/generators/track_relay/event/templates/event.rb.tt` -- created: event catalog stub with NamedBase ERB substitutions and 5-type param hints
- `lib/generators/track_relay/subscriber/subscriber_generator.rb` -- created: SubscriberGenerator class with `create_subscriber_file` action templating to `app/track_relay/subscribers/#{file_name}_subscriber.rb`
- `lib/generators/track_relay/subscriber/templates/subscriber.rb.tt` -- created: subscriber stub subclassing `TrackRelay::Subscribers::Base` with `def deliver(payload)` body, payload-shape comments, and registration example

## Deviations

None.
