import { defineConfig } from "vite";
import glsl from "vite-plugin-glsl";

export default defineConfig({
    base: "",
    plugins: [
        glsl({
            minify: true,
        }),
        {
            name: "watch-wasm",
            configureServer(server) {
                server.watcher.add("src/main.wasm");

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
