// Separate target for actual Web theme UI checks; excluded from production.
import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:easyplay/main.dart';
import 'package:easyplay/theme_controller.dart';

@JS('easyplayThemeSmoke')
external set _api(JSObject value);
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  final theme = ThemeController();
  _api =
      {
            'state': (() => jsonEncode({
              'appearance': theme.appearance.name,
              'style': theme.paletteStyle.name,
              'spec': theme.colorSpec.name,
              'scale': theme.pageScale,
              'seed': theme.keyColor?.toARGB32(),
              'lightPrimary': theme
                  .scheme(dark: false, color: theme.keyColor)
                  .primary
                  .toARGB32(),
              'darkSurface': theme
                  .scheme(dark: true, color: theme.keyColor)
                  .surface
                  .toARGB32(),
              'loaded': theme.lightSchemes.isNotEmpty,
              'error': theme.error,
            }).toJS).toJS,
            'scale':
                ((JSNumber value) => theme
                        .setScale(value.toDartDouble)
                        .then((_) => true.toJS)
                        .toJS)
                    .toJS,
          }.jsify()
          as JSObject;
  runApp(EasyPlayApp(themeController: theme));
}
