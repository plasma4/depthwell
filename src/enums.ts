// This is a dynamically generated file from generate_types.zig for use in engine.ts.

/**
 * A pointer in the WASM memory.
 */
export type Pointer = number;

/**
 * Configuration options for the GameEngine.
 */
export interface EngineOptions {
  highPerformance?: boolean;
}

// See the folders in /zig for more detailed documentation.
export interface EngineExports extends WebAssembly.Exports {
  readonly memory: WebAssembly.Memory;

  readonly init: () => void;
  readonly reset: () => void;
  readonly tick: () => void;
  readonly renderFrame: () => void;
  readonly execute_commands: () => void;
  readonly wasm_seed_from_string: () => void;
  readonly get_memory_layout_ptr: () => Pointer;
  readonly wasm_alloc: (arg0: number) => Pointer;
  readonly wasm_free: (arg0: Pointer, arg1: number) => void;
  readonly isDebug: () => 0 | 1;
}

export enum Command {
  Reset = 0,
  Begin = 1,
  Exit = 2,
  SendSeed = 3,
}
