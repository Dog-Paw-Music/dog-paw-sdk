# hello_dogpaw

Minimal Dog Paw teaching example.

This example keeps the app structure intentionally small:

- `main.dart` composes the app and controller
- `controllers/hello_controller.dart` owns startup connection, endpoint setup,
  key polling, and retained LED highlight updates
- `app.dart` renders one screen with two color-control rows

On startup the app connects automatically, creates one key input endpoint plus
one LED output endpoint, and listens for `BladeHW::key_press` messages. Active
and pressed key states map to user-selectable highlight colors, while rest
state clears the retained highlight for that key.
