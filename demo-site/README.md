# Browser demo (built)

The Task Plus app built for the browser in demo mode (`app/lib/demo/main_demo.dart`): sample data, no server.
Vercel serves this folder as static files (`vercel.json` at the repo root). Rebuild after app changes:

```sh
cd app
flutter build web -t lib/demo/main_demo.dart --release --no-web-resources-cdn --pwa-strategy=none
# then copy flutter.js, main.dart.js, canvaskit/canvaskit.{js,wasm} and assets/ into ../demo-site
```
