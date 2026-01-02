# Keyboard config

- nix develop environment with zephyr sdk and west (dependency fetcher)
- keymap defined in config
- a wip (should be mostly done soon)

## Build Instructions 

1. Have nix installed (direnv prefarably too: to have shell env available with the build-related commands).
2. just init 
3. just build (all or just build right - if only changing the keymap, and not something like bleutooth settings or firmware updates).

## Details 

**TODO** Some high level overview of the keyboard, firmware and stuff (the questions I had along the way of setting it all up)

I try to define layout either in keyboard firmware, or (in the future) using Kmonad or Kanata. This way I can use my keyboard or config with any OS or computer keeping my colemak and custom keyboard muscle memory without depending on the os (I need an os to have a regular english and russian layout still, but not some custom stuff).

Keymap visualized (simply):

```
#define 0 = None
#define * = layer switch

ESC      q   w   f     p     g              |           j   l   u   y   ;   BSPC
TAB      a   r   s     t     d              |           h   n   e   i   o   '
`        z   x   c     v     b              |           k   m   ,   .   /   0
             0   0    SPC    *   LSHIFT     |    RET    *   _   0   0

```

this was a fucking holiday nerd-snipe for sure...

