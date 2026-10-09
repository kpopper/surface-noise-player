import 'package:flutter/widgets.dart';

// Windows at least this wide (the macOS app at its default size, not an
// iPhone) get the wide layout: sidebar, cover grid, side release panel and
// a bottom player bar, instead of the stacked phone screens.
const double kWideLayoutMinWidth = 900;

bool isWideLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kWideLayoutMinWidth;
