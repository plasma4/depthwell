/// <reference types="vite/client" />
"use strict";

/**
 * Debug/testing options. Set all values to false in production.
 * TODO set to false for prod :P
 */
export const CONFIG = {
    /** Whether to expose engine to globalThis or not. */
    exportEngine: true,
    /** Whether to use verbose logging or not. */
    verbose: true,
    /** If set to true, disables alerting on error. Error will always show in console regardless of what this value is set to. */
    noAlertOnError: true,
};

if ("file:" === location.protocol) {
    alert(
        "This game cannot run from a local file:// context; use an online version or test from localhost instead.",
    );
}
if (!isSecureContext) {
    alert("This game cannot run in a non-secure context.");
}

if (!navigator.gpu) {
    alert(
        "WebGPU is not supported by your browser; try playing this on an alternate or more modern browser.",
    );
}

const adapter = await navigator.gpu.requestAdapter();
if (!adapter) {
    alert("WebGPU is supported, but no compatible GPU was found.");
}

import { GameEngine } from "./engine";
import { KeyBits, game_state_offsets } from "./enums";

globalThis.Zig = { KeyBits, game_state_offsets };
if (import.meta.env.DEV) {
    console.log(
        "Zig code is in debug mode. Use engine.exports to see its functions, variables, and memory, such as engine.exports.test_logs.",
    );

    document.body.innerHTML += `
    <div id="textTop">
        <div id="text1"></div>
        <div id="text2"></div>
    </div>
    <div id="textBottom">
        <div id="text3"></div>
        <div id="text4"></div>
    </div>
    <div id="logicText"></div>
    <div id="renderText"></div>
    <div id="debugContainer"></div>`;
} else {
    // Zig is not in debug mode!
    if (CONFIG.verbose) {
        console.log(
            'Note: engine is in verbose mode, but Zig code is not in -Doptimize=Debug; run just "zig build" to enable additional testing features and safety checks if possible.',
        );
    }
}

declare module "./engine" {
    interface GameEngine {
        /** True if Zig is in -Doptimize=Debug mode. */
        isDebug: boolean;
        /** A multipier for how fast logic speed is. */
        baseSpeed: number;
        /** Main render loop. */
        renderLoop: (time: number) => void;
        /** Main logic loop (called from `renderLoop` to prevent frame drops). */
        logicLoop: (ticks: number) => void;
        /**
         * Returns the timeout time between logic frames in milliseconds. Note that the actual logic accounts for lag.
         * Customize the frame rate and timeout to test frame interpolation with this:
            ```ts
            engine.getTimeoutLength = () => 500;
            engine.getFrameRate = () => 2;
            ```
         */
        getTimeoutLength: () => number;
        /**
         * Returns the target logic frame rate.
         * Customize the frame rate and timeout to test frame interpolation with this:
            ```ts
            engine.getTimeoutLength = () => 500;
            engine.getFrameRate = () => 2;
            ```
         */
        getFrameRate: () => number;
    }
}

declare global {
    interface Window {
        engine?: GameEngine;
    }
    var engine: GameEngine | undefined;
    var WasmTypeCode: object;
    var Zig: object;
}

/*
    These global exports allow you to access stuff like memory views from engine.ts easily from the console:
    engine.getGameView(
        WasmTypeCode.Uint64,
        Zig.game_state_offsets.seed,
        8,
    )
*/

// Error-handling logic section!
if (!CONFIG.noAlertOnError) {
    const handleFatalError = (
        error: any,
        source?: any,
        lineno?: any,
        colno?: any,
    ) => {
        const actualError = error || {};
        const message = actualError.message || String(error || "Unknown error");
        let errorMessage = `An error occurred: ${message}`;

        // Safari uses error.line/error.column
        const finalLine = lineno || actualError.line;
        const finalCol = colno || actualError.column;

        if (source || finalLine || finalCol) {
            const fileName = source
                ? source.split("/").pop() || source
                : "unknown";
            errorMessage += `\nSource: ${fileName}:${finalLine || "?"}:${finalCol || "?"}`;
        }

        let err = globalThis.engine?.destroyedError;
        if (globalThis.engine?.destroyedError) {
            errorMessage += `\nDetails: ${err.message || err}`;
        }

        if (actualError.stack) {
            errorMessage += `\n\nStack trace:\n${actualError.stack}`;
        } else if (typeof error === "object" && error !== null) {
            try {
                const json = JSON.stringify(error);
                if (json !== "{}") errorMessage += `\nObject state: ${json}`;
            } catch {
                errorMessage += "\n(Object state hidden: circular reference)";
            }
        }

        alert(errorMessage);
    };

    window.onerror = (message, source, lineno, colno, error) => {
        handleFatalError(error || message, source, lineno, colno);
    };

    window.onunhandledrejection = (e) => {
        handleFatalError(e.reason);
    };

    console.error = (...args) => {
        const error = args.find((arg) => arg instanceof Error) || args[0];
        handleFatalError(error);
    };
}

document.addEventListener(
    "wheel",
    function (e) {
        if (e.ctrlKey) {
            // TODO un-comment out in final version
            // e.preventDefault();
        }
    },
    { passive: false },
);

let engine = await GameEngine.create();

engine.getTimeoutLength = function () {
    return ++frame % 3 == 2 ? 16 : 17;
};

engine.getFrameRate = function () {
    return 60;
};

engine.baseSpeed = 1;

let time = performance.now(),
    accumulator = 0,
    frame = 0;
if (CONFIG.exportEngine) (globalThis as any).engine = engine;
if (CONFIG.verbose) {
    console.log("Engine initialized successfully:", engine);
    console.log("Exported functions and memory:", engine.exports);
}

window.addEventListener("blur", () => (time = Infinity)); // basically, don't let frames when the tab is hidden cause any simulation.

const past60SlowestLogicLoops = Array(60).fill(0);
const past60SlowestRenders = Array(60).fill(0);
const past60SlowestZigRenders = Array(60).fill(0);

// Add custom properties into the engine object (not handled by TypeScript)
engine.isDebug = !!engine.exports.isDebug(); // This function is only true if Doptimize=Debug (default with zig build).
engine.renderLoop = function (_t: number) {
    // TODO back-off logic when frames get skipped, maybe? (due to WebGPU being the bottleneck)

    // simulate to a second/tick of logical simulation, whichever is higher (in practice, a tick will be less than a second, so 1 second)
    let tempTime = performance.now();
    let delta = time === Infinity ? 0 : tempTime - time;
    let newTicks = Math.min(
        (delta * engine.getFrameRate()) / 1000,
        engine.getFrameRate(),
    );

    engine.logicLoop(Math.max(Math.floor(accumulator + newTicks), 1));
    accumulator = (accumulator + newTicks) % 1; // calculate new fractional accumulation of ticks

    if (import.meta.env.DEV) {
        past60SlowestRenders.shift();
        past60SlowestRenders.push(delta);
        past60SlowestZigRenders.shift();
        past60SlowestZigRenders.push(engine.prepare_visible_chunks_time);

        const slowestRender = Math.max.apply(null, past60SlowestRenders);
        const slowestZigRender = Math.max.apply(null, past60SlowestZigRenders);

        // mostly arbitrary color thresholds
        let color = "#cccccc";
        if (slowestRender > 55) {
            color = "#e83769";
        } else if (slowestRender > 30) {
            color = "#f39c19";
        } else if (slowestRender > 20) {
            color = "#f7ce1a";
        }

        const debugElem = document.getElementById(
            "renderText",
        ) as HTMLDivElement;
        debugElem.textContent = `Time since last render/prepare_visible_chunks time: ${delta.toFixed(1)}ms, ${engine.prepare_visible_chunks_time.toFixed(1)}ms
Worst (past 60 frames): ${slowestRender.toFixed(1)}ms, ${slowestZigRender.toFixed(1)}ms`;

        debugElem.style.fontWeight = (
            slowestRender > 40 ? (slowestRender > 55 ? 700 : 600) : 500
        ) as any; // gee thanks TypeScript
        debugElem.style.color = color;
    }

    let timeInterpolated = Math.min(accumulator - 1, 0);
    engine.renderFrame(timeInterpolated, time);

    requestAnimationFrame(engine.renderLoop);
    // setTimeout(engine.renderLoop, 100);
};

engine.logicLoop = function (ticks: number) {
    // Interestingly enough, as ticks becomes large enough, the "imprecision" of the camera (16 possible subpixel positions) results in the player panning being all weird! This only happens past 1000 logical FPS though so it's fine.
    const startTime = performance.now();
    engine.tick((60 / engine.getFrameRate()) * engine.baseSpeed, ticks); // ticks already capped in renderLoop
    time = performance.now();
    let delta = time - startTime;

    if (import.meta.env.DEV) {
        past60SlowestLogicLoops.shift();
        past60SlowestLogicLoops.push(delta);

        const slowestLogicLoop = Math.max.apply(null, past60SlowestLogicLoops);

        // mostly arbitrary color thresholds
        let color = "#cccccc";
        if (slowestLogicLoop > 30) {
            color = "#e83769";
        } else if (slowestLogicLoop > 15) {
            color = "#f39c19";
        } else if (slowestLogicLoop > 10) {
            color = "#f7ce1a";
        }

        const debugElem = document.getElementById(
            "logicText",
        ) as HTMLDivElement;
        debugElem.textContent = `Logic diff: ${delta.toFixed(1)}ms for ${ticks} tick${ticks == 1 ? "" : "s"}\nWorst (past 60 frames): ${slowestLogicLoop.toFixed(1)}ms\n`;
        // new-line in string for copy and paste

        debugElem.style.fontWeight = (
            slowestLogicLoop > 20 ? (slowestLogicLoop > 40 ? 700 : 600) : 500
        ) as any; // gee thanks TypeScript
        debugElem.style.color = color;
    }
};

// Helper to get normalized coordinates and tell Zig
const dispatch = (e: PointerEvent, action: number) => {
    // check if the target is actually the canvas
    if (e.target !== engine.canvas) return;
    // get canvas position relative to the viewport
    const rect = engine.canvas.getBoundingClientRect();
    const x = (e.clientX - rect.left) / rect.width;
    const y = (e.clientY - rect.top) / rect.height;
    if (x >= 0 && x <= 1 && y >= 0 && y <= 1) {
        // only allow if within canvas bounds
        engine.exports.handle_mouse(x, y, action);
    }
};

document.addEventListener("pointermove", (e) => {
    if (e.buttons > 0) dispatch(e, 0); // move while pressing any button
});

document.addEventListener("pointerdown", (e) => {
    const action = e.button === 2 ? 3 : 1;
    dispatch(e, action);
});

document.addEventListener("pointerup", (e) => {
    const action = e.button === 2 ? 4 : 2;
    dispatch(e, action);
});

engine.canvas.style.touchAction = "none"; // prevent touch gesture interception

// Prevent context menu on right-click
document.addEventListener("contextmenu", (e) => e.preventDefault());

// Build the fancy debug UI in the corner!
if (import.meta.env.DEV) {
    const exports = engine.exports as any;

    // Populate scratch buffer with JSON data and parse it
    exports.debug_build_ui_metadata();
    const jsonStr = engine.readStr();

    const meta = JSON.parse(jsonStr);

    const container = document.getElementById(
        "debugContainer",
    ) as HTMLDivElement;
    meta.buttons.forEach((b: any) => {
        const btn = document.createElement("button");
        btn.textContent = b.name;
        btn.onclick = () => exports.debug_ui_button_click(b.id);
        container.appendChild(btn);
    });

    meta.sliders.forEach((s: any) => {
        const wrapper = document.createElement("div");
        wrapper.style.display = "flex";
        wrapper.style.flexDirection = "column";

        const label = document.createElement("label");
        label.textContent = `${s.name}: ${s.val.toFixed(2)}`;
        label.style.fontSize = "12px";

        const input = document.createElement("input");
        input.type = "range";
        input.min = s.min;
        input.max = s.max;
        input.step = ((s.max - s.min) / 1000).toString();
        input.value = s.val;

        input.oninput = (e) => {
            const val = parseFloat((e.target as HTMLInputElement).value);
            label.textContent = `${s.name}: ${val.toFixed(2)}`;
            exports.debug_ui_slider_change(s.id, val);
        };

        wrapper.appendChild(label);
        wrapper.appendChild(input);
        container.appendChild(wrapper);
    });

    document.body.appendChild(container);
}

// Begin the logic
setTimeout(function () {
    engine.renderLoop(0);
}, 17);
