import { Buffer } from "buffer";
globalThis.Buffer = globalThis.Buffer || Buffer;

// Inject favicon (can't use <link> in HTML — Bun's bundler tries to resolve it)
const link = document.createElement("link");
link.rel = "icon";
link.type = "image/svg+xml";
link.href = "/favicon.svg";
document.head.appendChild(link);
