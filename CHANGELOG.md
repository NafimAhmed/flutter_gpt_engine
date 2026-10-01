## 0.0.11

- Replaced broad keyword-only automatic web-search triggering with contextual intent analysis.
- Added English, Bangla, and common Banglish detection for fresh/live information, current roles, recommendations, nearby discovery, evidence requests, and explicit web lookups.
- Added inspectable search decisions through `analyzeWebSearchIntent()`.
- Added a refined-query retry when the first Google HTML search produces no usable result.
- Reduced false-positive searches for stable concepts such as version control, source code, online learning, and SQL update operations.
- Restricted official-source hints to relevant version/release/docs queries instead of every technical query.

## 0.0.10

- Emergency privacy patch: removed device-location collection and runtime location permission requests.
- Removed `geolocator` and `geocoding` dependencies.
- Removed coarse/fine location permissions from the example Android manifest.
- Removed location-backed reverse geocoding and current-weather collection.
- Kept legacy location configuration/helper APIs as no-op compatibility shims so existing integrations keep compiling.

## 0.0.9

- Added opt-in Fast, Balanced, and Quality mobile performance presets.
- Added token-aware history budgeting and safe output-token sizing.
- Added warm-up plus median multi-run benchmarking for more stable tuning.
- Added persistent auto-tune profiles restored for the same GGUF model.
- Added CPU-vs-GPU verification diagnostics without changing the active profile.
- Preserved the existing default generation configuration and public APIs.

## 0.0.8
- More optimized.
## 0.0.7

- Reduced token-stream parsing allocations with an incremental reasoning parser.
- Coalesced ChangeNotifier generation updates for smoother Flutter UIs.
- Reused HTTP connections and parallelized web source fetching.
- Added bounded conversation-history context.
- Added local TTFT / token-throughput benchmarking.
- Added opt-in CPU/GPU auto-tuning for the current device and GGUF model.

## 0.0.8

- More optimized.

## 0.0.7

- More optimized.
## 0.0.6

- device state analysis integrated.


## 0.0.5

- Web search added.

## 0.0.4

- Web search added.


## 0.0.3

- More user friendly.


## 0.0.2

- More user friendly.


## 0.0.1

- Initial package.
