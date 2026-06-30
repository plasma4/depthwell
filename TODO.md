Codebase tasks:

- Create a performance testing system that benchmarks random chunk generation and water (can override procedural data, etc.).
    - Must be 0-cost in Release+no FORCE_DEBUG
- Evaluate places with "harmful inlining", especially higher up the abstraction chain
    - Evaluate a special case of inlining where functions like `state.procedural.getFbmValue` have anon variants (`__anon_18709`), potentially due to comptime splitting the function up
    - Determine if more specific benchmarking programming is needed
- Evaluate whether Chromium Performance tab testing is acceptable for WASM, especially on modern Apple devices
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
