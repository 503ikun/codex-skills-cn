---
name: chrome
description: "Use the user's external Google Chrome browser through the Codex Chrome extension. Trigger when the user says @chrome, asks to use Chrome, inspect current Chrome tabs, control an existing Chrome page, or browse with the installed Codex Chrome extension."
---

# Chrome

Use this skill when the user wants Codex to control the external Google Chrome browser through the Codex Chrome extension.

## Runtime

Use the bundled Browser Use runtime with the `chrome` backend:

```js
const { setupAtlasRuntime } = await import("C:/Users/Administrator/.codex/.tmp/bundled-marketplaces/openai-bundled/plugins/browser-use/scripts/browser-client.mjs");
const backend = "chrome";
await setupAtlasRuntime({ globals: globalThis, backend });
```

After setup, use `agent.browser.*` APIs. Prefer existing Chrome tabs when the user refers to an already-open page.

If setup fails, first confirm that the Codex Chrome extension is installed and that `C:\Users\Administrator\AppData\Local\OpenAI\Codex\ChromeNativeHost\CodexChromeNativeHost.exe` is running or can be launched by Chrome.
