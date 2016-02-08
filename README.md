# DWin-Bar

A taskbar for linux designed for DWin. Also works with other window managers implementing the EWMH standard.

![DWin Bar Example at the bottom on a 1280x800 display with clock and workspace widgets](https://i.imgur.com/aqVt0Xh.png)

Setting up bars currently only works in the source code, however the API is really simple. If you want to change
the orientation, screens or widgets simply change source/app.d and rebuild using `dub`. There is a widget interface
in source/widgets which can be extended and added to the bars. The clock widget is a good widget to base on.