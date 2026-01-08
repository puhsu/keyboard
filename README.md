# Keyboard config

- nix develop environment with zephyr sdk and west (dependency fetcher)
- keymap defined in config
- a wip (should be mostly done soon)

## Build Instructions 

1. Have nix installed
2. just init 
3. just build (all or just build right - if only changing the keymap)

## Details 

Core pillars of the setup:

- colemak based (with transliterated cyrillic)
- use home row modifiers (turns out it is very pleasent to use)
- integration with emacs (GUI-META-CTRL, only three)
- less layers (trying to make to with just two)
- shift is already a layer switcher and the os supports it

**Work in progress**:
- Some high level overview of the keyboard like firmware and stuff (the questions I had along the way of setting it all up)
- [x] base colemak layout with working home row modes
- [ ] document misfiers and annoyances to fix later
  - doing something like C-a and then C-e right after it is a bit hard (albeit I may get used to it). Kinda got used to it.
  - C-x b triggers false taps (not sure why, will probably get used to it)
  - shift on the left pinky is a bit hard to reach (possibly only when using it in combinations like shift + sym + 
  - using keybindings with numbers is tough right now.
  - sometimes I'm triggering key presses instead of a shortcut for very very fast shortcuts
  - mouse does not have smooth scrolling
  - mouse layer is badly developed
- symbols and navigation layers need a bit of tweaking (see the shift observation above)
- [x] russian layer is needed - something like my rulemak layout, but in the firmware for the regular russian os keyboard
- [x] Kmonad or Kanata config that matches my custom keyboard but in software
  - integrate kanata into the system more natively (add a shortcut to quickly disable it)

I try to define layout either in keyboard firmware, or (in the future) using Kmonad or Kanata. This way I can use my keyboard or config with any OS or computer keeping my colemak and custom keyboard muscle memory without depending on the os (I need an os to have a regular english and russian layout still, but not some custom stuff).

Keymap visualized (simply):

```
#define _ = None

Base layer (Colemak-DH with home row mods):

ESC      Q   W       F       P        G        |        J   L        U       Y       ;    BSPC
TAB      A   R/GUI   S/ALT   T/CTRL   D        |        H   N/CTRL   E/ALT   I/GUI   O    '
LSHIFT   Z   X       C       V        B        |        K   M        ,       .       /    RSHIFT
             -       -       SPC      L1   -   |  RET   L2  -        -       -


Sym layer (L2):

_        1   2       3       4        5        |        6   7        8       9       0    _
_        _   _       _       _        _        |        _   _        _       _       -    _
_        _   _       (       )        _        |        _   [        ]       _       =    _
             _       _       _        L3   _   |  _     _   _        _       _
```

this was a fucking holiday nerd-snipe for sure...
