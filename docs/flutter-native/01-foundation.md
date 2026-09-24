# Slice 1: foundation and shell

## Outcome

Establish the smallest production-shaped Flutter foundation on which every FORM
feature can be added without restructuring the app. An `apps/mobile` scaffold
already exists locally. Audit and evolve it rather than assuming it is complete.

Read [`stage-1-spec.md`](stage-1-spec.md) first. This slice owns every `F1` item
in [`parity-checklist.md`](parity-checklist.md).

## Dependencies

None. Preserve unrelated working-tree changes and the existing PWA.

## Ownership

This slice may change:

- `apps/mobile`
- root ignore rules and local verification scripts needed by the Flutter app
- API root metadata only if contract-version detection genuinely requires it
- the `F1` checklist items

Feature screens remain thin shell pages in this slice.

## Work

1. Audit the existing scaffold against the master spec. Record gaps before
   replacing generated platform files.
2. Pin Flutter 3.44.9 with FVM and configure analysis, package metadata, both
   flavors, identifiers, minimum OS versions, and portrait orientation.
3. Add only the agreed foundational dependencies. Resolve versions compatible
   with the pinned SDK and commit the lock file.
4. Bootstrap `easy_localization`, generated keys, German and English assets,
   the light FORM theme, repository injection, and Bloc observation suitable for
   development logs without personal payloads.
5. Build the `go_router` `StatefulShellRoute` with Feed, Wardrobe, and Settings
   branches. Preserve each branch stack during the process and open Feed after
   a cold launch.
6. Introduce the Dio API boundary, structured error mapping, API availability
   states, personal-session check, and contract-version gate.
7. Introduce Drift and the media-cache index at schema version 1. Create only
   tables justified by the master spec and the next two slices.
8. Implement stale-while-refresh primitives and read-only offline capability as
   repository behavior. Connectivity signals are hints. Request results remain
   authoritative.
9. Add focused unit tests and the local verification command.
10. Update every owned checklist item with evidence or a concise unresolved
    note.

## Unit tests

- environment and flavor configuration parsing
- contract-version compatibility decisions
- API error-code mapping
- initial locale and persisted locale selection
- stale cache versus successful and failed refresh decisions
- Drift migrations introduced by this slice
- non-trivial shell or connectivity Cubit transitions

## Completion criteria

- Every `F1` checklist item is checked.
- Feed, Wardrobe, and Settings launch in German and English.
- Independent tab stacks survive tab switches.
- Unavailable API, missing personal session, incompatible API, empty data, and
  loaded data render as distinct states.
- The app contains no feature implementation that belongs to a later slice.
- `fvm flutter analyze` and `fvm flutter test` pass.

## Exclusions

Wardrobe behavior, intake, looks, character-reference workflows, settings
features, login, monetization, telemetry, and store delivery remain in later
slices or later product stages.

