# jellyfin-rusticl

`jellyfin/jellyfin` (arm64) plus Mesa built from main with three local fixes (`fixes.patch`), giving OpenCL through rusticl on zink on panvk for the Mali G610 of the RK3588. Jellyfin's `tonemap_opencl` uses it.

Image: `ghcr.io/lywel/jellyfin-rusticl:<jellyfin tag>-mesa-<first 7 chars of the Mesa commit>`, e.g. `12.4-mesa-ef59438`.

`JELLYFIN_TAG` and `MESA_COMMIT` are set at the top of the `Dockerfile`. The Jellyfin base is also pinned by digest there: update it together with the tag.
