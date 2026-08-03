# Icon110

A minimal SpringBoard tweak based on Atria's icon-layer scaling approach.

- Fixed app/folder icon scale: 110%
- Widgets remain at the system scale
- No settings bundle
- No PreferenceLoader, Alderis, or other third-party tweak libraries
- Injects only into `com.apple.springboard`

Build with Theos:

```sh
make package FINALPACKAGE=1
```

