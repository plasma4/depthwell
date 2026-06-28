Codebase tasks:

- Fix strange issue with interpolation/movement of indicators when camera moves being off (acts jerky by a frame)
- Implement drag-and-drop for furnace smelting of ores; progress bar should move and reset instantly if item is added/removed
    - Note that since ore-forms of metals are supposed to be useless, a very simple "drag-all-at-once" is precisely the goal
    - Smelting should be paused if the menu is "closed"
- Improve performance of water, potentially by changing the algorithm
    - The bottleneck is primarily that even if there are 1-2 water blocks per chunk, performance decreases
    - Additionally, there is a very significant lag spike when first adding water to a chunk through manual modification
- Switch out naive value noise in procedural.zig when use_f2_f1 is false for a potentially hybrid and performant algorithm
    - Must analyze clock cycles/practically test to make sre it is no more than twice/frame
- Create a performance testing system that benchmarks random chunk generation and water (can override procedural data, etc.).
    - Must be 0-cost in Release+no FORCE_DEBUG
- Evaluate performancee
- Evaluate places with "harmful inlining", especially higher up the abstraction chain
    - Evaluate a special case of inlining where functions like `state.procedural.getFbmWorleyValue` have anon variants (`__anon_18709`), potentially due to comptime splitting the function up
    - Determine if more specific benchmarking programming is needed
- Evaluate whether Chromium Performance testing is acceptable for WASM, especially on modern Apple devices
    - Determine the reliability of CPU throttling and WGSL testing
    - Develop robust, consistent heuristics that target (most) WebGPU-supporting laptops in the past 4 years
        - As in: rules of thumb with margins like "0.25 second load time on M5 MacBook Pro" because that means chunk loading is faster than 1ms, or "10000 SIMT cycles per WGSL shader pixel" because 1 TFLOP very roughly is near that amount with modern frame rates/DPI.
        - Determine if ReleaseFast being ~2.5-3x faster vs. Debug will probably continue to hold up
- Do an analysis of robustness and extensibility, and refactor functions and areas as necessary
    - See if more sprite type-based data can be moved to sprite.zig; see if sprite.zig could be modified in a way that plays nice with ZLS autocomplete
- Create actual biomes with real differentiators
    - Determine what procedural algorithm to use
    - Use different blocks
    - Create more base-depth structures

Art tasks:

- Draw bar forms of ore as sprites
- Draw character sprites
- Biome-specific stuff/plants
