import 'package:flutter/foundation.dart';

class AppLanguage {
  static final ValueNotifier<bool> isEnglish = ValueNotifier<bool>(false);

  static String text(String vietnamese, String english) {
    return isEnglish.value ? english : vietnamese;
  }
}
