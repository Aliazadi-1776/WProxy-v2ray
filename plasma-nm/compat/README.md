`vpnuiplugin.h` and `settingwidget.h` are unmodified interface headers from
[KDE plasma-nm v6.7.5](https://github.com/KDE/plasma-nm/tree/v6.7.5/libs/editor),
tag commit `5bd2955209970a7208b782a6d5f2e6c1ad5226a8`.

They retain KDE's copyright notices and are used under LGPL-2.1, whose text is
in `COPYING.LGPL-2.1`. No KDE implementation is bundled. WProxy dynamically
links the distribution's `libplasmanm_editor` and Qt/KF libraries.

These are private Plasma interfaces, not a stable public SDK. Build against
the installed Plasma 6.7 or newer runtime and run the factory/widget test
before installation; older ABIs are not supported. The generated export-header
replacement only marks the installed library's declarations as imports.
