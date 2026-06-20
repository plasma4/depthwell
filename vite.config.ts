import { defineConfig } from "vite";
import glsl from "vite-plugin-glsl";

export default defineConfig({
    base: "",
    plugins: [
        {
            name: "wgsl-conditional-preprocessor",
            enforce: "pre", // execute before normal plugins
            transform(code, id) {
                if (/\.wgsl($|\?)/.test(id)) {
                    let output = code;

                    const regex =
                        /\/\/\s*#ifdef\s+WEB_TARGET\r?\n([\s\S]*?)\/\/\s*#else\r?\n([\s\S]*?)\/\/\s*#endif/g;

                    output = output.replace(
                        regex,
                        (match, webTargetBlock, elseBlock) => {
                            // 1. Uncomment the WEB_TARGET block by removing the leading // part from each line
                            const uncommentedWeb = webTargetBlock.replace(
                                /^\s*\/\/\s?/gm,
                                "",
                            );

                            // Comment out the fallback block by adding // to any line that doesn't have it
                            const commentedElse = elseBlock
                                .split(/\r?\n/)
                                .map((line: string) => {
                                    return line.trim().startsWith("//")
                                        ? line
                                        : `// ${line}`;
                                })
                                .join("\n");

                            // 3. Rebuild the string (keeping the flags for future toggles if needed)
                            return `// #ifdef WEB_TARGET\n${uncommentedWeb}// #else\n${commentedElse}\n// #endif`;
                        },
                    );

                    return {
                        code: output,
                        map: null,
                    };
                }
            },
        },
        glsl({
            minify: false,
        }),
        {
            name: "watch-wasm",
            configureServer(server) {
                server.watcher.add("public/main.wasm");

                // Trigger a full page reload when a watched wasm file changes
                server.watcher.on("change", (file) => {
                    if (file.endsWith(".wasm")) {
                        server.hot.send({ type: "full-reload" });
                    }
                });
            },
        },
    ],
});
